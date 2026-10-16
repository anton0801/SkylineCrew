import Foundation

// MARK: - Bundled content

final class BundleJSONLevelRepository: LevelRepository {
    private let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    enum ContentError: Error { case missing(String), invalid(String) }

    private func data(_ name: String) throws -> Data {
        if let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Resources/Data") {
            return try Data(contentsOf: url)
        }
        throw ContentError.missing(name)
    }

    func loadContent() throws -> GameContent {
        let decoder = JSONDecoder()
        let levels = try decoder.decode(LevelsFile.self, from: data("levels")).levels.sorted { $0.id < $1.id }
        let districts = try decoder.decode(DistrictsFile.self, from: data("districts")).districts.sorted { $0.id < $1.id }
        let economy = try decoder.decode(EconomyConfig.self, from: data("economy"))
        guard levels.map(\.id) == Array(1...levels.count) else { throw ContentError.invalid("level ids") }
        guard !economy.skins.isEmpty, economy.daily.bands.reduce(0, { $0 + $1.weight }) == 100 else {
            throw ContentError.invalid("economy")
        }
        return GameContent(levels: levels, districts: districts, economy: economy)
    }
}

// MARK: - Profile file storage

enum ProfileCoding {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    /// Only the schema number is read first; an unknown future schema is never decoded as v1.
    struct SchemaProbe: Decodable { let schemaVersion: Int }
}

enum StorageError: Error {
    case writeFailed(String)
    case noValidBackup
    case simulatedFailure
}

final class AtomicFileProfileRepository: ProfileRepository, SessionRepository, @unchecked Sendable {
    let directory: URL
    private let validator: ProfileValidator
    private let fm = FileManager.default
    /// Debug hook used by fixtures/tests to exercise the Save Problem flow.
    var simulateWriteFailure = false

    var primaryURL: URL { directory.appendingPathComponent("profile-v1.json") }
    var backupURL: URL { directory.appendingPathComponent("profile-v1.backup.json") }
    private var tempURL: URL { directory.appendingPathComponent("profile-v1.json.tmp") }
    private var backupTempURL: URL { directory.appendingPathComponent("profile-v1.backup.json.tmp") }

    init(directory: URL? = nil, content: GameContent) {
        if let directory {
            self.directory = directory
        } else {
            let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
            self.directory = base.appendingPathComponent("SkylineCrew", isDirectory: true)
        }
        self.validator = ProfileValidator(content: content)
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
        // Application Support content is part of the local device backup; no network sync.
    }

    private func decodeValidated(_ data: Data) throws -> Profile {
        let probe = try ProfileCoding.decoder().decode(ProfileCoding.SchemaProbe.self, from: data)
        if probe.schemaVersion > Profile.currentSchema { throw ProfileValidationError.futureSchema(probe.schemaVersion) }
        let profile = try ProfileCoding.decoder().decode(Profile.self, from: data)
        try validator.validate(profile)
        return profile
    }

    private func validBackup() -> Profile? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return try? decodeValidated(data)
    }

    func load() -> ProfileLoadResult {
        if !fm.fileExists(atPath: primaryURL.path) {
            if fm.fileExists(atPath: backupURL.path) {
                return .recovery(RecoveryInfo(backupAvailable: validBackup() != nil, futureSchema: false, reason: "missing"))
            }
            return .fresh
        }
        do {
            let data = try Data(contentsOf: primaryURL)
            return .loaded(try decodeValidated(data))
        } catch {
            preserveCorruptPrimary()
            var future = false
            if case ProfileValidationError.futureSchema = error { future = true }
            return .recovery(RecoveryInfo(backupAvailable: validBackup() != nil, futureSchema: future, reason: String(describing: error)))
        }
    }

    /// The damaged file is kept for possible manual recovery, never deleted automatically.
    private func preserveCorruptPrimary() {
        let stamp = Int(Date().timeIntervalSince1970)
        let keep = directory.appendingPathComponent("profile-v1.corrupt-\(stamp).json")
        let existing = (try? fm.contentsOfDirectory(atPath: directory.path))?.filter { $0.hasPrefix("profile-v1.corrupt-") } ?? []
        if let primaryData = try? Data(contentsOf: primaryURL) {
            for name in existing {
                if let old = try? Data(contentsOf: directory.appendingPathComponent(name)), old == primaryData { return }
            }
            try? primaryData.write(to: keep)
        }
    }

    func save(_ profile: Profile) throws {
        if simulateWriteFailure { throw StorageError.simulatedFailure }
        try validator.validate(profile)
        let data = try ProfileCoding.encoder().encode(profile)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeSynced(data, to: tempURL)
        // Keep the previous valid primary as backup (copy → flush → atomic rename).
        if fm.fileExists(atPath: primaryURL.path), let current = try? Data(contentsOf: primaryURL),
           (try? decodeValidated(current)) != nil {
            try writeSynced(current, to: backupTempURL)
            try atomicRename(backupTempURL, backupURL)
        }
        try atomicRename(tempURL, primaryURL)
    }

    func restoreBackup() throws -> Profile {
        guard let data = try? Data(contentsOf: backupURL) else { throw StorageError.noValidBackup }
        let profile = try decodeValidated(data)
        try writeSynced(data, to: tempURL)
        try atomicRename(tempURL, primaryURL)
        return profile
    }

    func saveSession(_ session: RunSession?, into profile: Profile) throws -> Profile {
        var p = profile
        p.activeSession = session
        try save(p)
        return p
    }

    private func writeSynced(_ data: Data, to url: URL) throws {
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        guard fm.createFile(atPath: url.path, contents: nil) else { throw StorageError.writeFailed("create") }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private func atomicRename(_ from: URL, _ to: URL) throws {
        if rename(from.path, to.path) != 0 {
            throw StorageError.writeFailed("rename \(errno)")
        }
    }
}

/// Fixture/preview storage: never touches the player's real profile.
final class InMemoryProfileRepository: ProfileRepository, SessionRepository, @unchecked Sendable {
    var stored: Profile?
    var backup: Profile?
    var simulateWriteFailure = false
    var loadResult: ProfileLoadResult?

    init(profile: Profile?) { stored = profile }

    func load() -> ProfileLoadResult {
        if let loadResult { return loadResult }
        if let stored { return .loaded(stored) }
        return .fresh
    }

    func save(_ profile: Profile) throws {
        if simulateWriteFailure { throw StorageError.simulatedFailure }
        backup = stored
        stored = profile
    }

    func restoreBackup() throws -> Profile {
        guard let backup else { throw StorageError.noValidBackup }
        stored = backup
        loadResult = nil
        return backup
    }

    func saveSession(_ session: RunSession?, into profile: Profile) throws -> Profile {
        var p = profile
        p.activeSession = session
        try save(p)
        return p
    }
}

// MARK: - System services

final class SystemClock: Clock {
    var now: Date { Date() }
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

final class SystemRandomSource: RandomSource {
    func nextInt(upperBound: Int) -> Int {
        var g = SystemRandomNumberGenerator()
        return Int.random(in: 0..<max(1, upperBound), using: &g)
    }
}

final class FixedRandomSource: RandomSource {
    var values: [Int]
    init(_ values: [Int]) { self.values = values }
    func nextInt(upperBound: Int) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.removeFirst() % max(1, upperBound)
    }
}
