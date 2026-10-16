import SwiftUI
import UIKit

enum TowerRef: Hashable {
    case level(Int)
    case freeBest
}

/// Typed routes (iOS 15: own router instead of NavigationStack).
enum Route: Hashable {
    case onboarding(Int)
    case home
    case districts
    case levelMap(Int)
    case brief(Int)
    case play
    case results
    case freeBuild
    case daily
    case workshop
    case collection
    case towerDetail(TowerRef)
    case settings
    case help
    case stats
    case data
    case cityComplete
}

/// Full-screen confirmation/problem states (15/16 are owned by the game screen).
enum DialogKind: Equatable {
    case themeLocked(String)
    case themeUnlock(String)
    case resetConfirm
    case saveProblem
    case freeBuildLocked
    /// nil = Free Build.
    case replaceSession(newLevelID: Int?)
}

enum TutorialOrigin: Equatable {
    case onboarding
    case help
}

enum SaveContext: Equatable {
    case general
    case game
    case daily
}

struct PendingSave {
    var profile: Profile
    var context: SaveContext
    var onSuccess: (() -> Void)?
}

enum AppPhase: Equatable {
    case ready
    case recovery(RecoveryInfo)
}

@MainActor
final class AppModel: ObservableObject {
    let content: GameContent
    let repository: ProfileRepository
    let clock: Clock
    let random: RandomSource
    let audio: AudioService
    let haptics: HapticService
    let isFixture: Bool

    @Published private(set) var profile: Profile
    @Published var phase: AppPhase = .ready
    @Published private(set) var stack: [Route]
    @Published var dialog: DialogKind?
    @Published private(set) var pendingSave: PendingSave?
    @Published var navForward = true
    @Published private(set) var game: GameController?
    /// A failed save blocks new sessions until it is resolved.
    @Published private(set) var saveBlocked = false
    @Published var scenePhaseActive = true

    var route: Route { stack.last ?? .home }
    var campaign: Campaign { Campaign(content: content, profile: profile) }
    var reduceMotion: Bool { profile.settings.reducedMotion || UIAccessibility.isReduceMotionEnabled }
    var isNewPlayer: Bool { profile.completedCount == 0 && profile.activeSession == nil }

    init(content: GameContent, repository: ProfileRepository, clock: Clock, random: RandomSource,
         audio: AudioService, haptics: HapticService, isFixture: Bool = false) {
        self.content = content
        self.repository = repository
        self.clock = clock
        self.random = random
        self.audio = audio
        self.haptics = haptics
        self.isFixture = isFixture
        self.stack = [.home]
        self.profile = Profile.fresh(now: clock.now)
        load()
    }

    // MARK: Loading & recovery

    func load() {
        switch repository.load() {
        case .fresh:
            var p = Profile.fresh(now: clock.now, initialBalance: content.economy.initialBalance)
            p.settings.reducedMotion = UIAccessibility.isReduceMotionEnabled
            profile = p
            phase = .ready
            try? repository.save(p)
        case .loaded(let p):
            profile = p
            phase = .ready
        case .recovery(let info):
            phase = .recovery(info)
        }
        applySettingsToServices()
        stack = [initialRoute()]
    }

    private func initialRoute() -> Route {
        profile.onboarding.completed ? .home : .onboarding(min(2, max(0, profile.onboarding.step)))
    }

    func restoreBackup() {
        do {
            profile = try repository.restoreBackup()
            phase = .ready
            applySettingsToServices()
            stack = [initialRoute()]
        } catch {
            phase = .recovery(RecoveryInfo(backupAvailable: false, futureSchema: false, reason: "backup"))
        }
    }

    func retryLoad() { load() }

