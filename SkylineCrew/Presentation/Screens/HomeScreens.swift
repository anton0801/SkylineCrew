import SwiftUI

// MARK: - 01–03 Onboarding

struct OnboardingScreen: View {
    let step: Int
    @EnvironmentObject private var app: AppModel
    @Environment(\.uiSound) private var uiSound

    private static let pages: [(art: String, title: String, lines: [String])] = [
        ("OB01", "Build a little higher", ["Stack colorful floors and give the", "city a new skyline."]),
        ("OB02", "Find the perfect moment", ["Tap when the edges line up. Three", "perfect drops earn a brace."]),
        ("OB03", "Make the city yours", ["Finish towers, visit new districts and", "collect your best builds."])
    ]

    var body: some View {
        let page = Self.pages[min(max(step, 0), 2)]
        return MockCanvas {
            BackgroundArt(id: page.art)
            CreamCard(radius: 24).mock(14, 576, 362, 234, v: .bottom, h: .stretch)
            Text(page.title).mockStyle(26).accessibilityAddTraits(.isHeader).mockText(195, 619, .middle, v: .bottom)
            ForEach(Array(page.lines.enumerated()), id: \.offset) { i, line in
                Text(line).mockStyle(17, Palette.secondary).mockText(195, 650 + 24 * CGFloat(i), .middle, v: .bottom)
            }
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(i == step ? Palette.royalBlue : Palette.dotOff)
                    .mock(CGFloat(173 + 18 * i), 714, 8, 8, v: .bottom)
                    .accessibilityHidden(true)
            }
            AXLabel(label: "Step \(step + 1) of 3").mock(165, 706, 60, 24, v: .bottom)
            SkinButton(title: step < 2 ? "Next" : "Let’s Build") {
                if step < 2 { app.onboardingNext(from: step) } else { app.finishOnboardingAndPractice() }
            }
            .mock(20, 738, 350, 60, v: .bottom, h: .stretch)
            if step < 2 {
                Button {
                    uiSound(.tap)
                    app.skipOnboarding()
                } label: {
                    Text("Skip").mockStyle(17).padding(12).contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Skip introduction")
                .mockText(348 + 12, 85, .end)
            }
            if step > 0 {
                IconButton(icon: "icon_back", label: "Back", sound: .back) { app.pop() }
                    .mock(20, 58, 44, 44, h: .leading)
            }
        }
    }
}

// MARK: - 04 Home / 37 First Visit

struct HomeScreen: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.mockMetrics) private var m

    private var greeting: String {
        if app.isNewPlayer { return "Your city starts here" }
        let hour = Calendar.current.component(.hour, from: app.clock.now)
        switch hour {
        case 5..<12: return "Good morning, builder!"
        case 12..<18: return "Good afternoon, builder!"
        default: return "Good evening, builder!"
        }
    }

    private var subtitle: String {
        let c = app.campaign
        if let active = app.profile.activeSession {
            if let id = active.mode.levelID, let d = app.content.district(forLevel: id) {
                return "\(d.name.uppercased()) · LEVEL \(id)"
            }
            return "FREE BUILD · IN PROGRESS"
        }
        if app.isNewPlayer { return "\(c.currentDistrict.name.uppercased()) · LET’S BUILD" }
        if let next = c.nextLevelID { return "\(c.currentDistrict.name.uppercased()) · LEVEL \(next)" }
        return "CITY COMPLETE · FREE BUILD"
    }

    private var continueTitle: String {
        let c = app.campaign
        if let active = app.profile.activeSession {
            if let id = active.mode.levelID { return "Resume · Level \(id)" }
            return "Resume · Free Build"
        }
        if app.isNewPlayer { return "Build Level 1" }
        if let next = c.nextLevelID { return "Continue · Level \(next)" }
        return "Free Build"
    }

    private func continueTapped() {
        let c = app.campaign
        if app.profile.activeSession != nil {
            app.resumeActiveSession()
        } else if let next = c.nextLevelID {
            app.playSound(.levelSelect)
            app.push(.brief(next))
        } else {
            app.push(.freeBuild)
        }
    }

    var body: some View {
        let first = app.isNewPlayer
        let seq = app.content.themeSequence(app.profile.selectedTheme)
        let count = first ? 3 : 5
        let floors = (0..<count).map { TowerFloor(asset: seq[$0 % seq.count]) }
        let half = (m.size.width - 52) / 2

        return MockCanvas {
            BackgroundArt(id: "BG01")
            LogoView(scale: 1).mock(22, 70, 220, 64, h: .leading)
            BoltsChip(amount: app.profile.walletBalance)
            Text(greeting).mockStyle(23).accessibilityAddTraits(.isHeader).mockText(22, 161, .start)
            Text(subtitle).mockStyle(13, Palette.secondary).mockText(22, 187, .start)

            MockBand(from: 250, to: 690, align: 1) {
                TowerView(spec: .home, floors: floors)
                ArtView("C01", .fit).placed(276, 505, 85, 123).accessibilityHidden(true)
            }

            homeIcon("icon_collection", "Collection", x: 22, pin: .leading) {
                app.push(.collection)
            }
            homeIcon("icon_brace", "Workshop", x: 173, pin: .center) { app.push(.workshop) }
            homeIcon("icon_gear", "Settings", x: 325, pin: .trailing) { app.push(.settings) }

            SkinButton(title: continueTitle, sound: nil, action: continueTapped)
                .mock(20, 658, 350, 60, v: .bottom, h: .stretch)
            SkinButton(title: "Daily Supply", style: .secondary) { app.push(.daily) }
                .placed(20, 728 + m.bottomShift, half, 60)
            SkinButton(title: "Districts", style: .quiet) { app.push(.districts) }
                .placed(32 + half, 728 + m.bottomShift, half, 60)
        }
    }

    private func homeIcon(_ icon: String, _ title: String, x: CGFloat, pin: HPin, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            UIAsset(icon).mock(x, 213, 44, 44, h: pin)
            Text(title).mockStyle(12).mockText(x + 22, 273, .middle, h: pin)
            TapArea(label: title, action: action).mock(x - 14, 205, 72, 76, h: pin)
        }
    }
}

