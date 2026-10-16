import Foundation

enum RunMode: Codable, Equatable, Hashable {
    case campaign(levelID: Int)
    case freeBuild
    case tutorial

    var levelID: Int? {
        if case .campaign(let id) = self { return id }
        return nil
    }

    var isTutorial: Bool { self == .tutorial }
    var isFreeBuild: Bool { self == .freeBuild }
}

/// Brief → Aiming → Dropping → Resolving(settling) → Aiming | Roofing → Won; a bad landing → Failing → Failed.
/// `isPaused` wraps any active stage.
enum RunStage: String, Codable, Equatable {
    case aiming
    case dropping
    case settling
    case failing
    case roofing
    case won
    case failed

    var isTerminal: Bool { self == .won || self == .failed }
}

enum FailReason: String, Codable, Equatable {
    case missedSupport
    case tooMuchStrain
}

enum LandingKind: String, Codable, Equatable {
    case perfect
    case normal
    /// Brace-assisted placement (“Steady!”).
    case steady
}

enum LandingMaterial: String, Codable, Equatable {
    case wood, stone, metal

    /// F05 = wood, F02 = metal, all other floors = stone.
    static func of(asset: String) -> LandingMaterial {
        switch asset {
        case "F05": return .wood
        case "F02": return .metal
        default: return .stone
        }
    }
}

/// A floor that has been placed. `centerX` is the real center after snapping (world units).
struct Placement: Codable, Equatable {
    var centerX: Double
    var accuracy: Double
    var assetID: String
    var kind: LandingKind
}

/// Fixed at the confirmed touchUpInside, persisted before the fall animation.
struct PlannedPlacement: Codable, Equatable {
    var dx: Double
    var assetID: String
    var braced: Bool
    var commandID: UUID
}

struct RunSession: Codable, Equatable {
    var schema: Int = 1
    var sessionID: UUID
    var mode: RunMode
    var stage: RunStage
    /// Active time spent in the current stage (Aiming t, fall progress, settle, roof). Never runs while paused.
    var stageTime: Double
    /// Total active simulation time of the run.
    var simulationTime: Double
    var placements: [Placement]
    var strain: Int
    var streak: Int
    var braceCharged: Bool
    var braceArmed: Bool
    var planned: PlannedPlacement?
    var lastLanding: LandingKind?
    var phaseSeed: Int
    var timingAssist: Bool
    /// The run used Timing Assist at any point.
    var assisted: Bool
    /// The run used a brace placement at any point.
    var braceUsed: Bool
    var failReason: FailReason?
    var pendingTransactionID: UUID?
    var appliedCommandIDs: [UUID]
    var isPaused: Bool
    var createdAt: Date
    /// Floors placed before the run starts (tutorial only); they are not part of the score.
    var presetFloors: Int

    var floorCount: Int { placements.count }
    var topX: Double { placements.last?.centerX ?? 0 }
    var usedAnyAssistance: Bool { assisted || braceUsed }

    static func new(mode: RunMode, phaseSeed: Int, timingAssist: Bool, now: Date, id: UUID = UUID()) -> RunSession {
        RunSession(sessionID: id,
                   mode: mode,
                   stage: .aiming,
                   stageTime: 0,
                   simulationTime: 0,
                   placements: [],
                   strain: 0,
                   streak: 0,
                   braceCharged: false,
                   braceArmed: false,
                   planned: nil,
                   lastLanding: nil,
                   phaseSeed: phaseSeed,
                   timingAssist: timingAssist,
                   assisted: timingAssist,
                   braceUsed: false,
                   failReason: nil,
                   pendingTransactionID: nil,
                   appliedCommandIDs: [],
                   isPaused: false,
                   createdAt: now,
                   presetFloors: 0)
    }
}
