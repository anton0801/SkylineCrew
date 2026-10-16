import Foundation

// MARK: - Ports (implemented in the Data layer)

enum ProfileLoadResult {
    case fresh
    case loaded(Profile)
    case recovery(RecoveryInfo)
}

struct RecoveryInfo: Equatable {
    var backupAvailable: Bool
    var futureSchema: Bool
    var reason: String
}

/// Implementations serialize writes on one storage queue (see AppModel), hence Sendable.
protocol ProfileRepository: AnyObject, Sendable {
    func load() -> ProfileLoadResult
    /// Atomic write: temp file → flush → replace. The previous valid version stays as backup.
    func save(_ profile: Profile) throws
    /// Loads and validates the backup and promotes it to primary.
    func restoreBackup() throws -> Profile
}

/// The active session lives inside the profile file; this port narrows access to it.
protocol SessionRepository: AnyObject {
    func saveSession(_ session: RunSession?, into profile: Profile) throws -> Profile
}

protocol LevelRepository {
    func loadContent() throws -> GameContent
}

protocol Clock {
    var now: Date { get }
    /// Monotonic seconds (does not jump with wall clock changes).
    var uptime: TimeInterval { get }
}

protocol RandomSource {
    /// Uniform integer in 0..<upperBound.
    func nextInt(upperBound: Int) -> Int
}

enum SoundCue: String, CaseIterable {
    case tap = "S01_tap"
    case back = "S02_back"
    case sheetOpen = "S03_sheet_open"
    case sheetClose = "S04_sheet_close"
    case toggle = "S05_toggle"
    case unavailable = "S06_unavailable"
    case levelSelect = "S07_level_select"
    case countdown = "S08_countdown"
    case start = "S09_start"
    case release = "S10_release"
    case fallAir = "S11_fall_air"
    case landWood = "S12_land_wood"
    case landStone = "S13_land_stone"
    case landMetal = "S14_land_metal"
    case perfectOne = "S15_perfect_one"
    case perfectTwo = "S16_perfect_two"
    case braceReady = "S17_brace_ready"
    case braceUse = "S18_brace_use"
    case strain = "S19_strain"
    case miss = "S20_miss"
    case retry = "S21_retry"
    case beacon = "S22_beacon"
    case complete = "S23_complete"
    case star = "S24_star"
    case bolts = "S25_bolts"
    case district = "S26_district"
    case reelTick = "S27_reel_tick"
    case reelStop = "S28_reel_stop"
    case supply = "S29_supply"
    case theme = "S30_theme"

    /// success > failure > perfect > impact > UI
    var priority: Int {
        switch self {
        case .complete, .district, .supply, .beacon, .star, .bolts, .theme: return 5
        case .retry, .miss: return 4
        case .perfectOne, .perfectTwo, .braceReady, .braceUse: return 3
        case .landWood, .landStone, .landMetal, .release, .fallAir, .strain: return 2
        default: return 1
        }
    }

    var isFanfare: Bool { self == .complete || self == .district || self == .supply }
}

enum MusicTrack: String {
    case sunnyRooftops = "M01_sunny_rooftops"
    case steadyHands = "M02_steady_hands"
    case harborBreeze = "M03_harbor_breeze"
    case depotDelivery = "M04_depot_delivery"
}

enum AmbienceLoop: String {
    case cityAir = "A01_city_air"
    case craneMotor = "A02_crane_motor"
}

protocol AudioService: AnyObject {
    func apply(settings: GameSettings)
    func play(_ cue: SoundCue)
    func setMusic(_ track: MusicTrack?)
    func setAmbience(_ loop: AmbienceLoop, on: Bool)
    /// Pause/background/interruption: every loop stops, pending effects are dropped.
    func stopAllLoops()
    func stopEffects()
    func resumeMusicIfNeeded()
}

enum HapticKind {
    case landing
    case perfect
    case failure
    case selection
}

protocol HapticService: AnyObject {
    var enabled: Bool { get set }
    func play(_ kind: HapticKind)
}

