import SwiftUI
import QuartzCore

enum GameOverlay: Equatable {
    case paused
    case restartConfirm
    case countdown(Int)
}

struct HUDState: Equatable {
    var title: String
    var progress: String
    var objective: String
    var strain: Int
    var maxStrain: Int
    var streakLine: String
    var braceCharged: Bool
    var braceArmed: Bool
    var dropEnabled: Bool
    var dropLooksDisabled: Bool
    var dropTitle: String
    var windArrow: String?
    var tutorialHint: [String]?
    var floorCount: Int
    /// DEBUG UI-test aid: the hanging floor is inside the perfect window.
    var aligned = false
}

/// Presentation-side owner of one run: feeds active time and commands into the pure reducer,
/// maps events to audio/haptics/scene cues and persists snapshots at the documented moments.
@MainActor
final class GameController: ObservableObject {
    weak var app: AppModel?
    let engine: RunEngine
    private(set) var session: RunSession
    let level: LevelConfig?
    let tutorialOrigin: TutorialOrigin?
    let scene: GameScene

    @Published private(set) var hud: HUDState
    @Published private(set) var overlay: GameOverlay?

    /// Fixture rendering: freezes model time at an exact state.
    var frozen = false
    var fixtureHangingOffset: Double?

    private var lastTick: CFTimeInterval?
    private var countdownItems: [DispatchWorkItem] = []
    private var finishing = false
    private var restarting = false
    private var craneLoopOn = false
    private(set) var cues: [RunEvent] = []

    var mode: RunMode { session.mode }
    var background: String {
        switch session.mode {
        case .campaign: return level?.background ?? "BG01"
        case .freeBuild: return "BG03"
        case .tutorial: return "BG01"
        }
    }

    init(app: AppModel, engine: RunEngine, session: RunSession, level: LevelConfig?, tutorialOrigin: TutorialOrigin?) {
        self.app = app
        self.engine = engine
        var s = session
        // Timing Assist chosen in Settings (before the run or while it was paused) applies on entry.
        if s.mode != .tutorial {
            engine.reduce(&s, .setTimingAssist(app.profile.settings.timingAssist))
        }
        self.session = s
        self.level = level
        self.tutorialOrigin = tutorialOrigin
        self.scene = GameScene()
        self.hud = HUDState(title: "", progress: "", objective: "", strain: 0, maxStrain: 100, streakLine: "",
                            braceCharged: false, braceArmed: false, dropEnabled: false, dropLooksDisabled: false,
                            dropTitle: "Drop Floor", windArrow: nil, tutorialHint: nil, floorCount: 0)
        scene.controller = self
        scene.reduceMotion = app.reduceMotion
        refreshHUD()
    }

    var audio: AudioService? { app?.audio }

    var isRunning: Bool {
        overlay == nil && !session.isPaused && !session.stage.isTerminal && !frozen && !finishing
            && app?.dialog == nil && (app?.scenePhaseActive ?? true)
    }

    // MARK: Frame loop (called by the scene on the main thread)

    func tick(_ now: CFTimeInterval) {
        guard isRunning else {
            lastTick = nil
            updateCraneLoop()
            return
        }
        guard let last = lastTick else { lastTick = now; updateCraneLoop(); return }
        lastTick = now
        let dt = min(max(0, now - last), 0.25)
        if dt > 0 { apply(.advance(dt: dt)) }
        updateCraneLoop()
    }

    func hangingOffset() -> Double {
        if let fixtureHangingOffset, session.stage == .aiming { return fixtureHangingOffset }
        return engine.hangingOffset(session)
    }

    func drainCues() -> [RunEvent] {
        defer { cues.removeAll() }
        return cues
    }

    private func apply(_ command: RunCommand) {
        let events = engine.reduce(&session, command)
        for e in events { handle(e) }
        refreshHUD()
    }

    // MARK: Player commands

    func dropTapped() {
        guard isRunning, engine.canRelease(session) else { return }
        // Catch the model up to the exact touch-up moment (monotonic clock) before fixing dx.
        let now = CACurrentMediaTime()
        if let last = lastTick, now > last, now - last < 0.1 {
            apply(.advance(dt: now - last))
            lastTick = now
        }
        apply(.release(commandID: UUID()))
    }

    func braceTapped() {
        guard isRunning, engine.canArmBrace(session) else {
            audio?.play(.unavailable)
            return
        }
        apply(.armBrace(commandID: UUID()))
        persist()
    }

    func pauseTapped() {
        guard !session.stage.isTerminal, !finishing else { return }
        if case .countdown = overlay { cancelCountdown() }
        guard overlay == nil || overlay != .paused else { return }
        enterPause(sound: true)
    }

