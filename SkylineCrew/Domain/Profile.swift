import Foundation

// MARK: - Persistent profile (ApplicationSupport/SkylineCrew/profile-v1.json)

struct GameSettings: Codable, Equatable {
    var music: Bool = true
    var effects: Bool = true
    var haptics: Bool = true
    var reducedMotion: Bool = false
    var timingAssist: Bool = false
}

struct OnboardingState: Codable, Equatable {
    /// Index of the onboarding card the player last saw (0…2).
    var step: Int = 0
    var completed: Bool = false
}

/// Best completed tower of one campaign level. Stars and precision are independent maxima;
/// the stored layout belongs to the attempt with the best precision (earliest on ties).
struct LevelBest: Codable, Equatable {
    var levelID: Int
    var bestStars: Int
    var bestPrecision: Double
    var layout: [Placement]
    var layoutPrecision: Double
    var layoutDate: Date
    var layoutAssisted: Bool
    var firstClearedAt: Date
    var clears: Int
}

enum FreeBuildOutcome: String, Codable, Equatable {
    case fell
    case heightLimit
}

struct FreeBuildRecord: Codable, Equatable {
    var sessionID: UUID
    var height: Int
    var precision: Double
    var layout: [Placement]
    var date: Date
    var assisted: Bool
    var outcome: FreeBuildOutcome
}

enum WalletEntryKind: String, Codable, Equatable {
    case levelReward
    case dailySupply
    case themePurchase
}

/// Every balance change has a stable transaction id; applying the same id twice is impossible.
struct WalletEntry: Codable, Equatable {
    var id: UUID
    var kind: WalletEntryKind
    var amount: Int
    var balanceAfter: Int
    var date: Date
    var reference: String
}

struct DailyReceipt: Codable, Equatable {
    var id: UUID
    var roll: Int
    var bandIndex: Int
    var bolts: Int
    var symbols: [String]
    var claimedAt: Date
    /// The reel presentation finished (or was skipped). A pending receipt is restored without new RNG.
    var presented: Bool
}

struct DailyState: Codable, Equatable {
    var nextEligibleAt: Date?
    var lastReceipt: DailyReceipt?
}

struct RunSummary: Codable, Equatable {
    var sessionID: UUID
    var mode: RunMode
    var success: Bool
    var floors: Int
    var precision: Double
    var stars: Int
    var bolts: Int
    var assisted: Bool
    var date: Date
}

/// Everything the result screen needs; written before the reward animation.
struct RunResult: Codable, Equatable {
    var sessionID: UUID
    var mode: RunMode
    var success: Bool
    var failReason: FailReason?
    var floors: Int
    var targetFloors: Int?
    var precision: Double
    var stars: Int
    var previousBestStars: Int
    var bolts: Int
    var firstClear: Bool
    var newBestPrecision: Bool
    var assisted: Bool
    var layout: [Placement]
    var freeOutcome: FreeBuildOutcome?
    var newRecord: Bool
    var unlockedDistrict: Int?
    var date: Date
}

struct Profile: Codable, Equatable {
    static let currentSchema = 1
    static let recentRunsLimit = 50

    var schemaVersion: Int = Profile.currentSchema
    var profileID: UUID
    var createdAt: Date
    var levelBests: [LevelBest]
    var freeBest: FreeBuildRecord?
    var freeLast: FreeBuildRecord?
    var unlockedThemes: [String]
    var selectedTheme: String
    var walletBalance: Int
    var walletReceipts: [WalletEntry]
    var daily: DailyState
    var lastSeenWall: Date
    var settings: GameSettings
    var onboarding: OnboardingState
    var tutorialSeen: Bool
    var recentRuns: [RunSummary]
    var activeSession: RunSession?
    var lastResult: RunResult?

    static func fresh(now: Date, settings: GameSettings = GameSettings(), onboarding: OnboardingState = OnboardingState(), tutorialSeen: Bool = false, initialBalance: Int = 0) -> Profile {
        Profile(profileID: UUID(),
                createdAt: now,
                levelBests: [],
                freeBest: nil,
                freeLast: nil,
                unlockedThemes: [GameContent.originalThemeID],
                selectedTheme: GameContent.originalThemeID,
                walletBalance: initialBalance,
                walletReceipts: [],
                daily: DailyState(),
                lastSeenWall: now,
                settings: settings,
                onboarding: onboarding,
                tutorialSeen: tutorialSeen,
                recentRuns: [],
                activeSession: nil,
                lastResult: nil)
    }

    func best(for levelID: Int) -> LevelBest? { levelBests.first { $0.levelID == levelID } }

    var completedLevelIDs: Set<Int> { Set(levelBests.map(\.levelID)) }
    var completedCount: Int { levelBests.count }
    var totalStars: Int { levelBests.reduce(0) { $0 + $1.bestStars } }

    func ownsTheme(_ id: String) -> Bool { unlockedThemes.contains(id) }

    func hasProcessed(session id: UUID) -> Bool {
        recentRuns.contains { $0.sessionID == id } || lastResult?.sessionID == id
    }
}
