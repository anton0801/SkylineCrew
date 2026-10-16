import XCTest
@testable import SkylineCrew

/// Simulated players on the pure model. This checks that every control level is clearable and
/// shows how timing skill maps to stars. It does not replace a human playtest on a device.
final class PlaytestSimulationTests: XCTestCase {
    struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        /// Approximately normal (Irwin–Hall, 6 samples).
        mutating func gaussian() -> Double { (0..<6).reduce(0) { a, _ in a + next() } - 3 }
    }

    struct Outcome { var cleared = 0; var stars = [0, 0, 0, 0]; var precision = 0.0; var floors = 0 }

    /// The player waits for the next moment the edges line up and taps with a Gaussian timing error.
    private func play(engine: RunEngine, session start: RunSession, sigma: Double, rng: inout LCG) -> RunSession {
        var s = start
        var guardSteps = 0
        while !s.stage.isTerminal && guardSteps < 4000 {
            guardSteps += 1
            if s.stage == .aiming {
                if s.braceCharged && s.strain >= 50 { engine.reduce(&s, .armBrace(commandID: UUID())) }
                let aim = engine.aim(s)
                let t0 = s.stageTime + 0.25
                var best = t0, bestAbs = Double.infinity
                var t = t0
                while t < t0 + 9 {
                    let v = abs(aim.offset(at: t, floorCount: s.floorCount))
                    if v < bestAbs { bestAbs = v; best = t }
                    if v < 0.5 { break }
                    t += 0.004
                }
                let target = max(s.stageTime, best + sigma * rng.gaussian())
                engine.reduce(&s, .advance(dt: target - s.stageTime))
                engine.reduce(&s, .release(commandID: UUID()))
            } else {
                engine.reduce(&s, .advance(dt: 0.05))
            }
        }
        return s
    }

    private func simulate(levelID: Int, sigma: Double, runs: Int) -> Outcome {
        let content = TestContent.shared
        let level = content.level(levelID)!
        let engine = RunEngine(context: .campaign(level, reduceMotion: false) { content.floorAsset(index: $0, level: level, themeID: "original") })
        var rng = LCG(state: UInt64(levelID * 7919 + Int(sigma * 1000)))
        var out = Outcome()
        for _ in 0..<runs {
            let start = StartRun(content: content).campaign(level: level, settings: GameSettings(), now: Date())
            let end = play(engine: engine, session: start, sigma: sigma, rng: &rng)
            if end.stage == .won {
                out.cleared += 1
                let p = Scoring.precision(end.placements, target: level.targetFloors)
                out.precision += p
                out.stars[Scoring.stars(precision: p, level: level)] += 1
            }
        }
        if out.cleared > 0 { out.precision /= Double(out.cleared) }
        return out
    }

    func testControlLevelsAreClearableWithHumanTiming() {
        let control = [1, 20, 21, 40, 60, 80, 100, 120]
        let sigmas = [0.06, 0.12, 0.2, 0.3]
        var report = "\nSimulated playtest, 100 runs per cell: clear% (★1/★2/★3) avg precision\nlevel"
        for s in sigmas { report += String(format: " | σ=%3.0fms              ", s * 1000) }
        report += "\n"
        for id in control {
            report += String(format: "%5d", id)
            for sigma in sigmas {
                let o = simulate(levelID: id, sigma: sigma, runs: 100)
                report += String(format: " | %3d%% (%2d/%2d/%2d) %3.0f%%", o.cleared, o.stars[1], o.stars[2], o.stars[3], o.precision * 100)
                if sigma <= 0.12 { XCTAssertGreaterThanOrEqual(o.cleared, 50, "Level \(id) must be clearable by a precise player") }
            }
            report += "\n"
        }
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFreeBuildHeightsGrowWithSkill() {
        let content = TestContent.shared
        let engine = RunEngine(context: .freeBuild(reduceMotion: false) { content.floorAsset(index: $0, level: nil, themeID: "original") })
        var heights: [Double: Double] = [:]
        for sigma in [0.1, 0.2, 0.3] {
            var rng = LCG(state: UInt64(sigma * 10_000))
            var total = 0
            for _ in 0..<40 {
                let start = StartRun(content: content).freeBuild(settings: GameSettings(), now: Date())
                let end = play(engine: engine, session: start, sigma: sigma, rng: &rng)
                total += end.floorCount
                XCTAssertTrue(end.stage.isTerminal)
            }
            heights[sigma] = Double(total) / 40
        }
        print("Free Build average height σ=100ms \(heights[0.1]!), σ=200ms \(heights[0.2]!), σ=300ms \(heights[0.3]!)")
        XCTAssertGreaterThanOrEqual(heights[0.1]!, heights[0.3]!)
    }
}