// MARK: - 05 / 38 Districts (one scrolling list of six)

struct DistrictsScreen: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.mockMetrics) private var m
    @State private var scrollProgress: CGFloat = 0
    @State private var shake: Int?

    /// Scroll distance between 05 (districts 1–3) and 38 (districts 4–6).
    private let pageShift: CGFloat = 676

    var body: some View {
        let c = app.campaign
        let districts = app.content.districts
        let viewportTop: CGFloat = 150
        let top = viewportTop + m.topShift
        let viewport = m.size.height - top
        return MockCanvas {
            BackgroundArt(id: "BG01")
            BackgroundArt(id: "BG03").opacity(Double(scrollProgress))
            ScreenHeader(title: "Districts", subtitle: "Six places to leave your mark.") { app.pop() }

            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    // 05: cards at y 160/344/528, note at 724; 38: cards 4–6 and the second note one page lower.
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 10)
                        ForEach(Array(districts.prefix(3).enumerated()), id: \.element.id) { i, d in
                            if i > 0 { Spacer().frame(height: 14) }
                            card(d, campaign: c)
                        }
                        Spacer().frame(height: 26)
                        note(["Market Mile, Marina View and Sky", "Gardens continue below."])
                        Spacer().frame(height: 26)
                        ForEach(Array(districts.dropFirst(3).enumerated()), id: \.element.id) { i, d in
                            if i > 0 { Spacer().frame(height: 14) }
                            card(d, campaign: c)
                        }
                        Spacer().frame(height: 26)
                        note(["Finish one district to open the", "next."])
                        Spacer().frame(height: 34).id("districts-bottom")
                    }
                    .frame(width: m.size.width, alignment: .leading)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: -proxy.frame(in: .named("districts")).minY)
                    })
                }
                .coordinateSpace(name: "districts")
                .onPreferenceChange(ScrollOffsetKey.self) { offset in updateProgress(offset) }
                .modifier(ScrollOffsetTracking(onChange: updateProgress))
                .onAppear {
                    if app.fixtureFlags.contains("districtsBottom") {
                        DispatchQueue.main.async { reader.scrollTo("districts-bottom", anchor: .bottom) }
                    }
                }
            }
            .placed(0, top, m.size.width, viewport)
        }
    }

    private func updateProgress(_ offset: CGFloat) {
        let p = min(1, max(0, offset / pageShift))
        if abs(p - scrollProgress) > 0.004 || (p != scrollProgress && (p == 0 || p == 1)) { scrollProgress = p }
    }

    private func card(_ d: District, campaign c: Campaign) -> some View {
        let unlocked = c.isDistrictUnlocked(d)
        let status: String
        if unlocked {
            status = "\(c.completedCount(in: d)) / 20"
        } else {
            let prev = app.content.districts.first { $0.lastLevel == d.unlockAfterLevel }
            status = "Clear \(prev?.name ?? "the previous district")"
        }
        let w = 350 + m.widthDelta
        return Button {
            if unlocked {
                app.playSound(.levelSelect)
                app.push(.levelMap(d.id))
            } else {
                app.playSound(.unavailable)
                withAnimation(.default) { shake = d.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { shake = nil }
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22).fill(Palette.cream)
                ArtView(d.background, .fill)
                    .frame(width: w - 2, height: 113).clipped()
                    .offset(x: 1, y: 1)
                RoundedRectangle(cornerRadius: 19).fill(Palette.cream)
                    .frame(width: w - 2, height: 69)
                    .offset(x: 1, y: 100)
                Text(d.name).mockStyle(20).placedText(16, 129, .start)
                Text(status).mockStyle(14, Palette.secondary).placedText(16, 153, .start)
                UIAsset(unlocked ? "icon_chevron" : "icon_lock").frame(width: 30, height: 30).offset(x: w - 49, y: 118)
            }
            .frame(width: w, height: 170, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.name)
        .accessibilityValue(status)
        .accessibilityAddTraits(.isButton)
        .padding(.leading, 20)
        .offset(x: shake == d.id ? 6 : 0)
        .animation(shake == d.id ? .easeInOut(duration: 0.07).repeatCount(4, autoreverses: true) : .default, value: shake)
    }

    private func note(_ lines: [String]) -> some View {
        let w = 350 + m.widthDelta
        return ZStack(alignment: .topLeading) {
            CreamCard(radius: 24)
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line).mockStyle(15, Palette.secondary).placedText(16, 26 + 23 * CGFloat(i), .start)
            }
        }
        .frame(width: w, height: 83, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.joined(separator: " "))
        .padding(.leading, 20)
        .padding(.bottom, 3)
    }
}

