import SwiftUI

// MARK: - 29 Settings

struct SettingsScreen: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.uiSound) private var uiSound

    private struct ToggleRow {
        let icon: String
        let title: String
        let keyPath: WritableKeyPath<GameSettings, Bool>
        let hint: String
    }

    private let toggles: [ToggleRow] = [
        ToggleRow(icon: "icon_music", title: "Music", keyPath: \.music, hint: "Background music"),
        ToggleRow(icon: "icon_sound", title: "Sound Effects", keyPath: \.effects, hint: "Building and interface sounds"),
        ToggleRow(icon: "icon_bolt", title: "Haptics", keyPath: \.haptics, hint: "Vibration on landings"),
        ToggleRow(icon: "icon_shield", title: "Reduced Motion", keyPath: \.reducedMotion, hint: "Removes particles, bounce and spinning reels"),
        ToggleRow(icon: "icon_brace", title: "Timing Assist", keyPath: \.timingAssist, hint: "Slows the swing. Towers built with it are marked Assisted")
    ]

    var body: some View {
        MockCanvas {
            BackgroundArt(id: "BG01")
            ScreenHeader(title: "Settings", subtitle: "Sound, motion and your progress.") { app.pop() }
            MockScrollBand(from: 160, to: 844, contentBottom: 770, bottomPin: .bottom) {
                ForEach(Array(toggles.enumerated()), id: \.offset) { i, row in
                    toggleRow(row, y: 171 + 70 * CGFloat(i))
                }
                navRow(icon: "icon_help", title: "How to Build", y: 552) { app.push(.help) }
                navRow(icon: "icon_collection", title: "City Record", y: 622) { app.push(.stats) }
                navRow(icon: "icon_gear", title: "Progress & Data", y: 692) { app.push(.data) }
            }
        }
    }

    private func toggleRow(_ row: ToggleRow, y: CGFloat) -> some View {
        let isOn = app.profile.settings[keyPath: row.keyPath]
        let systemReduce = row.keyPath == \GameSettings.reducedMotion && UIAccessibility.isReduceMotionEnabled
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16).fill(Palette.panel).mock(20, y, 350, 58, h: .stretch)
            UIAsset(row.icon).mock(29, y + 9, 36, 36, h: .leading)
            Text(row.title).mockStyle(17).mockText(75, y + 35, .start)
            ToggleSkin(isOn: isOn || systemReduce).mock(301, y + 14, 52, 30, h: .trailing)
            Button {
                guard !systemReduce else { uiSound(.unavailable); return }
                uiSound(.toggle)
                app.haptics.play(.selection)
                app.updateSettings { $0[keyPath: row.keyPath].toggle() }
            } label: { Color.clear.contentShape(Rectangle()) }
            .buttonStyle(PressScaleStyle())
            .mock(20, y, 350, 58, h: .stretch)
            .accessibilityLabel(row.title)
            .accessibilityValue(isOn || systemReduce ? "On" : "Off")
            .accessibilityHint(systemReduce ? "Follows the system Reduce Motion setting" : row.hint)
            .accessibilityAddTraits(.isButton)
        }
    }

    private func navRow(icon: String, title: String, y: CGFloat, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16).fill(Palette.panel).mock(20, y, 350, 58, h: .stretch)
            UIAsset(icon).mock(29, y + 9, 36, 36, h: .leading)
            Text(title).mockStyle(17).mockText(75, y + 35, .start)
            Text("›").mockStyle(16, Palette.secondary).mockText(350, y + 35, .end)
            TapArea(label: title, action: action).mock(20, y, 350, 58, h: .stretch)
        }
    }
}

// MARK: - 30 How to Build