// MARK: - Use cases (pure: Profile in → Profile out)

struct StartRun {
    let content: GameContent

    func campaign(level: LevelConfig, settings: GameSettings, now: Date) -> RunSession {
        RunSession.new(mode: .campaign(levelID: level.id), phaseSeed: level.phaseSeed, timingAssist: settings.timingAssist, now: now)
    }

    func freeBuild(settings: GameSettings, now: Date) -> RunSession {
        RunSession.new(mode: .freeBuild, phaseSeed: RunRules.freeBuildPhaseSeed, timingAssist: settings.timingAssist, now: now)
    }

    /// Practice: two preset floors on the plaza, slowed motion, no rewards.
    func tutorial(level: LevelConfig, themeID: String, now: Date) -> RunSession {
        var s = RunSession.new(mode: .tutorial, phaseSeed: level.phaseSeed, timingAssist: false, now: now)
        for i in 0..<RunRules.tutorialPresetFloors {
            s.placements.append(Placement(centerX: 0, accuracy: 1, assetID: content.floorAsset(index: i, level: level, themeID: themeID), kind: .perfect))
        }
        s.presetFloors = RunRules.tutorialPresetFloors
        s.assisted = false
        return s
    }
}

struct FinishRun {
    let content: GameContent

    /// Records a finished campaign/free run exactly once (keyed by sessionID).
    /// Returns the updated profile and the result to show. Re-applying the same session returns the stored result.
    func execute(_ profile: Profile, session: RunSession, now: Date) -> (Profile, RunResult)? {
        guard session.stage.isTerminal else { return nil }
        if profile.hasProcessed(session: session.sessionID) {
            if let r = profile.lastResult, r.sessionID == session.sessionID { return (profile, r) }
            return nil
        }
        switch session.mode {
        case .campaign(let levelID):
            guard let level = content.level(levelID) else { return nil }
            return campaign(profile, session: session, level: level, now: now)
        case .freeBuild:
            return free(profile, session: session, now: now)
        case .tutorial:
            return nil
        }
    }

    private func campaign(_ profile: Profile, session: RunSession, level: LevelConfig, now: Date) -> (Profile, RunResult) {
        var p = profile
        let success = session.stage == .won
        let old = p.best(for: level.id)
        let precision = success ? Scoring.precision(session.placements, target: level.targetFloors) : 0
        let stars = success ? Scoring.stars(precision: precision, level: level) : 0
        var bolts = 0
        var firstClear = false
        var newBestPrecision = false
        var unlocked: Int?
        if success {
            firstClear = old == nil
            bolts = Scoring.reward(level: level, firstClear: firstClear, oldBestStars: old?.bestStars ?? 0, newStars: stars)
            if var best = old {
                best.bestStars = max(best.bestStars, stars)
                if precision > best.bestPrecision + RunRules.epsilon {
                    best.bestPrecision = precision
                    newBestPrecision = true
                }
                if precision > best.layoutPrecision + RunRules.epsilon {
                    best.layout = session.placements
                    best.layoutPrecision = precision
                    best.layoutDate = now
                    best.layoutAssisted = session.usedAnyAssistance
                }
                best.clears += 1
                p.levelBests = p.levelBests.map { $0.levelID == level.id ? best : $0 }
            } else {
                newBestPrecision = true
                p.levelBests.append(LevelBest(levelID: level.id, bestStars: stars, bestPrecision: precision,
                                              layout: session.placements, layoutPrecision: precision, layoutDate: now,
                                              layoutAssisted: session.usedAnyAssistance, firstClearedAt: now, clears: 1))
                p.levelBests.sort { $0.levelID < $1.levelID }
                unlocked = Campaign(content: content, profile: profile).districtUnlocked(byClearing: level.id)?.id
            }
            if bolts > 0 {
                p.walletBalance += bolts
                p.walletReceipts.append(WalletEntry(id: session.sessionID, kind: .levelReward, amount: bolts,
                                                    balanceAfter: p.walletBalance, date: now, reference: "level-\(level.id)"))
            }
        }
        let result = RunResult(sessionID: session.sessionID, mode: session.mode, success: success,
                               failReason: success ? nil : (session.failReason ?? .missedSupport),
                               floors: session.floorCount, targetFloors: level.targetFloors,
                               precision: precision, stars: stars, previousBestStars: old?.bestStars ?? 0,
                               bolts: bolts, firstClear: firstClear, newBestPrecision: newBestPrecision,
                               assisted: session.usedAnyAssistance, layout: session.placements,
                               freeOutcome: nil, newRecord: false, unlockedDistrict: unlocked, date: now)
        recordRun(&p, session: session, result: result, now: now)
        return (p, result)
    }

