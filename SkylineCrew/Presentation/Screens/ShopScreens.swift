import SwiftUI

// MARK: - 21–24 Daily Supply

struct DailyScreen: View {
    enum Stage: Equatable {
        case ready
        case spinning(DailyReceipt, Date)
        case received(DailyReceipt, previous: Bool)
        case cooldown
    }

    @EnvironmentObject private var app: AppModel
    @Environment(\.mockMetrics) private var m
    @State private var stage: Stage = .ready
    @State private var now = Date()
    @State private var lastTickIndex: [Int] = [0, 0, 0]
    @State private var lastTickTime: TimeInterval = 0
    @State private var stoppedReels = 0
    @State private var stopItems: [DispatchWorkItem] = []
    @State private var claiming = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let stopTimes: [Double] = [1.6, 2.2, 2.8]
    private let present: Double = 3.2
    private let strip = ["F01", "F02", "F03", "R02", "R01"]
    private let cell: CGFloat = 110

    var body: some View {
        MockCanvas {
            BackgroundArt(id: "BG01")
            ScreenHeader(title: "Daily Supply", subtitle: subtitle, onBack: isSpinning ? nil : { app.pop() })
            if isSpinning {
                UIAsset("icon_back").opacity(0.35).mock(16, 58, 44, 44, h: .leading).accessibilityHidden(true)
            }
            MockBand(from: 236, to: 664) {
                cabinet
            }
            CreamCard(radius: 24).mock(0, 670, 390, max(174, 154 + m.safeBottom), v: .bottom, h: .stretch)
            Text(sheetTitle).mockStyle(18).mockText(195, 696, .middle, v: .bottom)
            Text("No purchases · Just building supplies").mockStyle(13, Palette.secondary).mockText(195, 719, .middle, v: .bottom)
            buttons
        }
        .onAppear(perform: setup)
        .onReceive(timer) { date in
            now = date
            if stage == .cooldown, DailySupply.isEligible(app.profile, now: app.clock.now) { stage = .ready }
        }
        .onChange(of: app.scenePhaseActive) { active in
            if active { now = Date(); if stage == .cooldown, DailySupply.isEligible(app.profile, now: app.clock.now) { stage = .ready } }
        }
        .onDisappear { stopItems.forEach { $0.cancel() } }
    }

    private var isSpinning: Bool { if case .spinning = stage { return true }; return false }

    private func setup() {
        if app.fixtureFlags.contains("dailySpinning"), let r = app.profile.daily.lastReceipt {
            stage = .spinning(r, .distantFuture)
            return
        }
        if app.fixtureFlags.contains("dailyReceived"), let r = app.profile.daily.lastReceipt {
            stage = .received(r, previous: false)
            return
        }
        // A receipt whose presentation was interrupted is restored without new RNG or credit.
        if let pending = app.profile.daily.lastReceipt, !pending.presented {
            stage = .received(pending, previous: false)
            app.markSupplyPresented(pending)
            return
        }
        stage = DailySupply.isEligible(app.profile, now: app.clock.now) ? .ready : .cooldown
    }

    private var remainingText: String {
        _ = now
        let secs = Int(DailySupply.remaining(app.profile, now: app.clock.now).rounded(.up))
        let h = secs / 3600, mnt = (secs % 3600) / 60
        if h > 0 { return "Next delivery in \(h)h \(mnt)m" }
        if mnt > 0 { return "Next delivery in \(mnt)m" }
        return "Next delivery in \(max(1, secs))s"
    }

    private var subtitle: String {
        switch stage {
        case .ready: return "A little help from the depot."
        case .spinning: return "Your delivery is on its way."
        case .received(let r, let previous): return previous ? "Previous delivery · \(r.bolts) Bolts" : "\(r.bolts) Bolts added to your toolbox."
        case .cooldown: return remainingText
        }
    }

    private var sheetTitle: String {
        switch stage {
        case .ready, .spinning: return "One free delivery every 24 hours"
        case .received(let r, let previous): return previous ? "Previous Delivery · +\(r.bolts) Bolts" : "+\(r.bolts) Bolts"
        case .cooldown: return remainingText
        }
    }