    /// Start Fresh after explicit confirmation (33). The damaged file was already preserved by the repository.
    func startFresh() {
        let fresh = ResetProfile().execute(phase == .ready ? profile : nil, now: clock.now)
        dialog = nil
        do {
            try repository.save(fresh)
            profile = fresh
            phase = .ready
            game = nil
            saveBlocked = false
            pendingSave = nil
            applySettingsToServices()
            navForward = false
            stack = [initialRoute()]
        } catch {
            pendingSave = PendingSave(profile: fresh, context: .general, onSuccess: nil)
            dialog = .saveProblem
        }
    }

    // MARK: Transactions

    /// Persist first, publish after successful I/O. A failure opens 34 and keeps the pending state for Retry.
    private let storageQueue = DispatchQueue(label: "skylinecrew.storage", qos: .userInitiated)
    private var commitVersion = 0

    @discardableResult
    func commit(_ new: Profile, context: SaveContext = .general, onSuccess: (() -> Void)? = nil) -> Bool {
        var p = new
        p.lastSeenWall = max(p.lastSeenWall, clock.now)
        commitVersion += 1
        do {
            // Same serial queue as snapshots: an earlier snapshot can never overwrite this commit.
            try storageQueue.sync { try repository.save(p) }
            profile = p
            pendingSave = nil
            saveBlocked = false
            if dialog == .saveProblem { dialog = nil }
            onSuccess?()
            return true
        } catch {
            pendingSave = PendingSave(profile: p, context: context, onSuccess: onSuccess)
            saveBlocked = true
            game?.saveFailed()
            dialog = .saveProblem
            return false
        }
    }

    /// Retry re-commits exactly the same transaction (same IDs, same receipt).
    func retrySave() {
        guard let pending = pendingSave else { dialog = nil; return }
        commit(pending.profile, context: pending.context, onSuccess: pending.onSuccess)
    }

    /// “Back to Tower”: nothing is announced as saved; the session stays in memory, paused.
    func dismissSaveProblem() {
        let context = pendingSave?.context
        dialog = nil
        if context == .game, let game {
            game.showPauseAfterSaveProblem()
        } else if context != .game {
            pendingSave = nil
            saveBlocked = game != nil
        }
    }

    // MARK: Navigation

    func push(_ r: Route) {
        navForward = true
        withAnimation(.easeInOut(duration: 0.28)) { stack.append(r) }
    }

    func pop() {
        guard stack.count > 1 else { return goHome() }
        navForward = false
        withAnimation(.easeInOut(duration: 0.28)) { _ = stack.removeLast() }
    }

    func replaceTop(_ r: Route, forward: Bool = true) {
        navForward = forward
        withAnimation(.easeInOut(duration: 0.28)) {
            if stack.isEmpty { stack = [r] } else { stack[stack.count - 1] = r }
        }
    }

    func setStack(_ routes: [Route], forward: Bool = true) {
        navForward = forward
        withAnimation(.easeInOut(duration: 0.28)) { stack = routes.isEmpty ? [.home] : routes }
    }

    func goHome() {
        if route == .play { leaveGame() }
        setStack([.home], forward: false)
    }

    func popTo(_ r: Route) {
        if let i = stack.lastIndex(of: r) {
            navForward = false
            withAnimation(.easeInOut(duration: 0.28)) { stack = Array(stack.prefix(i + 1)) }
        } else {
            setStack([.home, r], forward: false)
        }
    }

    func playSound(_ cue: SoundCue) { audio.play(cue) }

    // MARK: Music per section

    func updateMusic() {
        switch route {
        case .play:
            if let g = game {
                let district = g.level?.district ?? 0
                audio.setMusic(district == 2 || district == 5 ? .harborBreeze : .steadyHands)
                audio.setAmbience(.cityAir, on: true)
            }
        case .daily, .workshop:
            audio.setMusic(.depotDelivery)
            audio.setAmbience(.cityAir, on: false)
            audio.setAmbience(.craneMotor, on: false)
        default:
            audio.setMusic(.sunnyRooftops)
            audio.setAmbience(.cityAir, on: false)
            audio.setAmbience(.craneMotor, on: false)
        }
    }

    // MARK: Settings