struct HelpScreen: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Rule { let icon: String; let title: String; let lines: [String] }

    private let rules = [
        Rule(icon: "icon_crane_hook", title: "Line up the edges", lines: ["Tap Drop Floor as the edges meet."]),
        Rule(icon: "icon_shield", title: "Keep it steady", lines: ["Off-center floors add strain."]),
        Rule(icon: "icon_star", title: "Build a perfect streak", lines: ["Three perfect drops charge a brace."]),
        Rule(icon: "icon_brace", title: "Use your brace", lines: ["The next floor lands safely in", "place."])
    ]

    private var dailyLines: [String] {
        let bands = app.content.economy.daily.bands
        var lines = ["One free delivery every 24 hours.", "The depot picks one delivery:"]
        for b in bands { lines.append("\(b.weight)% · \(b.bolts) Bolts") }
        lines.append("No purchases. Bolts only unlock colors.")
        return lines
    }

    var body: some View {
        MockCanvas {
            BackgroundArt(id: "BG01")
            ScreenHeader(title: "How to Build", subtitle: "Small moves. A taller skyline.") { app.pop() }
            if typeSize <= .large {
                MockScrollBand(from: 155, to: 725, contentBottom: 731 + 222) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { i, rule in
                        ruleCard(rule, y: 165 + 131 * CGFloat(i))
                    }
                    dailyCard(y: 731)
                }
            } else {
                flowingContent
            }
            SkinButton(title: "Practice", sound: .start) { app.startTutorial(origin: .help) }
                .mock(20, 733, 350, 60, v: .bottom, h: .stretch)
        }
    }

    private func ruleCard(_ rule: Rule, y: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            CreamCard(radius: 24).mock(20, y, 350, 117, h: .stretch)
            UIAsset(rule.icon).mock(32, y + 18, 38, 38, h: .leading)
            Text(rule.title).mockStyle(19).accessibilityHidden(true).mockText(80, y + 38, .start)
            ForEach(Array(rule.lines.enumerated()), id: \.offset) { j, line in
                Text(line).mockStyle(16, Palette.secondary).accessibilityHidden(true).mockText(38, y + 77 + 22 * CGFloat(j), .start)
            }
            AXLabel(label: rule.title + ". " + rule.lines.joined(separator: " ")).mock(20, y, 350, 117, h: .stretch)
        }
    }

    private func dailyCard(y: CGFloat) -> some View {
        let lines = dailyLines
        return ZStack(alignment: .topLeading) {
            CreamCard(radius: 24).mock(20, y, 350, 60 + 22 * CGFloat(lines.count), h: .stretch)
            UIAsset("icon_gift").mock(32, y + 18, 38, 38, h: .leading)
            Text("Daily Supply").mockStyle(19).accessibilityHidden(true).mockText(80, y + 38, .start)
            ForEach(Array(lines.enumerated()), id: \.offset) { j, line in
                Text(line).mockStyle(16, Palette.secondary).accessibilityHidden(true).mockText(38, y + 77 + 22 * CGFloat(j), .start)
            }
            AXLabel(label: "Daily Supply. " + lines.joined(separator: " ")).mock(20, y, 350, 60 + 22 * CGFloat(lines.count), h: .stretch)
        }
    }

    /// Large Dynamic Type: the same content reflows and scrolls.
    private var flowingContent: some View {
        FlowingScroll(from: 150, to: 725) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                    flowingCard(icon: rule.icon, title: rule.title, body: rule.lines.joined(separator: " "))
                }
                flowingCard(icon: "icon_gift", title: "Daily Supply", body: dailyLines.joined(separator: "\n"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func flowingCard(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                UIAsset(icon).frame(width: 38, height: 38)
                Text(title).font(Typo.scaled(19, relativeTo: .headline)).foregroundColor(Palette.text)
            }
            Text(body).font(Typo.scaled(16)).foregroundColor(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CreamCard(radius: 24))
        .accessibilityElement(children: .combine)
    }
}

/// Plain scrolling container between two mockup lines (Dynamic Type layouts).
struct FlowingScroll<Content: View>: View {
    let from: CGFloat
    let to: CGFloat
    @Environment(\.mockMetrics) private var m
    @ViewBuilder var content: () -> Content

    var body: some View {
        let top = from + m.topShift
        let bottom = to + m.bottomShift
        ScrollView(.vertical, showsIndicators: true) { content() }
            .frame(width: m.size.width, height: max(1, bottom - top))
            .placed(0, top, m.size.width, max(1, bottom - top))
    }
}

// MARK: - 31 City Record