    private func free(_ profile: Profile, session: RunSession, now: Date) -> (Profile, RunResult) {
        var p = profile
        let height = session.floorCount
        let precision = height > 0 ? Scoring.precision(session.placements, target: height) : 0
        let outcome: FreeBuildOutcome = session.stage == .won ? .heightLimit : .fell
        let record = FreeBuildRecord(sessionID: session.sessionID, height: height, precision: precision,
                                     layout: session.placements, date: now, assisted: session.usedAnyAssistance, outcome: outcome)
        let isRecord = Scoring.isBetterFree(height: height, precision: precision, than: p.freeBest)
        if isRecord { p.freeBest = record }
        p.freeLast = record
        let result = RunResult(sessionID: session.sessionID, mode: .freeBuild, success: outcome == .heightLimit,
                               failReason: outcome == .fell ? session.failReason : nil,
                               floors: height, targetFloors: nil, precision: precision, stars: 0, previousBestStars: 0,
                               bolts: 0, firstClear: false, newBestPrecision: false, assisted: session.usedAnyAssistance,
                               layout: session.placements, freeOutcome: outcome, newRecord: isRecord, unlockedDistrict: nil, date: now)
        recordRun(&p, session: session, result: result, now: now)
        return (p, result)
    }

    private func recordRun(_ p: inout Profile, session: RunSession, result: RunResult, now: Date) {
        p.recentRuns.insert(RunSummary(sessionID: session.sessionID, mode: session.mode, success: result.success,
                                       floors: result.floors, precision: result.precision, stars: result.stars,
                                       bolts: result.bolts, assisted: result.assisted, date: now), at: 0)
        if p.recentRuns.count > Profile.recentRunsLimit { p.recentRuns.removeLast(p.recentRuns.count - Profile.recentRunsLimit) }
        if p.activeSession?.sessionID == session.sessionID { p.activeSession = nil }
        p.lastResult = result
        p.lastSeenWall = max(p.lastSeenWall, now)
    }
}

struct ResetProfile {
    /// Clears profile, session, wallet and receipts. Sound/accessibility settings and onboarding marks stay.
    func execute(_ profile: Profile?, now: Date, defaults: GameSettings = GameSettings()) -> Profile {
        Profile.fresh(now: now,
                      settings: profile?.settings ?? defaults,
                      onboarding: profile?.onboarding ?? OnboardingState(step: 2, completed: true),
                      tutorialSeen: profile?.tutorialSeen ?? true)
    }
}

// MARK: - Validation of a decoded profile

enum ProfileValidationError: Error, Equatable {
    case futureSchema(Int)
    case invalid(String)
}

struct ProfileValidator {
    let content: GameContent