    private func applySettingsToServices() {
        audio.apply(settings: profile.settings)
        haptics.enabled = profile.settings.haptics && !isFixture
    }

    func updateSettings(_ change: (inout GameSettings) -> Void) {
        var p = profile
        change(&p.settings)
        guard p.settings != profile.settings else { return }
        if commit(p) {
            applySettingsToServices()
            game?.settingsChanged()
        }
    }

    // MARK: Onboarding

    func onboardingNext(from step: Int) {
        var p = profile
        p.onboarding.step = min(2, step + 1)
        commit(p)
        push(.onboarding(step + 1))
    }

    func skipOnboarding() {
        var p = profile
        p.onboarding.completed = true
        commit(p) { [weak self] in self?.setStack([.home]) }
    }

    /// “Let’s Build”: one save completes onboarding and opens practice.
    func finishOnboardingAndPractice() {
        var p = profile
        p.onboarding.step = 2
        p.onboarding.completed = true
        commit(p) { [weak self] in self?.startTutorial(origin: .onboarding) }
    }

    // MARK: Runs

    private func makeController(session: RunSession, tutorialOrigin: TutorialOrigin? = nil) -> GameController? {
        let theme = profile.selectedTheme
        let content = self.content
        switch session.mode {
        case .campaign(let id):
            guard let level = content.level(id) else { return nil }
            let ctx = RunContext.campaign(level, reduceMotion: reduceMotion) { content.floorAsset(index: $0, level: level, themeID: theme) }
            return GameController(app: self, engine: RunEngine(context: ctx), session: session, level: level, tutorialOrigin: nil)
        case .freeBuild:
            let ctx = RunContext.freeBuild(reduceMotion: reduceMotion) { content.floorAsset(index: $0, level: nil, themeID: theme) }
            return GameController(app: self, engine: RunEngine(context: ctx), session: session, level: nil, tutorialOrigin: nil)
        case .tutorial:
            guard let level = content.level(1) else { return nil }
            let ctx = RunContext.tutorial(level: level, reduceMotion: reduceMotion) { content.floorAsset(index: $0, level: level, themeID: theme) }
            return GameController(app: self, engine: RunEngine(context: ctx), session: session, level: level, tutorialOrigin: tutorialOrigin ?? .help)
        }
    }

    /// Brief → Start Building. One active session; another unfinished tower needs explicit replacement (16-style).
    func requestStartLevel(_ levelID: Int) {
        guard !saveBlocked else { dialog = .saveProblem; return }
        guard campaign.isUnlocked(levelID) else { audio.play(.unavailable); return }
        if let active = profile.activeSession {
            if active.mode == .campaign(levelID: levelID) {
                resumeActiveSession()
            } else {
                audio.play(.sheetOpen)
                dialog = .replaceSession(newLevelID: levelID)
            }
            return
        }
        startNewLevel(levelID)
    }

    func startNewLevel(_ levelID: Int, replacingRoute: Bool = false) {
        guard let level = content.level(levelID), !saveBlocked else { return }
        dialog = nil
        let session = StartRun(content: content).campaign(level: level, settings: profile.settings, now: clock.now)
        launch(session: session, replacing: replacingRoute)
    }

    func startFreeBuild() {
        guard !saveBlocked else { dialog = .saveProblem; return }
        guard campaign.freeBuildUnlocked else { dialog = .freeBuildLocked; return }
        if let active = profile.activeSession {
            if active.mode == .freeBuild {
                resumeActiveSession()
            } else {
                audio.play(.sheetOpen)
                dialog = .replaceSession(newLevelID: nil)
            }
            return
        }
        let session = StartRun(content: content).freeBuild(settings: profile.settings, now: clock.now)
        launch(session: session, replacing: false)
    }

    private func launch(session: RunSession, replacing: Bool) {
        var p = profile
        p.activeSession = session
        commit(p, context: .general) { [weak self] in
            guard let self, let controller = self.makeController(session: session) else { return }
            self.game = controller
            self.audio.play(.start)
            if replacing { self.replaceTop(.play) } else { self.push(.play) }
            self.updateMusic()
        }
    }

