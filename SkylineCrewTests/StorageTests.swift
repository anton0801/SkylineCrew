import XCTest
@testable import SkylineCrew

final class StorageTests: XCTestCase {
    var dir: URL!
    let content = TestContent.shared
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sc-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testFreshThenSaveAndLoad() throws {
        let repo = AtomicFileProfileRepository(directory: dir, content: content)
        guard case .fresh = repo.load() else { return XCTFail() }
        var p = Profile.fresh(now: now)
        p.walletBalance = 42
        try repo.save(p)
        guard case .loaded(let loaded) = repo.load() else { return XCTFail() }
        XCTAssertEqual(loaded, p)
    }

    func testPreviousVersionBecomesBackup() throws {
        let repo = AtomicFileProfileRepository(directory: dir, content: content)
        var p = Profile.fresh(now: now)
        p.walletBalance = 1
        try repo.save(p)
        p.walletBalance = 2
        try repo.save(p)
        let backup = try ProfileCoding.decoder().decode(Profile.self, from: Data(contentsOf: repo.backupURL))
        XCTAssertEqual(backup.walletBalance, 1)
    }

    func testCorruptPrimaryLeadsToRecoveryAndIsPreserved() throws {
        let repo = AtomicFileProfileRepository(directory: dir, content: content)
        var p = Profile.fresh(now: now)
        p.walletBalance = 10
        try repo.save(p)
        p.walletBalance = 20
        try repo.save(p)
        try Data("{ not json".utf8).write(to: repo.primaryURL)
        guard case .recovery(let info) = repo.load() else { return XCTFail("Corrupt primary must not load") }
        XCTAssertTrue(info.backupAvailable)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("profile-v1.corrupt-") }, "Damaged file is kept")
        let restored = try repo.restoreBackup()
        XCTAssertEqual(restored.walletBalance, 10)
        guard case .loaded(let again) = repo.load() else { return XCTFail() }
        XCTAssertEqual(again.walletBalance, 10)
    }

    func testInvalidValuesAreRejected() throws {
        let repo = AtomicFileProfileRepository(directory: dir, content: content)
        var p = Profile.fresh(now: now)
        p.walletBalance = -5
        XCTAssertThrowsError(try repo.save(p), "Validation also guards writes")

        var json = try JSONSerialization.jsonObject(with: ProfileCoding.encoder().encode(Profile.fresh(now: now))) as! [String: Any]
        json["walletBalance"] = -1
        try JSONSerialization.data(withJSONObject: json).write(to: repo.primaryURL)
        guard case .recovery = repo.load() else { return XCTFail() }
    }

    func testDuplicateReceiptsAreRejected() throws {
        var p = Profile.fresh(now: now)
        let id = UUID()
        p.walletReceipts = [WalletEntry(id: id, kind: .dailySupply, amount: 20, balanceAfter: 20, date: now, reference: "daily"),
                            WalletEntry(id: id, kind: .dailySupply, amount: 20, balanceAfter: 40, date: now, reference: "daily")]
        XCTAssertThrowsError(try ProfileValidator(content: content).validate(p))
    }

    func testFutureSchemaIsNotReadAsV1() throws {
        let repo = AtomicFileProfileRepository(directory: dir, content: content)
        var json = try JSONSerialization.jsonObject(with: ProfileCoding.encoder().encode(Profile.fresh(now: now))) as! [String: Any]
        json["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: json).write(to: repo.primaryURL)
        guard case .recovery(let info) = repo.load() else { return XCTFail() }
        XCTAssertTrue(info.futureSchema)
    }

    func testActiveSessionSurvivesRoundTrip() throws {
        let repo = AtomicFileProfileRepository(directory: dir, content: content)
        let level = TestContent.level(9)
        var h = RunHarness(level: level)
        h.engine.reduce(&h.session, .advance(dt: 0.4))
        _ = h.engine.reduce(&h.session, .release(commandID: UUID()))
        h.engine.reduce(&h.session, .advance(dt: 0.1))
        h.engine.reduce(&h.session, .setPaused(true))
        let saved = try repo.saveSession(h.session, into: Profile.fresh(now: now))
        guard case .loaded(let loaded) = repo.load() else { return XCTFail() }
        XCTAssertEqual(loaded.activeSession, saved.activeSession)
        XCTAssertEqual(loaded.activeSession?.planned, h.session.planned)
    }
}