    private func enterPause(sound: Bool) {
        cancelCountdown()
        engine.reduce(&session, .setPaused(true))
        overlay = .paused
        lastTick = nil
        scene.isPaused = true
        if sound { audio?.play(.sheetOpen) }
        audio?.stopAllLoops()
        updateCraneLoop()
        refreshHUD()
        persist(sync: true)
    }

    func resumeTapped() {
        guard overlay == .paused else { return }
        startCountdown()
    }

    /// Entering an unfinished tower from Home: always an explicit 3-2-1.
    func enterResumed() {
        engine.reduce(&session, .setPaused(true))
        scene.isPaused = true
        startCountdown()
    }

    private func startCountdown() {
        cancelCountdown()
        let reduce = app?.reduceMotion ?? false
        audio?.play(.countdown)
        if reduce {
            overlay = .countdown(1)
            schedule(after: 0.3) { [weak self] in self?.finishCountdown() }
        } else {
            overlay = .countdown(3)
            schedule(after: 1) { [weak self] in self?.overlay = .countdown(2); self?.audio?.play(.countdown) }
            schedule(after: 2) { [weak self] in self?.overlay = .countdown(1); self?.audio?.play(.countdown) }
            schedule(after: 3) { [weak self] in self?.finishCountdown() }
        }
        refreshHUD()
    }

    private func finishCountdown() {
        countdownItems.removeAll()
        audio?.play(.start)
        engine.reduce(&session, .setPaused(false))
        overlay = nil
        lastTick = nil
        scene.isPaused = false
        audio?.resumeMusicIfNeeded()
        app?.updateMusic()
        refreshHUD()
    }

    private func schedule(after seconds: Double, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        countdownItems.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelCountdown() {
        countdownItems.forEach { $0.cancel() }
        countdownItems.removeAll()
    }

    func restartTapped() {
        guard overlay == .paused else { return }
        audio?.play(.sheetOpen)
        overlay = .restartConfirm
    }

    func keepBuilding() {
        audio?.play(.sheetClose)
        overlay = .paused
    }

    /// Explicit replacement of the current attempt; best results stay. Double taps create one session.
    func confirmRestart() {
        guard !restarting else { return }
        restarting = true
        cancelCountdown()
        audio?.play(.sheetClose)
        app?.restartRun(from: session)
    }

    func homeTapped() {
        cancelCountdown()
        if session.mode != .tutorial { persist(sync: true) }
        app?.goHome()
    }

    func skipTutorial() {
        guard let origin = tutorialOrigin else { return }
        cancelCountdown()
        finishing = true
        app?.endTutorial(origin: origin, skipped: true)
    }

    // MARK: Lifecycle

    func appWillResignActive() {
        guard !session.stage.isTerminal, !finishing else { return }
        if overlay == nil || { if case .countdown = overlay { return true }; return false }() {
            enterPause(sound: false)
        } else {
            persist(sync: true)
        }
    }

    func saveFailed() {
        cancelCountdown()
        engine.reduce(&session, .setPaused(true))
        lastTick = nil
        scene.isPaused = true
        if overlay == nil || overlay != .paused { overlay = nil }
        updateCraneLoop()
    }

    func showPauseAfterSaveProblem() {
        overlay = .paused
        refreshHUD()
    }

    func settingsChanged() {
        guard let app else { return }
        scene.reduceMotion = app.reduceMotion
        if session.mode != .tutorial { apply(.setTimingAssist(app.profile.settings.timingAssist)) }
    }

    func teardown() {
        cancelCountdown()
        if craneLoopOn { audio?.setAmbience(.craneMotor, on: false); craneLoopOn = false }
        scene.isPaused = true
    }

    // MARK: Events → audio / haptics / persistence

    private func handle(_ e: RunEvent) {
        cues.append(e)
        let haptics = app?.haptics
        switch e {
        case .released:
            audio?.play(.release)
            audio?.play(.fallAir)
            persist()
        case .landed(_, let material, _):
            switch material {
            case .wood: audio?.play(.landWood)
            case .stone: audio?.play(.landStone)
            case .metal: audio?.play(.landMetal)
            }
            haptics?.play(.landing)
            persist()
        case .perfect(let streak):
            audio?.play(streak == 2 ? .perfectTwo : .perfectOne)
            haptics?.play(.perfect)
        case .braceCharged:
            audio?.play(.braceReady)
            haptics?.play(.perfect)
        case .braceArmed:
            audio?.play(.braceUse)
        case .strainCrossed:
            audio?.play(.strain)
        case .missed:
            audio?.play(.miss)
            haptics?.play(.failure)
        case .tooMuchStrain:
            audio?.play(.strain)
            haptics?.play(.failure)
        case .failed:
            finish(delay: 0.15)
        case .won:
            finish(delay: session.mode == .tutorial ? 0.6 : 0.5)
        case .beaconLit:
            audio?.play(.beacon)
        case .roofStarted, .aimingStarted, .tutorialRetry, .rejected:
            break
        }
    }

    private func finish(delay: Double) {
        guard !finishing else { return }
        finishing = true
        updateCraneLoop()
        let snapshot = session
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let app = self.app else { return }
            if snapshot.mode == .tutorial {
                app.endTutorial(origin: self.tutorialOrigin ?? .help, skipped: false)
            } else {
                app.finishRun(snapshot)
            }
        }
    }