struct StatsScreen: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        let p = app.profile
        let c = app.campaign
        let floorsTotal = p.levelBests.reduce(0) { $0 + $1.layout.count }
        let weighted = p.levelBests.reduce(0.0) { $0 + $1.layoutPrecision * Double($1.layout.count) }
        let precision: String = floorsTotal > 0 ? "\(Scoring.percent(weighted / Double(floorsTotal)))%" : "—"
        let bestTower = p.levelBests.max { $0.layoutPrecision < $1.layoutPrecision }
        let rows: [(String, String, String, (() -> Void)?)] = [
            ("icon_collection", "Towers built", "\(p.completedCount) / \(app.content.levels.count)", { app.push(.collection) }),
            ("icon_star", "Stars earned", "\(p.totalStars) / \(app.content.levels.count * 3)", { app.push(.collection) }),
            ("icon_brace", "Best-build precision", precision, bestTower.map { b in { app.push(.towerDetail(.level(b.levelID))) } }),
            ("icon_flag", "Free Build record", p.freeBest.map { "\($0.height) floors" } ?? "—", p.freeBest == nil ? nil : { app.push(.towerDetail(.freeBest)) }),
            ("icon_map", "Current district", c.currentDistrict.name, { app.push(.levelMap(c.currentDistrict.id)) })
        ]
        return MockCanvas {
            BackgroundArt(id: "BG03")
            ScreenHeader(title: "City Record", subtitle: "Your best builds, all in one place.") { app.pop() }
            MockScrollBand(from: 160, to: 725, contentBottom: 660) {
                ArtView("R02", .fit).mock(148, 169, 94, 94).accessibilityHidden(true)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    let y = 294 + 73 * CGFloat(i)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16).fill(Palette.panel).mock(20, y, 350, 58, h: .stretch)
                        UIAsset(row.0).mock(29, y + 9, 36, 36, h: .leading)
                        Text(row.1).mockStyle(17).mockText(75, y + 35, .start)
                        Text(row.2).mockStyle(16, Palette.secondary).mockText(350, y + 35, .end)
                        if let action = row.3 {
                            TapArea(label: "\(row.1), \(row.2)", action: action).mock(20, y, 350, 58, h: .stretch)
                        } else {
                            Color.clear.accessibilityElement().accessibilityLabel("\(row.1), \(row.2)").mock(20, y, 350, 58, h: .stretch)
                        }
                    }
                }
            }
            SkinButton(title: "View Collection") { app.push(.collection) }
                .mock(20, 735, 350, 60, v: .bottom, h: .stretch)
        }
    }
}

// MARK: - 32 Progress & Data

struct DataScreen: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        MockCanvas {
            BackgroundArt(id: "BG01")
            ScreenHeader(title: "Progress on this device", subtitle: "Your city is saved locally.") { app.pop() }
            if typeSize <= .large {
                ZStack(alignment: .topLeading) {
                    CreamCard(radius: 24).mock(20, 191, 350, 276, h: .stretch)
                    Text("Saved on this device").mockStyle(22).accessibilityHidden(true).mockText(39, 233, .start)
                    ForEach(Array(["Your towers, colors and Bolts", "stay in this app. No account is", "needed."].enumerated()), id: \.offset) { i, line in
                        Text(line).mockStyle(17, Palette.secondary).accessibilityHidden(true).mockText(39, 273 + 23 * CGFloat(i), .start)
                    }
                    ForEach(Array(["Deleting the app may remove", "your local progress."].enumerated()), id: \.offset) { i, line in
                        Text(line).mockStyle(17, Palette.secondary).accessibilityHidden(true).mockText(39, 385 + 23 * CGFloat(i), .start)
                    }
                    AXLabel(label: "Saved on this device. Your towers, colors and Bolts stay in this app. No account is needed. Deleting the app may remove your local progress.")
                        .mock(20, 191, 350, 276, h: .stretch)
                }
            } else {
                FlowingScroll(from: 150, to: 590) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Saved on this device").font(Typo.scaled(22, relativeTo: .title2)).foregroundColor(Palette.text)
                        Text("Your towers, colors and Bolts stay in this app. No account is needed.")
                        Text("Deleting the app may remove your local progress.")
                    }
                    .font(Typo.scaled(17))
                    .foregroundColor(Palette.secondary)
                    .padding(19)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CreamCard(radius: 24))
                    .padding(20)
                }
            }
            SkinButton(title: "Reset Progress", style: .danger, sound: .sheetOpen) { app.dialog = .resetConfirm }
                .mock(20, 600, 350, 60, h: .stretch)
        }
    }
}