    @ViewBuilder
    private var buttons: some View {
        let half = (m.size.width - 52) / 2
        switch stage {
        case .ready:
            SkinButton(title: "Collect Supply", sound: nil, action: collect)
                .mock(20, 738, 350, 60, v: .bottom, h: .stretch)
        case .spinning(let r, _):
            SkinButton(title: "Skip Animation", sound: .tap) { finishSpin(r, skipped: true) }
                .mock(20, 738, 350, 60, v: .bottom, h: .stretch)
        case .received(_, let previous):
            SkinButton(title: "Done") {
                if previous { stage = .cooldown } else { app.goHome() }
            }
            .placed(20, 738 + m.bottomShift, half, 60)
            SkinButton(title: "Workshop", style: .quiet) { app.replaceTop(.workshop) }
                .placed(32 + half, 738 + m.bottomShift, half, 60)
        case .cooldown:
            SkinButton(title: "Come Back Tomorrow", enabled: false) {}
                .mock(20, 738, 350, 60, v: .bottom, h: .stretch)
        }
    }

    // MARK: Reel cabinet

    private var cabinet: some View {
        ZStack(alignment: .topLeading) {
            UIAsset("reel_cabinet").placed(20, 241, 350, 316)
            Text("CITY DEPOT").font(Typo.font(22)).foregroundColor(Palette.text).placedText(195, 279, .middle)
            ForEach(0..<3, id: \.self) { i in
                reel(i).placed(48 + 102 * CGFloat(i), 309, 92, 154)
            }
            Text("DAILY DELIVERY").font(Typo.font(15)).foregroundColor(.white).placedText(195, 517, .middle)
            ArtView("R01", .fit).placed(128, 557, 134, 102).accessibilityHidden(true)
            if stage == .cooldown, let last = app.profile.daily.lastReceipt {
                TapArea(label: "View last delivery", hint: "Shows the previous delivery without collecting") {
                    stage = .received(last, previous: true)
                }
                .placed(20, 241, 350, 316)
            }
        }
    }

    private func finalSymbols() -> [String] {
        switch stage {
        case .spinning(let r, _), .received(let r, _): return r.symbols
        case .cooldown: return app.profile.daily.lastReceipt?.symbols ?? ["F01", "F02", "F03"]
        case .ready: return ["F01", "F02", "F03"]
        }
    }

