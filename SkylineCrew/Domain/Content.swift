import Foundation

// MARK: - Static game content (campaign/levels.json, districts.json, economy.json)

struct LevelConfig: Codable, Equatable, Identifiable {
    let id: Int
    let district: Int
    let name: String
    let targetFloors: Int
    let width: Double
    let amplitude: Double
    let angularSpeed: Double
    let perfectTolerance: Double
    let maxStrain: Int
    let windAmplitude: Double
    let windFrequency: Double
    let phaseSeed: Int
    let floorSequence: [String]
    let baseAsset: String
    let roofAsset: String
    let background: String
    let braceThreshold: Int
    let star2Accuracy: Double
    let star3Accuracy: Double
    let firstClearBolts: Int
    let maxStarBonusBolts: Int
    let mechanic: String

    var hasWind: Bool { windAmplitude > 0 }
    /// Districts 4–6: the sign of the wind term flips after every pair of placed floors.
    var changingWind: Bool { mechanic == "Changing wind" }
}

struct LevelsFile: Codable {
    let schemaVersion: Int
    let levels: [LevelConfig]
}

struct District: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let background: String
    let firstLevel: Int
    let lastLevel: Int
    let unlockAfterLevel: Int?

    var levelRange: ClosedRange<Int> { firstLevel...lastLevel }
}

struct DistrictsFile: Codable {
    let districts: [District]
}

struct ThemeSkin: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let cost: Int
    let unlocked: Bool?
    let sequence: [String]

    var isFree: Bool { unlocked == true || cost == 0 }

    /// Three sample facades shown in the Workshop row.
    var previewAssets: [String] {
        if sequence.count > 3 { return Array(sequence.reversed().prefix(3)) }
        return sequence
    }
}

struct DailyBand: Codable, Equatable {
    let weight: Int
    let bolts: Int
    let symbols: [String]
}

struct DailyConfig: Codable, Equatable {
    let cooldownSeconds: Double
    let bands: [DailyBand]
    let presentationSeconds: Double
    let realMoney: Bool
}

struct EconomyConfig: Codable, Equatable {
    let currency: String
    let initialBalance: Int
    let purchasedWithMoney: Bool
    let spendOnly: String
    let skins: [ThemeSkin]
    let daily: DailyConfig
}

/// All bundled, read-only content.
struct GameContent {
    let levels: [LevelConfig]
    let districts: [District]
    let economy: EconomyConfig

    static let originalThemeID = "original"
    static let freeBuildUnlockLevel = 5
    static let freeBuildHeightLimit = 200

    var lastLevelID: Int { levels.last?.id ?? 0 }

    func level(_ id: Int) -> LevelConfig? {
        guard id >= 1, id <= levels.count else { return nil }
        let candidate = levels[id - 1]
        return candidate.id == id ? candidate : levels.first { $0.id == id }
    }

    func district(_ id: Int) -> District? { districts.first { $0.id == id } }

    func district(forLevel levelID: Int) -> District? {
        districts.first { $0.levelRange.contains(levelID) }
    }

    func theme(_ id: String) -> ThemeSkin? { economy.skins.first { $0.id == id } }

    var originalTheme: ThemeSkin {
        theme(Self.originalThemeID) ?? economy.skins[0]
    }

    /// Facade asset for floor index `i` (0 = lowest) given the equipped theme.
    /// Cosmetics only change the facade sequence; geometry and physics are identical.
    func floorAsset(index: Int, level: LevelConfig?, themeID: String) -> String {
        if themeID == Self.originalThemeID || theme(themeID) == nil {
            if let level, !level.floorSequence.isEmpty {
                return level.floorSequence[index % level.floorSequence.count]
            }
            let seq = originalTheme.sequence
            return seq[index % seq.count]
        }
        let seq = theme(themeID)!.sequence
        return seq[index % seq.count]
    }

    func themeSequence(_ themeID: String) -> [String] {
        (theme(themeID) ?? originalTheme).sequence
    }
}