    /// Gameplay commits (release/resolve) are written off the main thread; pause, Home and
    /// background are written synchronously so nothing is lost if the app is suspended.
    private func persist(sync: Bool = false) {
        guard session.mode != .tutorial, !frozen, !finishing else { return }
        app?.saveSnapshot(session, async: !sync)
    }

    private func updateCraneLoop() {
        let want = isRunning && session.stage == .aiming
        guard want != craneLoopOn else { return }
        craneLoopOn = want
        audio?.setAmbience(.craneMotor, on: want)
    }

    // MARK: HUD

    func refreshHUD() {
        let s = session
        let target = engine.context.targetFloors
        var h = HUDState(title: "", progress: "", objective: "Build to the rooftop beacon",
                         strain: s.strain, maxStrain: engine.context.maxStrain, streakLine: "",
                         braceCharged: s.braceCharged, braceArmed: s.braceArmed,
                         dropEnabled: false, dropLooksDisabled: false, dropTitle: "Drop Floor",
                         windArrow: nil, tutorialHint: nil, floorCount: s.floorCount)
        switch s.mode {
        case .campaign(let id):
            h.title = "LEVEL \(id)"
            h.progress = "\(s.floorCount) / \(target ?? 0) FLOORS"
        case .freeBuild:
            h.title = "FREE BUILD"
            h.progress = "\(s.floorCount) FLOORS"
            h.objective = "Build as high as you can"
        case .tutorial:
            let step = engine.context.tutorialStep(s)
            h.title = "PRACTICE"
            h.progress = "STEP \(min(step + 1, RunRules.tutorialSteps)) / \(RunRules.tutorialSteps)"
            switch step {
            case 0: h.tutorialHint = ["Tap when the glowing", "edges line up."]
            case 1: h.tutorialHint = ["Off-center floors", "add strain."]
            case 2: h.tutorialHint = ["Three perfect drops", "charge a brace."]
            default:
                h.tutorialHint = s.braceArmed ? ["Brace armed. Now", "drop the floor."] : ["Tap the brace,", "then drop."]
            }
        }
        if s.braceArmed {
            h.streakLine = "Brace armed · Next drop is steady"
        } else if s.braceCharged {
            h.streakLine = "Brace ready · Tap support"
        } else {
            h.streakLine = "\(s.streak) / \(engine.context.braceThreshold) perfect drops"
        }
        let countdown: Bool = { if case .countdown = overlay { return true }; return false }()
        h.dropEnabled = isRunning && engine.canRelease(s)
        switch s.stage {
        case .dropping:
            h.dropTitle = "Dropping…"
            h.dropLooksDisabled = true
        case .roofing, .won, .failed, .failing:
            h.dropLooksDisabled = true
        case .aiming:
            h.dropLooksDisabled = countdown || !engine.canRelease(s)
        case .settling:
            h.dropLooksDisabled = countdown
        }
        let aim = engine.aim(s)
        if aim.windAmplitude > 0 {
            let m = AimParameters.windMultiplier(floorCount: s.floorCount, flips: aim.windFlips)
            let push = m * aim.windAmplitude * sin(aim.windOmega * s.stageTime + aim.psi)
            h.windArrow = push >= 0 ? "→" : "←"
        }
        #if DEBUG
        if Self.exposeAlignment, s.stage == .aiming {
            h.aligned = abs(engine.hangingOffset(s)) <= engine.context.width * 0.03
        }
        #endif
        if h != hud { hud = h }
    }

    #if DEBUG
    static let exposeAlignment = UserDefaults.standard.bool(forKey: "uitestAimHint")
    #endif

    // MARK: Fixtures

    func installFixture(session: RunSession, overlay: GameOverlay?, hangingOffset: Double?) {
        self.session = session
        self.overlay = overlay
        self.frozen = true
        self.fixtureHangingOffset = hangingOffset
        scene.isPaused = overlay != nil
        refreshHUD()
    }
}
