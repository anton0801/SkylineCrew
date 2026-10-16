#if DEBUG
import SwiftUI

/// Reproduces the 42 design states of design/screens.json in memory for simulator comparison.
/// Launch with `-fixture 09` (any screen id). Demo numbers never reach the player's real profile:
/// fixtures use InMemoryProfileRepository and silent audio.
final class FixtureClock: Clock {
    let now: Date
    init(hour: Int = 9, minute: Int = 41) {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        now = Calendar.current.date(from: c) ?? Date()
    }
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

@MainActor
enum FixtureFactory {
    static func make(id: String, content: GameContent) -> AppModel {
        let clock = FixtureClock()
        let now = clock.now
        var profile = demoProfile(content: content, now: now)
        var stack: [Route] = [.home]
        var dialog: DialogKind?
        var flags: Set<String> = []
        var gameSetup: ((AppModel) -> GameController?)?
        var recovery: RecoveryInfo?
        var pending: SaveContext?

        switch id {
        case "01", "02", "03":
            profile = fresh(content, now)
            profile.onboarding = OnboardingState(step: Int(id)! - 1, completed: false)
            stack = (0..<Int(id)!).map { .onboarding($0) }
        case "04": stack = [.home]
        case "05": stack = [.home, .districts]
        case "38": stack = [.home, .districts]; flags.insert("districtsBottom")
        case "06": stack = [.home, .districts, .levelMap(1)]
        case "07": stack = [.home, .levelMap(1), .brief(12)]
        case "08":
            gameSetup = { app in tutorial(app, content: content, now: now) }
            stack = [.play]
        case "09", "10", "11", "12", "13", "14", "15", "16", "39", "40":
            gameSetup = { app in game(id, app: app, content: content, now: now) }
            stack = [.home, .play]
        case "17", "18", "19":
            profile.lastResult = result(id, content: content, now: now)
            stack = [.home, .results]
        case "20": stack = [.home, .collection, .freeBuild]
        case "41":
            profile = partialProfile(content, now, levels: 2)
            stack = [.home, .collection]
            dialog = .freeBuildLocked
        case "21":
            profile.daily = DailyState()
            stack = [.home, .daily]
        case "22", "23":
            let receipt = DailyReceipt(id: UUID(), roll: 72, bandIndex: 1, bolts: 35, symbols: ["R02", "R02", "F03"],
                                       claimedAt: now, presented: true)
            profile.daily = DailyState(nextEligibleAt: now.addingTimeInterval(86_400), lastReceipt: receipt)
            flags.insert(id == "22" ? "dailySpinning" : "dailyReceived")
            stack = [.home, .daily]
        case "24":
            let receipt = DailyReceipt(id: UUID(), roll: 12, bandIndex: 0, bolts: 20, symbols: ["F01", "F02", "F03"],
                                       claimedAt: now.addingTimeInterval(-20_000), presented: true)
            profile.daily = DailyState(nextEligibleAt: now.addingTimeInterval(18 * 3600 + 24 * 60 + 30), lastReceipt: receipt)
            stack = [.home, .daily]
        case "25": stack = [.home, .workshop]
        case "25b":
            profile.walletBalance = 45
            stack = [.home, .workshop]
            dialog = .themeLocked("ocean")
        case "26": stack = [.home, .collection]
        case "27":
            profile = demoProfile(content: content, now: now, includeLevel12: true)
            stack = [.home, .collection, .towerDetail(.level(12))]
        case "28":
            profile = fresh(content, now)
            stack = [.home, .collection]
        case "29": stack = [.home, .settings]
        case "30": stack = [.home, .settings, .help]
        case "31": stack = [.home, .settings, .stats]
        case "32": stack = [.home, .settings, .data]
        case "33": stack = [.home, .settings, .data]; dialog = .resetConfirm
        case "34": stack = [.home]; dialog = .saveProblem; pending = .game
        case "35":
            profile = partialProfile(content, now, levels: 120)
            stack = [.home, .cityComplete]
        case "36": recovery = RecoveryInfo(backupAvailable: true, futureSchema: false, reason: "fixture")
        case "37":
            profile = fresh(content, now)
            stack = [.home]
        default: break
        }

        let repo = InMemoryProfileRepository(profile: profile)
        let app = AppModel(content: content, repository: repo, clock: clock, random: FixedRandomSource([72]),
                           audio: SilentAudio(), haptics: SilentHaptics(), isFixture: true)
        app.fixtureFlags = flags
        if let recovery { app.forceRecoveryForFixture(recovery) }
        if let pending { app.setPendingSaveForFixture(context: pending) }
        app.installFixture(stack: stack, dialog: dialog, game: gameSetup?(app))
        return app
    }

    // MARK: Profiles

    static func fresh(_ content: GameContent, _ now: Date) -> Profile {
        var p = Profile.fresh(now: now)
        p.onboarding = OnboardingState(step: 2, completed: true)
        p.tutorialSeen = true
        return p
    }

