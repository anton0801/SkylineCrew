import XCTest
@testable import SkylineCrew

final class RunEngineTests: XCTestCase {
    let level1 = TestContent.level(1)

    // MARK: Trajectory

    func testPhasesFollowSpecFormula() {
        let p = AimParameters.phases(seed: 7919)
        XCTAssertEqual(p.phi, Double(7919 % 6283) / 1000, accuracy: 1e-12)
        XCTAssertEqual(p.psi, Double((7919 / 7) % 6283) / 1000, accuracy: 1e-12)
    }

    func testOffsetMatchesEquationAndIsFrameRateIndependent() {
        let level = TestContent.level(26)
        let a = AimParameters.campaign(level, seed: level.phaseSeed, timingAssist: false)
        let t = 2.345
        let expected = level.amplitude * sin(level.angularSpeed * t + a.phi) + level.windAmplitude * sin(level.windFrequency * t + a.psi)
        XCTAssertEqual(a.offset(at: t, floorCount: 3), expected, accuracy: 1e-9)

        // 60 Hz vs 120 Hz stepping lands on the same model time.
        var h60 = RunHarness(level: level), h120 = RunHarness(level: level)
        for _ in 0..<120 { h60.engine.reduce(&h60.session, .advance(dt: 1.0 / 60)) }
        for _ in 0..<240 { h120.engine.reduce(&h120.session, .advance(dt: 1.0 / 120)) }
        XCTAssertEqual(h60.engine.hangingOffset(h60.session), h120.engine.hangingOffset(h120.session), accuracy: 1e-6)
    }

    func testChangingWindFlipsAfterEachPairOfFloors() {
        XCTAssertEqual(AimParameters.windMultiplier(floorCount: 0, flips: true), 1)
        XCTAssertEqual(AimParameters.windMultiplier(floorCount: 1, flips: true), 1)
        XCTAssertEqual(AimParameters.windMultiplier(floorCount: 2, flips: true), -1)
        XCTAssertEqual(AimParameters.windMultiplier(floorCount: 3, flips: true), -1)
        XCTAssertEqual(AimParameters.windMultiplier(floorCount: 4, flips: true), 1)
        XCTAssertEqual(AimParameters.windMultiplier(floorCount: 2, flips: false), 1)
        XCTAssertTrue(TestContent.level(61).changingWind)
        XCTAssertFalse(TestContent.level(60).changingWind)
    }

    func testTimingAssistSlowsBothFrequencies() {
        let level = TestContent.level(30)
        let normal = AimParameters.campaign(level, seed: level.phaseSeed, timingAssist: false)
        let assisted = AimParameters.campaign(level, seed: level.phaseSeed, timingAssist: true)
        XCTAssertEqual(assisted.omega, normal.omega * 0.65, accuracy: 1e-12)
        XCTAssertEqual(assisted.windOmega, normal.windOmega * 0.65, accuracy: 1e-12)
    }

    func testFreeBuildParameters() {
        let p = AimParameters.freeBuild(floorCount: 30, seed: 1, timingAssist: false)
        XCTAssertEqual(p.amplitude, 70)
        XCTAssertEqual(p.omega, 0.95 + 30 * 0.008, accuracy: 1e-12)
        XCTAssertEqual(p.windAmplitude, 10, accuracy: 1e-12)
        let capped = AimParameters.freeBuild(floorCount: 90, seed: 1, timingAssist: false)
        XCTAssertEqual(capped.omega, 0.95 + 60 * 0.008, accuracy: 1e-12)
        XCTAssertEqual(capped.windAmplitude, 14)
    }

    // MARK: Boundaries .045 and .42

    func testPerfectIncludesTolerance() {
        var h = RunHarness(level: level1)
        let events = h.drop(dx: 0.045 * 180)
        XCTAssertEqual(h.session.placements.last?.kind, .perfect)
        XCTAssertEqual(h.session.placements.last?.accuracy, 1)
        XCTAssertEqual(h.session.placements.last?.centerX, 0, "Perfect snaps to topX")
        XCTAssertTrue(events.contains(.perfect(streak: 1)))
    }

    func testJustAbovePerfectIsOrdinary() {
        var h = RunHarness(level: level1)
        h.drop(dx: 0.045001 * 180)
        XCTAssertEqual(h.session.placements.last?.kind, .normal)
        XCTAssertLessThan(h.session.placements.last!.accuracy, 1)
        XCTAssertEqual(h.session.strain, 1)
        XCTAssertEqual(h.session.placements.last!.centerX, 0.045001 * 180, accuracy: 1e-9)
    }

    func testMissIncludesPoint42() {
        var h = RunHarness(level: level1)
        let events = h.drop(dx: -0.42 * 180)
        XCTAssertEqual(h.session.stage, .failing)
        XCTAssertTrue(events.contains(.missed))
        XCTAssertTrue(h.session.placements.isEmpty, "A missed floor is never counted")
        let after = h.engine.reduce(&h.session, .advance(dt: RunRules.failingDuration))
        XCTAssertEqual(h.session.stage, .failed)
        XCTAssertEqual(h.session.failReason, .missedSupport)
        XCTAssertTrue(after.contains(.failed(.missedSupport)))
    }

