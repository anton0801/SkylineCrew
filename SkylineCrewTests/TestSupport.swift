import XCTest
@testable import SkylineCrew

enum TestContent {
    static let shared: GameContent = {
        try! BundleJSONLevelRepository(bundle: Bundle(for: AtomicFileProfileRepository.self)).loadContent()
    }()

    static func level(_ id: Int) -> LevelConfig { shared.level(id)! }
}

/// Builds sessions in exact states and drives drops with a chosen dx.
struct RunHarness {
    var engine: RunEngine
    var session: RunSession

    init(level: LevelConfig, reduceMotion: Bool = false) {
        let content = TestContent.shared
        engine = RunEngine(context: .campaign(level, reduceMotion: reduceMotion) { content.floorAsset(index: $0, level: level, themeID: "original") })
        session = StartRun(content: content).campaign(level: level, settings: GameSettings(), now: Date(timeIntervalSince1970: 1_000))
    }

    init(engine: RunEngine, session: RunSession) {
        self.engine = engine
        self.session = session
    }

    /// Performs a drop that lands with exactly `dx` (bypasses the trajectory by editing the plan).
    @discardableResult
    mutating func drop(dx: Double) -> [RunEvent] {
        var events = engine.reduce(&session, .release(commandID: UUID()))
        if !session.braceArmed, var plan = session.planned, !plan.braced {
            plan.dx = dx
            session.planned = plan
        }
        events += engine.reduce(&session, .advance(dt: RunRules.dropDuration))
        return events
    }

    /// Lets the settle phase finish so the next Aiming starts.
    @discardableResult
    mutating func settle() -> [RunEvent] {
        engine.reduce(&session, .advance(dt: RunRules.settlePerfect + 0.001))
    }
}