    /// 06 shows levels 1–11 with ★★ ★★★ ★★★ ★★ ★★★ ★★★ ★★ ★★★ ★★★ ★★ ★★ (28 stars), 145 Bolts, Level 12 next.
    static func demoProfile(content: GameContent, now: Date, includeLevel12: Bool = false) -> Profile {
        var p = fresh(content, now)
        let stars = [2, 3, 3, 2, 3, 3, 2, 3, 3, 2, 2]
        for (i, s) in stars.enumerated() {
            let level = content.level(i + 1)!
            p.levelBests.append(best(level, stars: s, now: now))
        }
        if includeLevel12 {
            p.levelBests.append(best(content.level(12)!, stars: 3, now: now, precision: 0.94))
        }
        p.walletBalance = 145
        let free = (0..<16).map { i in Placement(centerX: 0, accuracy: 0.9, assetID: content.floorAsset(index: i, level: nil, themeID: "original"), kind: .normal) }
        p.freeBest = FreeBuildRecord(sessionID: UUID(), height: 16, precision: 0.9, layout: free, date: now, assisted: false, outcome: .fell)
        p.freeLast = p.freeBest
        return p
    }

    private static func best(_ level: LevelConfig, stars: Int, now: Date, precision: Double? = nil) -> LevelBest {
        let p = precision ?? (stars == 3 ? 0.95 : stars == 2 ? 0.87 : 0.7)
        let layout = level.floorSequence.map { Placement(centerX: 0, accuracy: p, assetID: $0, kind: .normal) }
        return LevelBest(levelID: level.id, bestStars: stars, bestPrecision: p, layout: layout, layoutPrecision: p,
                         layoutDate: now, layoutAssisted: false, firstClearedAt: now, clears: 1)
    }

    static func partialProfile(_ content: GameContent, _ now: Date, levels: Int) -> Profile {
        var p = fresh(content, now)
        p.levelBests = (1...levels).map { best(content.level($0)!, stars: 3, now: now) }
        p.walletBalance = 145
        return p
    }

    // MARK: Results

    private static func result(_ id: String, content: GameContent, now: Date) -> RunResult {
        let level = content.level(12)!
        let layout = level.floorSequence.map { Placement(centerX: 0, accuracy: 1, assetID: $0, kind: .perfect) }
        switch id {
        case "17":
            return RunResult(sessionID: UUID(), mode: .campaign(levelID: 12), success: true, failReason: nil, floors: 8, targetFloors: 8,
                             precision: 0.94, stars: 3, previousBestStars: 0, bolts: 30, firstClear: true, newBestPrecision: true,
                             assisted: false, layout: layout, freeOutcome: nil, newRecord: false, unlockedDistrict: nil, date: now)
        case "18":
            return RunResult(sessionID: UUID(), mode: .campaign(levelID: 12), success: true, failReason: nil, floors: 8, targetFloors: 8,
                             precision: 0.76, stars: 1, previousBestStars: 0, bolts: 20, firstClear: true, newBestPrecision: true,
                             assisted: false, layout: layout, freeOutcome: nil, newRecord: false, unlockedDistrict: nil, date: now)
        default:
            return RunResult(sessionID: UUID(), mode: .campaign(levelID: 12), success: false, failReason: .missedSupport, floors: 5,
                             targetFloors: 8, precision: 0, stars: 0, previousBestStars: 0, bolts: 0, firstClear: false,
                             newBestPrecision: false, assisted: false, layout: Array(layout.prefix(5)), freeOutcome: nil,
                             newRecord: false, unlockedDistrict: nil, date: now)
        }
    }

    // MARK: Gameplay states (09–16, 39, 40)

    /// The hanging floor in the mockups is drawn at x=167 (center 254): 59 pt right of the tower axis.
    private static let mockHangingOffset = 59.0 * 180.0 / 174.0

    private static func game(_ id: String, app: AppModel, content: GameContent, now: Date) -> GameController? {
        let levelID = id == "11" ? 26 : 12
        let level = content.level(levelID)!
        var s = StartRun(content: content).campaign(level: level, settings: GameSettings(), now: now)
        let placed = id == "10" ? 7 : (id == "11" ? 5 : 6)
        let pt = 180.0 / 174.0
        let unevenOffsets: [Double] = [-7, 0, 7, -7, 0, 7].map { $0 * pt }
        s.placements = (0..<placed).map { i in
            let x = id == "12" ? unevenOffsets[i] : 0
            return Placement(centerX: x, accuracy: 1, assetID: level.floorSequence[i], kind: .perfect)
        }
        s.strain = id == "12" ? 72 : 28
        s.streak = 2
        var overlay: GameOverlay?
        var offset: Double? = mockHangingOffset
        switch id {
        case "10":
            s.stage = .settling
            s.stageTime = 0.2
            s.lastLanding = .perfect
            offset = nil
        case "13":
            s.stage = .dropping
            s.stageTime = 0
            s.planned = PlannedPlacement(dx: mockHangingOffset, assetID: level.floorSequence[placed], braced: false, commandID: UUID())
        case "14":
            s.braceCharged = true
            s.streak = 0
        case "39":
            s.braceArmed = true
            s.streak = 0
        case "40":
            s.isPaused = true
            overlay = .countdown(3)
        case "15":
            s.isPaused = true
            overlay = .paused
        case "16":
            s.isPaused = true
            overlay = .restartConfirm
        default:
            break
        }
        if id == "12" { offset = (212 - 195) * pt - s.topX }
        guard let c = app.makeFixtureController(session: s) else { return nil }
        c.installFixture(session: s, overlay: overlay, hangingOffset: offset)
        return c
    }

    private static func tutorial(_ app: AppModel, content: GameContent, now: Date) -> GameController? {
        let level = content.level(1)!
        var s = StartRun(content: content).tutorial(level: level, themeID: "original", now: now)
        s.strain = 28
        s.streak = 2
        guard let c = app.makeFixtureController(session: s) else { return nil }
        c.installFixture(session: s, overlay: nil, hangingOffset: mockHangingOffset)
        return c
    }
}
#endif
