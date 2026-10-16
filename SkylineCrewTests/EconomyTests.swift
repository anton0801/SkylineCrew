import XCTest
@testable import SkylineCrew

final class EconomyTests: XCTestCase {
    let content = TestContent.shared
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func wonSession(level: LevelConfig, accuracies: [Double]) -> RunSession {
        var s = StartRun(content: content).campaign(level: level, settings: GameSettings(), now: now)
        s.placements = accuracies.enumerated().map { i, a in
            Placement(centerX: 0, accuracy: a, assetID: level.floorSequence[i], kind: a == 1 ? .perfect : .normal)
        }
        s.stage = .won
        return s
    }

    // MARK: Stars

    func testStarThresholdsCheckedBeforeRounding() {
        let level = TestContent.level(12)
        XCTAssertEqual(Scoring.stars(precision: 0.82, level: level), 2)
        XCTAssertEqual(Scoring.stars(precision: 0.93, level: level), 3)
        XCTAssertEqual(Scoring.stars(precision: 0.929999, level: level), 2, "93% after rounding is still two stars")
        XCTAssertEqual(Scoring.percent(0.929999), 93)
        XCTAssertEqual(Scoring.stars(precision: 0.5, level: level), 1)
    }

    func testRewardsFirstClearAndStarImprovements() {
        let level = TestContent.level(12) // firstClearBolts 15
        XCTAssertEqual(Scoring.reward(level: level, firstClear: true, oldBestStars: 0, newStars: 2), 25)
        XCTAssertEqual(Scoring.reward(level: level, firstClear: true, oldBestStars: 0, newStars: 3), 30)
        XCTAssertEqual(Scoring.reward(level: level, firstClear: true, oldBestStars: 0, newStars: 1), 20)
        XCTAssertEqual(Scoring.reward(level: level, firstClear: false, oldBestStars: 2, newStars: 3), 5)
        XCTAssertEqual(Scoring.reward(level: level, firstClear: false, oldBestStars: 3, newStars: 3), 0)
        XCTAssertEqual(Scoring.reward(level: level, firstClear: false, oldBestStars: 3, newStars: 1), 0)
    }

    func testFinishRunIsIdempotentAndKeepsMaxima() {
        let level = TestContent.level(12)
        let finish = FinishRun(content: content)
        var profile = Profile.fresh(now: now)

        let first = wonSession(level: level, accuracies: Array(repeating: 0.76, count: 8))
        let (p1, r1) = finish.execute(profile, session: first, now: now)!
        XCTAssertEqual(r1.stars, 1)
        XCTAssertEqual(r1.bolts, 20)
        XCTAssertTrue(r1.firstClear)
        XCTAssertEqual(p1.walletBalance, 20)

        // Re-applying the same session does not pay again.
        let (p1b, r1b) = finish.execute(p1, session: first, now: now)!
        XCTAssertEqual(p1b.walletBalance, 20)
        XCTAssertEqual(r1b, r1)
        profile = p1b

        let better = wonSession(level: level, accuracies: Array(repeating: 1, count: 8))
        let (p2, r2) = finish.execute(profile, session: better, now: now.addingTimeInterval(10))!
        XCTAssertEqual(r2.stars, 3)
        XCTAssertEqual(r2.bolts, 10)
        XCTAssertEqual(p2.walletBalance, 30)
        XCTAssertEqual(p2.best(for: 12)?.bestStars, 3)

        let worse = wonSession(level: level, accuracies: Array(repeating: 0.85, count: 8))
        let (p3, r3) = finish.execute(p2, session: worse, now: now.addingTimeInterval(20))!
        XCTAssertEqual(r3.bolts, 0)
        XCTAssertEqual(p3.best(for: 12)?.bestStars, 3)
        XCTAssertEqual(p3.best(for: 12)!.bestPrecision, 1, accuracy: 1e-12)
        XCTAssertEqual(p3.best(for: 12)!.layoutPrecision, 1, accuracy: 1e-12, "Layout belongs to the best precision")
        XCTAssertEqual(p3.best(for: 12)!.clears, 3)
    }

    func testEqualPrecisionKeepsEarlierLayout() {
        let level = TestContent.level(3)
        let finish = FinishRun(content: content)
        let a = wonSession(level: level, accuracies: Array(repeating: 0.9, count: level.targetFloors))
        let (p1, _) = finish.execute(Profile.fresh(now: now), session: a, now: now)!
        let b = wonSession(level: level, accuracies: Array(repeating: 0.9, count: level.targetFloors))
        let (p2, _) = finish.execute(p1, session: b, now: now.addingTimeInterval(60))!
        XCTAssertEqual(p2.best(for: 3)!.layoutDate, now)
    }

    func testFailedRunGivesNothingAndKeepsBest() {
        let level = TestContent.level(4)
        var s = StartRun(content: content).campaign(level: level, settings: GameSettings(), now: now)
        s.stage = .failed
        s.failReason = .tooMuchStrain
        let (p, r) = FinishRun(content: content).execute(Profile.fresh(now: now), session: s, now: now)!
        XCTAssertFalse(r.success)
        XCTAssertEqual(r.bolts, 0)
        XCTAssertEqual(p.walletBalance, 0)
        XCTAssertTrue(p.levelBests.isEmpty)
    }

    // MARK: Campaign

