import SwiftUI

// MARK: - 17 / 18 / 19 (+ Free Build result)

struct ResultsScreen: View {
    @EnvironmentObject private var app: AppModel
    @State private var revealedStars = 0
    @State private var announced = false

    var body: some View {
        Group {
            if let r = app.profile.lastResult {
                if r.mode == .freeBuild {
                    freeResult(r)
                } else if r.success {
                    clearResult(r)
                } else {
                    failedResult(r)
                }
            } else {
                Color.clear.onAppear { app.goHome() }
            }
        }
        .onAppear(perform: announce)
    }

    private var reduceMotion: Bool { app.reduceMotion }

    /// The receipt is already saved; this only presents it (re-entering never pays again).
    private func announce() {
        guard !announced, let r = app.profile.lastResult else { return }
        announced = true
        if !r.success && r.mode != .freeBuild {
            app.playSound(.retry)
            return
        }
        app.playSound(.complete)
        let stars = r.stars
        if reduceMotion || stars == 0 {
            revealedStars = stars
        } else {
            for i in 0..<stars {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + 0.12 * Double(i)) {
                    revealedStars = i + 1
                    app.playSound(.star)
                }
            }
        }
        if r.bolts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + 0.12 * Double(stars)) { app.playSound(.bolts) }
        }
        if r.unlockedDistrict != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { app.playSound(.district) }
        }
    }

    private func clearResult(_ r: RunResult) -> some View {
        let levelID = r.mode.levelID ?? 1
        let level = app.content.level(levelID)!
        let district = app.content.district(forLevel: levelID)!
        let c = app.campaign
        let next = levelID < app.content.lastLevelID ? levelID + 1 : nil
        let campaignDone = c.isCampaignComplete
        let rewardText: String = {
            if r.bolts > 0 {
                if r.firstClear { return "+\(r.bolts) Bolts · First clear" }
                let gained = r.stars - r.previousBestStars
                return "+\(r.bolts) Bolts · \(gained == 1 ? "New star" : "New stars")"
            }
            return "Best stays · \(Scoring.percent(app.profile.best(for: levelID)?.bestPrecision ?? r.precision))% precision"
        }()
        let goNext: () -> Void = {
            if let next {
                let nextDistrict = app.content.district(forLevel: next)?.id ?? district.id
                app.setStack([.home, .levelMap(nextDistrict), .brief(next)])
            }
            else if campaignDone { app.setStack([.home, .cityComplete]) }
        }
        let nextTitle = next == nil ? "City Complete" : "Next Level"

        return MockCanvas {
            BackgroundArt(id: level.background)
            if !reduceMotion { ConfettiView().allowsHitTesting(false) }
            IconButton(icon: "icon_back", label: "Level map", sound: .back) {
                app.setStack([.home, .levelMap(district.id)], forward: false)
            }
            .mock(16, 57, 44, 44, h: .leading)
            Text(r.stars >= 2 ? "A new rooftop!" : "The city keeps growing").mockStyle(28)
                .accessibilityAddTraits(.isHeader).mockText(195, 103, .middle)
            Text("Level \(levelID) · \(Scoring.percent(r.precision))% precision").mockStyle(16, Palette.secondary)
                .mockText(195, 137, .middle)
            starsRow(r.stars)

            MockBand(from: 207, to: 638, align: 1) {
                TowerView(spec: .result, floors: r.layout.towerFloors(floorWidth: 168), fitTop: 215)
                ArtView("C02", .fit).placed(270, 481, 81, 119).accessibilityHidden(true)
            }

            CreamCard(radius: 24).mock(20, 606, 350, 59, v: .bottom, h: .stretch)
            Text(rewardText).mockStyle(21).mockText(195, 644, .middle, v: .bottom)
            if r.stars >= 2 {
                SkinButton(title: nextTitle, enabled: next != nil || campaignDone, action: goNext)
                    .mock(20, 681, 350, 60, v: .bottom, h: .stretch)
                SkinButton(title: "View Tower", style: .quiet) { app.push(.towerDetail(.level(levelID))) }
                    .mock(20, 749, 350, 60, v: .bottom, h: .stretch)
            } else {
                SkinButton(title: "Try Again") { app.setStack([.home, .levelMap(district.id), .brief(levelID)]) }
                    .mock(20, 681, 350, 60, v: .bottom, h: .stretch)
                SkinButton(title: nextTitle, style: .quiet, enabled: next != nil || campaignDone, action: goNext)
                    .mock(20, 749, 350, 60, v: .bottom, h: .stretch)
            }
        }
    }

    private func starsRow(_ stars: Int) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { i in
                let x = 119 + 52 * CGFloat(i)
                if i < stars {
                    ArtView("R02", .fit)
                        .scaleEffect(i < revealedStars ? 1 : 0.4)
                        .opacity(i < revealedStars ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: revealedStars)
                        .mock(x, 161, 46, 46)
                } else {
                    UIAsset("empty_star").mock(x, 161, 46, 46)
                }
            }
            AXLabel(label: "\(stars) of 3 stars").mock(119, 161, 150, 46)
        }
    }

    private func failedResult(_ r: RunResult) -> some View {
        let levelID = r.mode.levelID ?? 1
        let level = app.content.level(levelID)!
        let district = app.content.district(forLevel: levelID)!
        let strain = r.failReason == .tooMuchStrain
        return MockCanvas {
            BackgroundArt(id: level.background)
            IconButton(icon: "icon_back", label: "Level map", sound: .back) {
                app.setStack([.home, .levelMap(district.id)], forward: false)
            }
            .mock(16, 57, 44, 44, h: .leading)
            Text("Almost there").mockStyle(28).accessibilityAddTraits(.isHeader).mockText(195, 103, .middle)
            Text(strain ? "The tower leaned a little too far." : "The last floor missed its support.")
                .mockStyle(16, Palette.secondary).mockText(195, 137, .middle)
            MockBand(from: 225, to: 500) {
                ArtView("C03", .fit).placed(94, 233, 200, 256).accessibilityHidden(true)
            }
            CreamCard(radius: 24).mock(20, 520, 350, 133, v: .bottom, h: .stretch)
            Text(strain ? "Too much strain" : "Missed support").mockStyle(23).mockText(195, 558, .middle, v: .bottom)
            Text(strain ? "Keep floors centered to ease the" : "Wait for the edges to meet. There")
                .mockStyle(16, Palette.secondary).mockText(195, 591, .middle, v: .bottom)
            Text(strain ? "load. There is always another try." : "is always another try.")
                .mockStyle(16, Palette.secondary).mockText(195, 614, .middle, v: .bottom)
            SkinButton(title: "Try Again") { app.setStack([.home, .levelMap(district.id), .brief(levelID)]) }
                .mock(20, 681, 350, 60, v: .bottom, h: .stretch)
            SkinButton(title: "Districts", style: .quiet) { app.setStack([.home, .districts, .levelMap(district.id)], forward: false) }
                .mock(20, 749, 350, 60, v: .bottom, h: .stretch)
        }
    }

    private func freeResult(_ r: RunResult) -> some View {
        let best = app.profile.freeBest
        let title: String = r.freeOutcome == .heightLimit ? "Height limit reached!" : (r.newRecord ? "New record!" : "Nice tower!")
        return MockCanvas {
            BackgroundArt(id: "BG03")
            if !reduceMotion && r.newRecord { ConfettiView().allowsHitTesting(false) }
            IconButton(icon: "icon_back", label: "Free Build", sound: .back) {
                app.setStack([.home, .freeBuild], forward: false)
            }
            .mock(16, 57, 44, 44, h: .leading)
            Text(title).mockStyle(28).accessibilityAddTraits(.isHeader).mockText(195, 103, .middle)
            Text("Free Build · \(r.floors) floors · \(Scoring.percent(r.precision))% precision")
                .mockStyle(16, Palette.secondary).mockText(195, 137, .middle)
            MockBand(from: 160, to: 638, align: 1) {
                TowerView(spec: .result, floors: r.layout.towerFloors(floorWidth: 168), roof: r.floors > 0, fitTop: 170)
                ArtView("C02", .fit).placed(270, 481, 81, 119).accessibilityHidden(true)
            }
            CreamCard(radius: 24).mock(20, 606, 350, 59, v: .bottom, h: .stretch)
            Text(best.map { "Best: \($0.height) floors · \(Scoring.percent($0.precision))%" } ?? "No record yet")
                .mockStyle(21).mockText(195, 644, .middle, v: .bottom)
            SkinButton(title: "Build Again", sound: nil) { app.setStack([.home, .freeBuild]); app.startFreeBuild() }
                .mock(20, 681, 350, 60, v: .bottom, h: .stretch)
            SkinButton(title: "Free Build", style: .quiet) { app.setStack([.home, .freeBuild], forward: false) }
                .mock(20, 749, 350, 60, v: .bottom, h: .stretch)
        }
    }
}