    func testJustBelowMissIsValid() {
        var h = RunHarness(level: level1)
        h.drop(dx: 0.4199 * 180)
        XCTAssertEqual(h.session.stage, .settling)
        XCTAssertEqual(h.session.floorCount, 1)
        XCTAssertEqual(h.session.placements[0].accuracy, 1 - 0.4199, accuracy: 1e-9)
        XCTAssertEqual(h.session.strain, Int(ceil((0.4199 - 0.045) * 110)))
    }

    // MARK: Strain

    func testStrain99To100Fails() {
        var h = RunHarness(level: level1)
        h.session.strain = 99
        let events = h.drop(dx: 0.055 * 180)
        XCTAssertEqual(h.session.stage, .failing)
        XCTAssertEqual(h.session.failReason, .tooMuchStrain)
        XCTAssertEqual(h.session.strain, 100)
        XCTAssertTrue(events.contains(.tooMuchStrain))
        XCTAssertEqual(h.session.floorCount, 0)
    }

    func testStrainCrossingEventsOnlyUpward() {
        var h = RunHarness(level: level1)
        h.session.strain = 55
        let up = h.drop(dx: 0.12 * 180) // +9 → 64
        XCTAssertTrue(up.contains(.strainCrossed(threshold: 60)))
        h.settle()
        let perfect = h.drop(dx: 0) // −10 → 54, no event
        XCTAssertFalse(perfect.contains { if case .strainCrossed = $0 { return true }; return false })
        XCTAssertEqual(h.session.strain, 54)
    }

    func testPerfectRelievesStrainButNotBelowZero() {
        var h = RunHarness(level: level1)
        h.session.strain = 4
        h.drop(dx: 0)
        XCTAssertEqual(h.session.strain, 0)
    }

    // MARK: Brace

    func testThreePerfectsChargeBraceAndResetStreak() {
        var h = RunHarness(level: level1)
        h.drop(dx: 0); h.settle()
        h.drop(dx: 1); h.settle()
        XCTAssertEqual(h.session.streak, 2)
        let events = h.drop(dx: -2)
        XCTAssertTrue(events.contains(.braceCharged))
        XCTAssertTrue(h.session.braceCharged)
        XCTAssertEqual(h.session.streak, 0)
    }

    func testAlreadyChargedStaysOne() {
        var h = RunHarness(level: level1)
        h.session.braceCharged = true
        h.session.streak = 2
        let events = h.drop(dx: 0)
        XCTAssertFalse(events.contains(.braceCharged))
        XCTAssertTrue(h.session.braceCharged)
        XCTAssertEqual(h.session.streak, 0)
    }

    func testArmedBraceProtectsOtherwiseMissedFloor() {
        var h = RunHarness(level: level1)
        h.session.strain = 50
        h.session.streak = 2
        h.session.braceCharged = true
        let arm = h.engine.reduce(&h.session, .armBrace(commandID: UUID()))
        XCTAssertEqual(arm, [.braceArmed])
        XCTAssertFalse(h.session.braceCharged)
        XCTAssertTrue(h.session.braceArmed)
        // The hanging floor may be far away; armed drop is placed at dx = 0.
        h.session.stageTime = 1.2
        let events = h.drop(dx: 0.6 * 180)
        XCTAssertEqual(h.session.placements.last?.kind, .steady)
        XCTAssertEqual(h.session.placements.last?.accuracy, 1)
        XCTAssertEqual(h.session.strain, 30)
        XCTAssertEqual(h.session.streak, 0, "Assisted placement cannot recharge the streak")
        XCTAssertFalse(h.session.braceArmed)
        XCTAssertTrue(h.session.braceUsed)
        XCTAssertTrue(events.contains(.landed(kind: .steady, material: .stone, floorIndex: 0)))
    }

    func testArmRequiresChargeAndAiming() {
        var h = RunHarness(level: level1)
        XCTAssertEqual(h.engine.reduce(&h.session, .armBrace(commandID: UUID())), [.rejected])
        h.session.braceCharged = true
        _ = h.engine.reduce(&h.session, .release(commandID: UUID()))
        XCTAssertEqual(h.engine.reduce(&h.session, .armBrace(commandID: UUID())), [.rejected], "Only in Aiming")
    }

    // MARK: Commands

    func testDuplicateCommandsApplyOnce() {
        var h = RunHarness(level: level1)
        let id = UUID()
        let first = h.engine.reduce(&h.session, .release(commandID: id))
        XCTAssertEqual(first.count, 1)
        h.engine.reduce(&h.session, .advance(dt: RunRules.dropDuration))
        h.settle()
        let again = h.engine.reduce(&h.session, .release(commandID: id))
        XCTAssertEqual(again, [])
        XCTAssertEqual(h.session.stage, .aiming)

        h.session.braceCharged = true
        let armID = UUID()
        XCTAssertEqual(h.engine.reduce(&h.session, .armBrace(commandID: armID)), [.braceArmed])
        XCTAssertEqual(h.engine.reduce(&h.session, .armBrace(commandID: armID)), [])
    }