    func testSequentialUnlockAndLastLevel() {
        var profile = Profile.fresh(now: now)
        var campaign = Campaign(content: content, profile: profile)
        XCTAssertEqual(campaign.nextLevelID, 1)
        XCTAssertTrue(campaign.isUnlocked(1))
        XCTAssertFalse(campaign.isUnlocked(2))
        XCTAssertFalse(campaign.freeBuildUnlocked)
        XCTAssertFalse(campaign.isDistrictUnlocked(content.district(2)!))

        profile.levelBests = (1...120).map { id in
            let level = content.level(id)!
            return LevelBest(levelID: id, bestStars: 1, bestPrecision: 0.5,
                             layout: (0..<level.targetFloors).map { _ in Placement(centerX: 0, accuracy: 0.5, assetID: "F01", kind: .normal) },
                             layoutPrecision: 0.5, layoutDate: now, layoutAssisted: false, firstClearedAt: now, clears: 1)
        }
        campaign = Campaign(content: content, profile: profile)
        XCTAssertNil(campaign.nextLevelID, "No Level 121")
        XCTAssertTrue(campaign.isCampaignComplete)
        XCTAssertTrue(campaign.freeBuildUnlocked)
        XCTAssertEqual(campaign.districtUnlocked(byClearing: 20)?.id, 2)
        XCTAssertNil(campaign.districtUnlocked(byClearing: 120))
    }

    // MARK: Workshop

    func testPurchaseChecksBalanceAndIsAtomic() {
        var profile = Profile.fresh(now: now)
        profile.walletBalance = 45
        let fail = Workshop.purchase(profile, themeID: "ocean", content: content, now: now)
        XCTAssertEqual(fail, .failure(.notEnoughBolts(need: 80, have: 45)))

        profile.walletBalance = 145
        guard case .success(let bought) = Workshop.purchase(profile, themeID: "ocean", content: content, now: now) else { return XCTFail() }
        XCTAssertEqual(bought.walletBalance, 65)
        XCTAssertTrue(bought.ownsTheme("ocean"))
        XCTAssertEqual(bought.selectedTheme, "ocean")

        // Repeating the command for an owned theme spends nothing.
        guard case .success(let again) = Workshop.purchase(bought, themeID: "ocean", content: content, now: now) else { return XCTFail() }
        XCTAssertEqual(again.walletBalance, 65)
        XCTAssertEqual(again.unlockedThemes.filter { $0 == "ocean" }.count, 1)

        XCTAssertEqual(Workshop.equip(again, themeID: "warm"), .failure(.notOwned))
        guard case .success(let equipped) = Workshop.equip(again, themeID: "original") else { return XCTFail() }
        XCTAssertEqual(equipped.selectedTheme, "original")
    }

    func testThemesOnlyChangeFacadeSequence() {
        let level = TestContent.level(12)
        XCTAssertEqual(content.floorAsset(index: 0, level: level, themeID: "original"), "F06")
        XCTAssertEqual(content.floorAsset(index: 0, level: level, themeID: "sunshine"), "F03")
        XCTAssertEqual(content.floorAsset(index: 4, level: level, themeID: "sunshine"), "F05")
    }

    // MARK: Daily Supply

    func testDailyBandsAndCooldown() {
        let cfg = content.economy.daily
        XCTAssertEqual(DailySupply.band(for: 0, config: cfg), 0)
        XCTAssertEqual(DailySupply.band(for: 59, config: cfg), 0)
        XCTAssertEqual(DailySupply.band(for: 60, config: cfg), 1)
        XCTAssertEqual(DailySupply.band(for: 89, config: cfg), 1)
        XCTAssertEqual(DailySupply.band(for: 90, config: cfg), 2)
        XCTAssertEqual(DailySupply.band(for: 99, config: cfg), 2)

        let profile = Profile.fresh(now: now)
        XCTAssertTrue(DailySupply.isEligible(profile, now: now), "First claim is available immediately")
        let (claimed, receipt) = DailySupply.makeClaim(profile, now: now, roll: 75, config: cfg)!
        XCTAssertEqual(receipt.bolts, 35)
        XCTAssertEqual(receipt.symbols, ["R02", "R02", "F03"])
        XCTAssertEqual(claimed.walletBalance, 35)
        XCTAssertFalse(receipt.presented)
        XCTAssertNil(DailySupply.makeClaim(claimed, now: now.addingTimeInterval(3600), roll: 1, config: cfg))
        XCTAssertNotNil(DailySupply.makeClaim(claimed, now: now.addingTimeInterval(86_400), roll: 1, config: cfg))
    }

    func testClockRollbackDoesNotReopenDelivery() {
        let cfg = content.economy.daily
        var profile = Profile.fresh(now: now)
        profile.lastSeenWall = now
        let (claimed, _) = DailySupply.makeClaim(profile, now: now, roll: 10, config: cfg)!
        // Device clock moved back by two days.
        XCTAssertFalse(DailySupply.isEligible(claimed, now: now.addingTimeInterval(-172_800)))
        XCTAssertEqual(DailySupply.remaining(claimed, now: now.addingTimeInterval(-172_800)), 86_400, accuracy: 1)
    }

    func testResetKeepsSettingsAndOnboarding() {
        var profile = Profile.fresh(now: now)
        profile.walletBalance = 500
        profile.settings.music = false
        profile.settings.reducedMotion = true
        profile.onboarding = OnboardingState(step: 2, completed: true)
        profile.tutorialSeen = true
        let fresh = ResetProfile().execute(profile, now: now)
        XCTAssertEqual(fresh.walletBalance, 0)
        XCTAssertTrue(fresh.levelBests.isEmpty)
        XCTAssertNil(fresh.activeSession)
        XCTAssertTrue(fresh.walletReceipts.isEmpty)
        XCTAssertEqual(fresh.settings, profile.settings)
        XCTAssertTrue(fresh.onboarding.completed)
        XCTAssertTrue(fresh.tutorialSeen)
    }
}