/// Max 24 small palette rectangles for 1.2 s (never with Reduce Motion).
struct ConfettiView: View {
    @Environment(\.mockMetrics) private var m
    @State private var start = Date()

    private struct Piece {
        let x: CGFloat, delay: Double, speed: CGFloat, drift: CGFloat, spin: Double, color: Color, w: CGFloat, h: CGFloat
    }

    private static let pieces: [Piece] = {
        let colors = [Palette.gold, Palette.royalBlue, Color(hex: 0xEF7E61), Palette.amber, Color(hex: 0x36C8E9), Palette.success]
        return (0..<24).map { i in
            let r = { (seed: Int) -> CGFloat in CGFloat(abs(sin(Double(i * 97 + seed) * 12.9898)).truncatingRemainder(dividingBy: 1)) }
            return Piece(x: 20 + r(1) * 350, delay: Double(r(2)) * 0.25, speed: 420 + r(3) * 280, drift: (r(4) - 0.5) * 80,
                         spin: Double(r(5) - 0.5) * 8, color: colors[i % colors.count], w: 6 + r(6) * 4, h: 10 + r(7) * 6)
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard t < 1.2 else { return }
                let sx = size.width / 390
                for p in Self.pieces {
                    let lt = max(0, t - p.delay)
                    guard lt > 0 else { continue }
                    let y = -20 + p.speed * CGFloat(lt) + 120 * CGFloat(lt * lt)
                    let x = p.x * sx + p.drift * CGFloat(lt)
                    let alpha = t > 0.9 ? max(0, (1.2 - t) / 0.3) : 1
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * lt))
                    c.fill(Path(CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h)), with: .color(p.color.opacity(alpha)))
                }
            }
        }
        .frame(width: m.size.width, height: m.size.height)
        .accessibilityHidden(true)
    }
}