    @ViewBuilder
    private func reel(_ i: Int) -> some View {
        let symbols = finalSymbols()
        if case .spinning(let receipt, let started) = stage {
            if app.reduceMotion {
                // Reduce Motion: no spinning, sequential 150 ms fades at the stop times.
                TimelineView(.periodic(from: started, by: 0.05)) { tl in
                    let t = tl.date.timeIntervalSince(started)
                    let shown = t >= stopTimes[i]
                    symbol(shown ? receipt.symbols[i] : strip[i])
                        .opacity(shown ? 1 : 0.25)
                        .animation(.easeInOut(duration: 0.15), value: shown)
                }
            } else {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSince(started)
                    spinningStrip(reel: i, t: t, target: receipt.symbols[i])
                }
                .clipped()
            }
        } else {
            symbol(symbols[i])
        }
    }

    private func symbol(_ id: String) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 92, height: 154)
            ArtView(id, .fit).placed(5, 19, 80, 90)
        }
        .accessibilityElement()
        .accessibilityLabel(symbolName(id))
    }

    private func symbolName(_ id: String) -> String {
        switch id {
        case "R02": return "Gold star"
        case "R01": return "Supply crate"
        default: return "Floor"
        }
    }

    /// Reel position: total travel eases out and lands exactly on the already-recorded symbol.
    private func spinningStrip(reel i: Int, t: Double, target: String) -> some View {
        let targetIndex = strip.firstIndex(of: target) ?? 0
        // Reels start on the idle symbols (F01, F02, F03) and land on the stored receipt.
        let startIndex = i
        let steps = (targetIndex - startIndex + strip.count) % strip.count
        let cycles = [4, 6, 8][i]
        let total = CGFloat(cycles * strip.count + steps) * cell
        let x = min(1, max(0, t / stopTimes[i]))
        let eased = 1 - pow(1 - x, 3)
        let travel = CGFloat(startIndex) * cell + total * CGFloat(eased)
        let loop = cell * CGFloat(strip.count)
        let offset = travel.truncatingRemainder(dividingBy: loop)
        let base = Int(offset / cell)
        let frac = offset / cell - CGFloat(base)
        DispatchQueue.main.async { tickIfNeeded(reel: i, index: Int(travel / cell), t: t) }
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 92, height: 154)
            ForEach(-1...1, id: \.self) { j in
                let idx = ((base - j) % strip.count + strip.count) % strip.count
                ArtView(strip[idx], .fit).placed(5, 19 + (frac + CGFloat(j)) * cell, 80, 90)
            }
        }
    }

    private func tickIfNeeded(reel: Int, index: Int, t: Double) {
        guard isSpinning, t < stopTimes[reel] else { return }
        if index != lastTickIndex[reel] {
            lastTickIndex[reel] = index
            let wall = ProcessInfo.processInfo.systemUptime
            if wall - lastTickTime >= 0.1 { // S27 at most 10 Hz
                lastTickTime = wall
                app.playSound(.reelTick)
            }
        }
    }

    // MARK: Actions

    private func collect() {
        guard !claiming else { return }
        claiming = true
        app.claimSupply { receipt in
            claiming = false
            startSpin(receipt)
        }
        // A failed write keeps the reels still; Retry in 34 repeats the same transaction.
        DispatchQueue.main.async { if app.pendingSave != nil { claiming = false } }
    }

    private func startSpin(_ receipt: DailyReceipt) {
        app.playSound(.tap)
        lastTickIndex = [0, 0, 0]
        stoppedReels = 0
        stage = .spinning(receipt, Date())
        stopItems.forEach { $0.cancel() }
        stopItems = stopTimes.map { time in
            let item = DispatchWorkItem { app.playSound(.reelStop) }
            DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: item)
            return item
        }
        let end = DispatchWorkItem { finishSpin(receipt, skipped: false) }
        stopItems.append(end)
        DispatchQueue.main.asyncAfter(deadline: .now() + present, execute: end)
    }

    /// Skip shows the same recorded receipt immediately.
    private func finishSpin(_ receipt: DailyReceipt, skipped: Bool) {
        guard isSpinning else { return }
        stopItems.forEach { $0.cancel() }
        stopItems.removeAll()
        app.audio.stopEffects()
        app.playSound(.supply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { app.playSound(.bolts) }
        stage = .received(receipt, previous: false)
        app.markSupplyPresented(receipt)
    }
}

// MARK: - 25 Workshop

struct WorkshopScreen: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let skins = app.content.economy.skins
        return MockCanvas {
            BackgroundArt(id: "BG02")
            ScreenHeader(title: "Workshop", subtitle: "Same city. Your own character.") { app.pop() }
            BoltsChip(amount: app.profile.walletBalance, compact: true)
            MockScrollBand(from: 180, to: 770, contentBottom: 760) {
                ForEach(Array(skins.enumerated()), id: \.element.id) { i, skin in
                    row(skin, y: 185 + 145 * CGFloat(i))
                }
            }
            CreamCard(radius: 24).mock(20, 778, 350, 34, v: .bottom, h: .stretch)
            Text("Colors change. Your timing stays yours.").mockStyle(14).mockText(195, 801, .middle, v: .bottom)
        }
    }

    private func row(_ skin: ThemeSkin, y: CGFloat) -> some View {
        let equipped = app.profile.selectedTheme == skin.id
        let owned = app.profile.ownsTheme(skin.id)
        let status = equipped ? "Equipped" : (owned ? "Owned" : "\(skin.cost) Bolts")
        return ZStack(alignment: .topLeading) {
            CreamCard(radius: 24).mock(20, y, 350, 128, h: .stretch)
            Text(skin.name).mockStyle(20).mockText(38, y + 34, .start)
            Text(status).mockStyle(15, equipped ? Palette.secondary : (owned ? Palette.success : Palette.secondary))
                .mockText(351, y + 34, .end)
            ForEach(Array(skin.previewAssets.enumerated()), id: \.offset) { j, asset in
                ArtView(asset, .fit).mock(36 + 107 * CGFloat(j), y + 46, 96, 58)
            }
            TapArea(label: skin.name, hint: equipped ? "Equipped" : (owned ? "Owned. Double tap to use" : "Costs \(skin.cost) Bolts"), sound: nil) {
                app.themeTapped(skin.id)
            }
            .mock(20, y, 350, 128, h: .stretch)
        }
    }
}