    func testInputBlockedWhileDroppingAndPaused() {
        var h = RunHarness(level: level1)
        _ = h.engine.reduce(&h.session, .release(commandID: UUID()))
        let dx = h.session.planned!.dx
        XCTAssertEqual(h.engine.reduce(&h.session, .release(commandID: UUID())), [.rejected])
        XCTAssertEqual(h.session.planned!.dx, dx, "dx is fixed once")
        h.engine.reduce(&h.session, .setPaused(true))
        let before = h.session
        h.engine.reduce(&h.session, .advance(dt: 5))
        XCTAssertEqual(h.session, before, "No motion while paused")
    }

    func testReleaseCapturesTrajectoryDxOnce() {
        var h = RunHarness(level: level1)
        h.engine.reduce(&h.session, .advance(dt: 1.7))
        let expected = h.engine.hangingOffset(h.session)
        _ = h.engine.reduce(&h.session, .release(commandID: UUID()))
        XCTAssertEqual(h.session.planned!.dx, expected, accuracy: 1e-12)
        h.engine.reduce(&h.session, .advance(dt: 0.1))
        XCTAssertEqual(h.session.planned!.dx, expected, accuracy: 1e-12)
    }

    func testSnapshotRestoresFallWithoutRecomputingDx() throws {
        var h = RunHarness(level: level1)
        h.engine.reduce(&h.session, .advance(dt: 0.9))
        _ = h.engine.reduce(&h.session, .release(commandID: UUID()))
        h.engine.reduce(&h.session, .advance(dt: 0.2))
        let data = try ProfileCoding.encoder().encode(h.session)
        var restored = try ProfileCoding.decoder().decode(RunSession.self, from: data)
        XCTAssertEqual(restored, h.session)
        XCTAssertEqual(restored.stage, .dropping)
        XCTAssertEqual(restored.stageTime, 0.2, accuracy: 1e-12)
        let dx = restored.planned!.dx
        h.engine.reduce(&restored, .advance(dt: 0.15))
        XCTAssertEqual(restored.floorCount, 1)
        XCTAssertEqual(restored.placements[0].centerX, abs(dx) / 180 <= 0.045 ? 0 : dx, accuracy: 1e-9)
    }

    // MARK: Completion

    func testTargetFloorsLeadToRoofThenWon() {
        var h = RunHarness(level: level1)
        for _ in 0..<level1.targetFloors {
            h.drop(dx: 0)
            h.settle()
        }
        XCTAssertEqual(h.session.stage, .roofing)
        let events = h.engine.reduce(&h.session, .advance(dt: 1.3))
        XCTAssertTrue(events.contains(.beaconLit))
        XCTAssertTrue(events.contains(.won))
        XCTAssertEqual(h.session.stage, .won)
        XCTAssertEqual(h.session.floorCount, level1.targetFloors, "Base and roof are not counted")
    }

    func testReducedMotionRoofIsShort() {
        var h = RunHarness(level: level1, reduceMotion: true)
        for _ in 0..<level1.targetFloors { h.drop(dx: 0); h.settle() }
        h.engine.reduce(&h.session, .advance(dt: 0.2))
        XCTAssertEqual(h.session.stage, .won)
    }

    func testTutorialNeverFailsAndRequiresBraceOnLastStep() {
        let content = TestContent.shared
        let engine = RunEngine(context: .tutorial(level: level1, reduceMotion: false) { content.floorAsset(index: $0, level: self.level1, themeID: "original") })
        var h = RunHarness(engine: engine, session: StartRun(content: content).tutorial(level: level1, themeID: "original", now: Date()))
        XCTAssertEqual(h.session.floorCount, 2)
        h.drop(dx: 0.5 * 180)
        let retry = h.engine.reduce(&h.session, .advance(dt: RunRules.failingDuration))
        XCTAssertTrue(retry.contains(.tutorialRetry))
        XCTAssertEqual(h.session.stage, .aiming)
        h.session.strain = 98
        h.drop(dx: 0.3 * 180); h.settle()
        XCTAssertEqual(h.session.strain, 99, "Practice strain never reaches the limit")
        h.drop(dx: 0.1 * 180); h.settle()
        h.drop(dx: 0.1 * 180); h.settle()
        XCTAssertTrue(h.session.braceCharged, "Step 4 grants a brace")
        XCTAssertEqual(h.engine.reduce(&h.session, .release(commandID: UUID())), [.rejected])
        _ = h.engine.reduce(&h.session, .armBrace(commandID: UUID()))
        h.drop(dx: 0); h.settle()
        XCTAssertEqual(h.session.stage, .roofing)
    }
}