    /// Home “Resume” / same-level Start: re-enter with an explicit 3-2-1.
    func resumeActiveSession() {
        guard let active = profile.activeSession, let controller = makeController(session: active) else { return }
        dialog = nil
        game = controller
        push(.play)
        updateMusic()
        controller.enterResumed()
    }

    func startTutorial(origin: TutorialOrigin) {
        guard let level = content.level(1) else { return }
        let session = StartRun(content: content).tutorial(level: level, themeID: profile.selectedTheme, now: clock.now)
        guard let controller = makeController(session: session, tutorialOrigin: origin) else { return }
        game = controller
        if origin == .onboarding { setStack([.play]) } else { push(.play) }
        updateMusic()
    }

    /// Practice finished or skipped: tutorialSeen is written, no rewards.
    func endTutorial(origin: TutorialOrigin, skipped: Bool) {
        var p = profile
        p.tutorialSeen = true
        commit(p) { [weak self] in
            guard let self else { return }
            self.game = nil
            switch origin {
            case .onboarding:
                if skipped {
                    self.setStack([.home])
                    self.startNewLevel(1)
                } else {
                    self.setStack([.home, .brief(1)])
                }
            case .help:
                self.popTo(.help)
            }
            self.updateMusic()
        }
    }

    /// Writes the result before any reward animation; idempotent per sessionID.
    func finishRun(_ session: RunSession) {
        guard let (p, _) = FinishRun(content: content).execute(profile, session: session, now: clock.now) else { return }
        commit(p, context: .game) { [weak self] in
            guard let self else { return }
            self.game = nil
            self.replaceTop(.results)
            self.updateMusic()
        }
    }