/// iOS 18+: native scroll geometry; iOS 15–17 rely on the GeometryReader preference above.
struct ScrollOffsetTracking: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, new in
                onChange(new)
            }
        } else {
            content
        }
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - 06 Level Map

struct LevelMapScreen: View {
    let districtID: Int
    @EnvironmentObject private var app: AppModel
    @Environment(\.mockMetrics) private var m
    @State private var lockedMessage: String?

    var body: some View {
        let c = app.campaign
        let district = app.content.district(districtID) ?? app.content.districts[0]
        let done = c.completedCount(in: district)
        return MockCanvas {
            BackgroundArt(id: district.background)
            ScreenHeader(title: district.name, subtitle: "\(done) / 20 towers complete") { app.pop() }
            CreamCard(radius: 24)
                .placed(20, 159 + m.topShift, 350 + m.widthDelta, (736 + m.bottomShift) - (159 + m.topShift))
            MockBand(from: 170, to: 730) {
                ForEach(Array(district.levelRange.enumerated()), id: \.element) { i, id in
                    tile(id: id, x: 45 + 84 * CGFloat(i % 4), y: 184 + 107 * CGFloat(i / 4), campaign: c)
                }
                if let lockedMessage {
                    Text(lockedMessage).mockStyle(14, Palette.secondary).placedText(195, 712, .middle)
                        .transition(.opacity)
                }
            }
            primaryButton(district: district, campaign: c)
                .mock(20, 756, 350, 60, v: .bottom, h: .stretch)
        }
    }