    func validate(_ p: Profile) throws {
        if p.schemaVersion > Profile.currentSchema { throw ProfileValidationError.futureSchema(p.schemaVersion) }
        guard p.schemaVersion == Profile.currentSchema else { throw ProfileValidationError.invalid("schema") }
        guard p.walletBalance >= 0 else { throw ProfileValidationError.invalid("negative balance") }
        let ids = p.levelBests.map(\.levelID)
        guard Set(ids).count == ids.count else { throw ProfileValidationError.invalid("duplicate levels") }
        for b in p.levelBests {
            guard let level = content.level(b.levelID) else { throw ProfileValidationError.invalid("unknown level") }
            guard (1...3).contains(b.bestStars) else { throw ProfileValidationError.invalid("stars") }
            guard finite01(b.bestPrecision), finite01(b.layoutPrecision), b.layoutPrecision <= b.bestPrecision + 1e-6 else {
                throw ProfileValidationError.invalid("precision")
            }
            guard b.layout.count == level.targetFloors else { throw ProfileValidationError.invalid("layout size") }
            try validateLayout(b.layout)
        }
        let receiptIDs = p.walletReceipts.map(\.id)
        guard Set(receiptIDs).count == receiptIDs.count else { throw ProfileValidationError.invalid("duplicate receipts") }
        guard p.walletReceipts.allSatisfy({ $0.balanceAfter >= 0 }) else { throw ProfileValidationError.invalid("receipt balance") }
        let themeIDs = Set(content.economy.skins.map(\.id))
        guard p.unlockedThemes.allSatisfy({ themeIDs.contains($0) }), Set(p.unlockedThemes).count == p.unlockedThemes.count,
              p.unlockedThemes.contains(GameContent.originalThemeID) else {
            throw ProfileValidationError.invalid("themes")
        }
        guard themeIDs.contains(p.selectedTheme), p.unlockedThemes.contains(p.selectedTheme) else {
            throw ProfileValidationError.invalid("selected theme")
        }
        for rec in [p.freeBest, p.freeLast].compactMap({ $0 }) {
            guard rec.height >= 0, rec.height <= GameContent.freeBuildHeightLimit, rec.layout.count == rec.height,
                  finite01(rec.precision) else { throw ProfileValidationError.invalid("free build") }
            try validateLayout(rec.layout)
        }
        if let r = p.daily.lastReceipt {
            guard (0..<100).contains(r.roll), r.bolts >= 0, r.symbols.count == 3 else { throw ProfileValidationError.invalid("daily") }
        }
        guard p.recentRuns.count <= Profile.recentRunsLimit else { throw ProfileValidationError.invalid("recent runs") }
        if let s = p.activeSession { try validateSession(s) }
        guard p.lastSeenWall.timeIntervalSince1970.isFinite else { throw ProfileValidationError.invalid("clock") }
    }

    private func finite01(_ v: Double) -> Bool { v.isFinite && v >= 0 && v <= 1 + 1e-9 }

    private func validateLayout(_ layout: [Placement]) throws {
        var prev = 0.0
        for pl in layout {
            guard pl.centerX.isFinite, finite01(pl.accuracy) else { throw ProfileValidationError.invalid("placement") }
            // Each floor sits on the previous one with |dx| < .42·W.
            guard abs(pl.centerX - prev) < 0.42 * 180 + 1e-6 else { throw ProfileValidationError.invalid("offset") }
            prev = pl.centerX
        }
    }

    private func validateSession(_ s: RunSession) throws {
        guard s.stageTime.isFinite, s.stageTime >= 0, s.simulationTime.isFinite, s.simulationTime >= 0 else {
            throw ProfileValidationError.invalid("session time")
        }
        guard (0...100).contains(s.strain), s.streak >= 0, s.streak < 3 else { throw ProfileValidationError.invalid("session values") }
        guard !(s.braceCharged && s.braceArmed) else { throw ProfileValidationError.invalid("brace") }
        if let lid = s.mode.levelID {
            guard let level = content.level(lid), s.floorCount <= level.targetFloors else { throw ProfileValidationError.invalid("session level") }
        }
        if let plan = s.planned { guard plan.dx.isFinite, abs(plan.dx) < 1000 else { throw ProfileValidationError.invalid("planned") } }
        if s.stage == .dropping { guard s.planned != nil else { throw ProfileValidationError.invalid("dropping without plan") } }
        try validateLayout(Array(s.placements))
    }
}
