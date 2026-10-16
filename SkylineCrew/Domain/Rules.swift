import Foundation

// MARK: - Scores

enum Scoring {
    /// Precision = Σ accuracy_i / targetFloors.
    static func precision(_ placements: [Placement], target: Int) -> Double {
        guard target > 0 else { return 0 }
        let sum = placements.reduce(0.0) { $0 + $1.accuracy }
        return min(1, max(0, sum / Double(target)))
    }

    /// Thresholds are checked before rounding.
    static func stars(precision p: Double, level: LevelConfig) -> Int {
        if p >= level.star3Accuracy - RunRules.epsilon { return 3 }
        if p >= level.star2Accuracy - RunRules.epsilon { return 2 }
        return 1
    }

    static func percent(_ p: Double) -> Int { Int((p * 100).rounded()) }

    /// firstClearBolts on the first clear + 5 × max(0, newStars − oldBestStars).
    static func reward(level: LevelConfig, firstClear: Bool, oldBestStars: Int, newStars: Int) -> Int {
        let base = firstClear ? level.firstClearBolts : 0
        let bonus = min(level.maxStarBonusBolts, 5 * max(0, newStars - (firstClear ? 0 : oldBestStars)))
        return base + bonus
    }

    /// Free Build ordering: higher height wins; equal height → higher precision.
    static func isBetterFree(height: Int, precision: Double, than other: FreeBuildRecord?) -> Bool {
        guard let other else { return height > 0 }
        if height != other.height { return height > other.height }
        return precision > other.precision + RunRules.epsilon
    }
}

// MARK: - Campaign progression

struct Campaign {
    let content: GameContent
    let completed: Set<Int>

    init(content: GameContent, profile: Profile) {
        self.content = content
        self.completed = profile.completedLevelIDs
    }

    func isComplete(_ levelID: Int) -> Bool { completed.contains(levelID) }

    /// The next level opens after the current one is cleared, regardless of stars. Replays are always open.
    func isUnlocked(_ levelID: Int) -> Bool {
        guard content.level(levelID) != nil else { return false }
        return levelID == 1 || completed.contains(levelID) || completed.contains(levelID - 1)
    }

    /// First level that is not completed yet; nil after Level 120.
    var nextLevelID: Int? {
        content.levels.map(\.id).first { !completed.contains($0) && isUnlocked($0) }
    }

    var isCampaignComplete: Bool { content.levels.allSatisfy { completed.contains($0.id) } }

    func isDistrictUnlocked(_ d: District) -> Bool {
        guard let after = d.unlockAfterLevel else { return true }
        return completed.contains(after)
    }

    func completedCount(in d: District) -> Int { d.levelRange.filter { completed.contains($0) }.count }

    /// District that contains the next level, or the last one once everything is built.
    var currentDistrict: District {
        if let next = nextLevelID, let d = content.district(forLevel: next) { return d }
        return content.districts.last!
    }

    var freeBuildUnlocked: Bool { completed.contains(GameContent.freeBuildUnlockLevel) }

    /// The district whose last level is `levelID`, if clearing it opens a new district.
    func districtUnlocked(byClearing levelID: Int) -> District? {
        content.districts.first { $0.unlockAfterLevel == levelID }
    }
}

// MARK: - Daily Supply

enum DailySupply {
    /// nowEffective = max(systemWallClock, lastSeenWall): a clock rollback can't reopen a delivery.
    static func effectiveNow(system: Date, lastSeen: Date) -> Date { max(system, lastSeen) }

    static func isEligible(_ profile: Profile, now: Date) -> Bool {
        guard let next = profile.daily.nextEligibleAt else { return true }
        return effectiveNow(system: now, lastSeen: profile.lastSeenWall) >= next
    }

    static func remaining(_ profile: Profile, now: Date) -> TimeInterval {
        guard let next = profile.daily.nextEligibleAt else { return 0 }
        return max(0, next.timeIntervalSince(effectiveNow(system: now, lastSeen: profile.lastSeenWall)))
    }

    /// Uniform 0…99 → band by cumulative weight (60 / 30 / 10).
    static func band(for roll: Int, config: DailyConfig) -> Int {
        var acc = 0
        for (i, b) in config.bands.enumerated() {
            acc += b.weight
            if roll < acc { return i }
        }
        return max(0, config.bands.count - 1)
    }

    /// Builds the claim transaction. The caller persists it atomically *before* the reels spin.
    static func makeClaim(_ profile: Profile, now: Date, roll: Int, config: DailyConfig, id: UUID = UUID()) -> (Profile, DailyReceipt)? {
        guard isEligible(profile, now: now) else { return nil }
        let eff = effectiveNow(system: now, lastSeen: profile.lastSeenWall)
        let idx = band(for: roll, config: config)
        let band = config.bands[idx]
        let receipt = DailyReceipt(id: id, roll: roll, bandIndex: idx, bolts: band.bolts, symbols: band.symbols, claimedAt: eff, presented: false)
        var p = profile
        p.walletBalance += band.bolts
        p.walletReceipts.append(WalletEntry(id: id, kind: .dailySupply, amount: band.bolts, balanceAfter: p.walletBalance, date: eff, reference: "daily"))
        p.daily.lastReceipt = receipt
        p.daily.nextEligibleAt = eff.addingTimeInterval(config.cooldownSeconds)
        p.lastSeenWall = eff
        return (p, receipt)
    }
}

// MARK: - Workshop themes

enum ThemeError: Error, Equatable {
    case unknownTheme
    case notEnoughBolts(need: Int, have: Int)
    case notOwned
}

enum Workshop {
    /// Unlock checks balance and ownership, then atomically spends, adds and equips. Repeating it for an owned theme spends nothing.
    static func purchase(_ profile: Profile, themeID: String, content: GameContent, now: Date, transactionID: UUID = UUID()) -> Result<Profile, ThemeError> {
        guard let theme = content.theme(themeID) else { return .failure(.unknownTheme) }
        var p = profile
        if p.ownsTheme(themeID) {
            p.selectedTheme = themeID
            return .success(p)
        }
        guard p.walletBalance >= theme.cost else {
            return .failure(.notEnoughBolts(need: theme.cost, have: p.walletBalance))
        }
        p.walletBalance -= theme.cost
        p.unlockedThemes.append(themeID)
        p.selectedTheme = themeID
        p.walletReceipts.append(WalletEntry(id: transactionID, kind: .themePurchase, amount: -theme.cost, balanceAfter: p.walletBalance, date: now, reference: themeID))
        return .success(p)
    }

    static func equip(_ profile: Profile, themeID: String) -> Result<Profile, ThemeError> {
        guard profile.ownsTheme(themeID) else { return .failure(.notOwned) }
        var p = profile
        p.selectedTheme = themeID
        return .success(p)
    }
}