    @ViewBuilder
    private func tile(id: Int, x: CGFloat, y: CGFloat, campaign c: Campaign) -> some View {
        let complete = c.isComplete(id)
        let unlocked = c.isUnlocked(id)
        let stars = app.profile.best(for: id)?.bestStars ?? 0
        ZStack(alignment: .topLeading) {
            if complete || unlocked {
                Group {
                    if complete {
                        RoundedRectangle(cornerRadius: 17).fill(Color.white)
                    } else {
                        RoundedRectangle(cornerRadius: 17).fill(Palette.goldGradient)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.tileStroke, lineWidth: 2))
                .placed(x, y, 59, 60)
                Text("\(id)").mockStyle(22).placedText(x + 29, y + 37, .middle)
                if complete {
                    Text(String(repeating: "★", count: stars)).font(Typo.font(14)).foregroundColor(Palette.starText)
                        .placedText(x + 29, y + 82, .middle)
                }
            } else {
                RoundedRectangle(cornerRadius: 17).fill(Palette.lockedFill)
                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.lockedStroke, lineWidth: 2))
                    .placed(x, y, 59, 60)
                UIAsset("icon_lock").placed(x + 13, y + 13, 32, 32)
            }
            TapArea(label: unlocked ? "Level \(id)" : "Level \(id), locked",
                    hint: complete ? "\(stars) stars" : (unlocked ? "Current level" : "Finish Level \(id - 1) first"),
                    sound: unlocked ? .levelSelect : .unavailable) {
                if unlocked {
                    app.push(.brief(id))
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { lockedMessage = "Finish Level \(id - 1) to open Level \(id)." }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        withAnimation(.easeInOut(duration: 0.3)) { lockedMessage = nil }
                    }
                }
            }
            .placed(x - 8, y - 4, 75, 92)
        }
    }

    @ViewBuilder
    private func primaryButton(district: District, campaign c: Campaign) -> some View {
        if let next = c.nextLevelID, district.levelRange.contains(next) {
            SkinButton(title: "Build Level \(next)", sound: .levelSelect) { app.push(.brief(next)) }
        } else if let nextDistrict = app.content.district(district.id + 1) {
            if c.isDistrictUnlocked(nextDistrict) {
                SkinButton(title: "Next District") { app.replaceTop(.levelMap(nextDistrict.id)) }
            } else {
                SkinButton(title: "Clear \(district.name) First", enabled: false) {}
            }
        } else if c.isCampaignComplete {
            SkinButton(title: "City Complete") { app.push(.cityComplete) }
        } else {
            SkinButton(title: "Build Level \(c.nextLevelID ?? 1)", enabled: false) {}
        }
    }
}

// MARK: - 07 Build Brief

struct BriefScreen: View {
    let levelID: Int
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let level = app.content.level(levelID)!
        let district = app.content.district(forLevel: levelID)!
        let best = app.profile.best(for: levelID)
        let seq = app.content.themeSequence(app.profile.selectedTheme)
        let resuming = app.profile.activeSession?.mode == .campaign(levelID: levelID)
        let wind: String = !level.hasWind ? "Calm" : (level.changingWind ? "Changing gusts" : "Steady breeze")
        let bestText: String = best.map { "Best: \(Scoring.percent($0.bestPrecision))% · \($0.bestStars) \($0.bestStars == 1 ? "star" : "stars")" } ?? "Best: Not built yet"

        return MockCanvas {
            BackgroundArt(id: "BG01")
            ScreenHeader(title: "Level \(levelID)", subtitle: "\(district.name) · \(best == nil ? "Your next rooftop" : "Build it again")") { app.pop() }

            MockBand(from: 170, to: 492, align: 1) {
                ArtView("C01", .fit).placed(231, 177, 119, 171).accessibilityHidden(true)
                TowerView(spec: .brief, floors: (0..<3).map { TowerFloor(asset: seq[$0 % seq.count]) })
            }

            CreamCard(radius: 24).mock(20, 492, 350, 222, v: .bottom, h: .stretch)
            Text("The plan").mockStyle(25).accessibilityAddTraits(.isHeader).mockText(39, 529, .start, v: .bottom)
            RoundedRectangle(cornerRadius: 16).fill(Palette.panel).mock(20, 551, 350, 58, v: .bottom, h: .stretch)
            UIAsset("icon_flag").mock(29, 560, 36, 36, v: .bottom, h: .leading)
            Text("Target").mockStyle(17).mockText(75, 586, .start, v: .bottom)
            Text("\(level.targetFloors) floors").mockStyle(16, Palette.secondary).mockText(350, 586, .end, v: .bottom)
            Text("Wind: \(wind)").mockStyle(17).mockText(41, 644, .start, v: .bottom)
            Text(bestText).mockStyle(17, Palette.secondary).mockText(41, 678, .start, v: .bottom)
            SkinButton(title: resuming ? "Resume Building" : "Start Building", sound: nil) {
                app.requestStartLevel(levelID)
            }
            .mock(20, 745, 350, 60, v: .bottom, h: .stretch)
        }
    }
}