    /// Snapshot of the running session (release/resolve/pause/background).
    /// Written on the serial storage queue so a flush never delays the next touch;
    /// a failure still stops the run and opens 34 with the same snapshot for Retry.
    func saveSnapshot(_ session: RunSession, async: Bool = true) {
        guard session.mode != .tutorial else { return }
        var p = profile
        p.activeSession = session
        p.lastSeenWall = max(p.lastSeenWall, clock.now)
        guard async, !isFixture else { commit(p, context: .game); return }
        commitVersion += 1
        let version = commitVersion
        let repo = repository
        storageQueue.async {
            let ok = (try? repo.save(p)) != nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if ok {
                    if version == self.commitVersion { self.profile = p }
                } else if self.pendingSave == nil {
                    self.pendingSave = PendingSave(profile: p, context: .game, onSuccess: nil)
                    self.saveBlocked = true
                    self.game?.saveFailed()
                    self.dialog = .saveProblem
                }
            }
        }
    }

    func replaceSessionAndStart(levelID: Int?) {
        guard !saveBlocked else { return }
        var p = profile
        p.activeSession = nil
        dialog = nil
        commit(p) { [weak self] in
            if let levelID { self?.startNewLevel(levelID) } else { self?.startFreeBuild() }
        }
    }

    func restartRun(from session: RunSession) {
        guard !saveBlocked else { dialog = .saveProblem; return }
        switch session.mode {
        case .campaign(let id):
            guard let level = content.level(id) else { return }
            let fresh = StartRun(content: content).campaign(level: level, settings: profile.settings, now: clock.now)
            var p = profile
            p.activeSession = fresh
            commit(p, context: .game) { [weak self] in
                guard let self, let c = self.makeController(session: fresh) else { return }
                self.game = c
                self.audio.play(.start)
                self.updateMusic()
            }
        case .freeBuild:
            let fresh = StartRun(content: content).freeBuild(settings: profile.settings, now: clock.now)
            var p = profile
            p.activeSession = fresh
            commit(p, context: .game) { [weak self] in
                guard let self, let c = self.makeController(session: fresh) else { return }
                self.game = c
                self.audio.play(.start)
                self.updateMusic()
            }
        case .tutorial:
            guard let level = content.level(1) else { return }
            let fresh = StartRun(content: content).tutorial(level: level, themeID: profile.selectedTheme, now: clock.now)
            game = makeController(session: fresh, tutorialOrigin: game?.tutorialOrigin)
        }
    }

    func leaveGame() {
        if let g = game { g.teardown() }
        audio.setAmbience(.craneMotor, on: false)
        audio.setAmbience(.cityAir, on: false)
        game = nil
    }

    func handleLifecycle(active: Bool) {
        scenePhaseActive = active
        if active {
            if route != .play || game?.overlay != nil { audio.resumeMusicIfNeeded() }
        } else {
            game?.appWillResignActive()
            audio.stopEffects()
            audio.stopAllLoops()
        }
    }

    // MARK: Daily Supply

    /// Atomically stores wallet, receipt and nextEligibleAt, then the reels may spin.
    func claimSupply(onCommitted: @escaping (DailyReceipt) -> Void) {
        guard !saveBlocked else { dialog = .saveProblem; return }
        let roll = random.nextInt(upperBound: 100)
        guard let (p, receipt) = DailySupply.makeClaim(profile, now: clock.now, roll: roll, config: content.economy.daily) else {
            audio.play(.unavailable)
            return
        }
        commit(p, context: .daily) { onCommitted(receipt) }
    }

    func markSupplyPresented(_ receipt: DailyReceipt) {
        guard var r = profile.daily.lastReceipt, r.id == receipt.id, !r.presented else { return }
        r.presented = true
        var p = profile
        p.daily.lastReceipt = r
        commit(p, context: .daily)
    }

    // MARK: Workshop

    func themeTapped(_ id: String) {
        guard let theme = content.theme(id) else { return }
        if profile.selectedTheme == id { audio.play(.tap); return }
        if profile.ownsTheme(id) {
            if case .success(let p) = Workshop.equip(profile, themeID: id) {
                commit(p) { [weak self] in self?.audio.play(.theme) }
            }
            return
        }
        if profile.walletBalance < theme.cost {
            audio.play(.unavailable)
            dialog = .themeLocked(id)
        } else {
            audio.play(.sheetOpen)
            dialog = .themeUnlock(id)
        }
    }

    func purchaseTheme(_ id: String) {
        switch Workshop.purchase(profile, themeID: id, content: content, now: clock.now) {
        case .success(let p):
            commit(p) { [weak self] in
                self?.dialog = nil
                self?.audio.play(.theme)
            }
        case .failure(.notEnoughBolts):
            dialog = .themeLocked(id)
        case .failure:
            dialog = nil
        }
    }

    // MARK: Reset

    /// Hold Clear Progress 1.5 s → fresh profile (settings, accessibility and onboarding kept) → Home.
    func resetProgress() {
        let fresh = ResetProfile().execute(profile, now: clock.now)
        leaveGame()
        commit(fresh) { [weak self] in
            self?.dialog = nil
            self?.setStack([.home], forward: false)
            self?.updateMusic()
        }
    }

    // MARK: Fixture support

    /// Screen-state switches used only by the 42 design fixtures (never persisted).
    @Published var fixtureFlags: Set<String> = []

    func setPendingSaveForFixture(context: SaveContext) {
        pendingSave = PendingSave(profile: profile, context: context, onSuccess: nil)
        saveBlocked = true
    }

    func installFixture(stack: [Route], dialog: DialogKind?, game: GameController?) {
        self.stack = stack
        self.dialog = dialog
        self.game = game
    }

    func makeFixtureController(session: RunSession) -> GameController? { makeController(session: session, tutorialOrigin: .onboarding) }

    func overrideProfileForFixture(_ p: Profile) { profile = p }
    func forceRecoveryForFixture(_ info: RecoveryInfo) { phase = .recovery(info) }
}