// MARK: - 35 City Complete

struct CityCompleteScreen: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let seq = app.content.themeSequence(app.profile.selectedTheme)
        let floors = (0..<6).map { TowerFloor(asset: seq[$0 % seq.count]) }
        let built = app.profile.completedCount
        return MockCanvas {
            BackgroundArt(id: "BG03")
            if !app.reduceMotion { ConfettiView().allowsHitTesting(false) }
            IconButton(icon: "icon_back", label: "Replay Districts", sound: .back) { app.setStack([.home, .districts], forward: false) }
                .mock(16, 57, 44, 44, h: .leading)
            Text("Look what you built").mockStyle(28).accessibilityAddTraits(.isHeader).mockText(195, 103, .middle)
            Text("\(built) towers. One wonderful skyline.").mockStyle(16, Palette.secondary).mockText(195, 137, .middle)
            ForEach(0..<3, id: \.self) { i in
                ArtView("R02", .fit).mock(119 + 52 * CGFloat(i), 161, 46, 46)
            }
            MockBand(from: 207, to: 638, align: 1) {
                TowerView(spec: .cityComplete, floors: floors)
                ArtView("C02", .fit).placed(270, 481, 81, 119).accessibilityHidden(true)
            }
            CreamCard(radius: 24).mock(20, 606, 350, 59, v: .bottom, h: .stretch)
            Text("\(built) towers built").mockStyle(21).mockText(195, 644, .middle, v: .bottom)
            SkinButton(title: "Your Collection") { app.push(.collection) }
                .mock(20, 681, 350, 60, v: .bottom, h: .stretch)
            SkinButton(title: "Free Build", style: .quiet) { app.push(.freeBuild) }
                .mock(20, 749, 350, 60, v: .bottom, h: .stretch)
        }
        .onAppear { app.playSound(.district) }
    }
}

// MARK: - 20 Free Build

struct FreeBuildScreen: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let seq = app.content.themeSequence(app.profile.selectedTheme)
        let floors = (0..<7).map { TowerFloor(asset: seq[$0 % seq.count]) }
        let best = app.profile.freeBest
        let resuming = app.profile.activeSession?.mode == .freeBuild
        return MockCanvas {
            BackgroundArt(id: "BG03")
            ScreenHeader(title: "How high can you go?", subtitle: "No target. One tower. Your timing.") { app.pop() }
            MockBand(from: 165, to: 712, align: 1) {
                // Decoration only — the record is shown as text and opens its own saved layout.
                TowerView(spec: .showcase, floors: floors)
            }
            Group {
                if let best {
                    Text("Best: \(best.height) floors · \(Scoring.percent(best.precision))%").mockStyle(18)
                        .mockText(195, 727, .middle, v: .bottom)
                    TapArea(label: "Best tower, \(best.height) floors") { app.push(.towerDetail(.freeBest)) }
                        .mock(60, 704, 270, 32, v: .bottom)
                } else {
                    Text("No record yet").mockStyle(18).mockText(195, 727, .middle, v: .bottom)
                }
            }
            SkinButton(title: resuming ? "Resume Run" : "Start Run", sound: nil) { app.startFreeBuild() }
                .mock(20, 742, 350, 60, v: .bottom, h: .stretch)
        }
    }
}
