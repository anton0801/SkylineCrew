import SwiftUI

struct DialogAction {
    var title: String
    var style: SkinStyle
    var sound: SoundCue? = .tap
    var hold: Bool = false
    var enabled: Bool = true
    var action: () -> Void
}

/// Shared layout of 15, 16, 25b, 33, 34, 36, 41: city background, decorative tower,
/// 65 % deep-blue scrim, foreman, cream panel with title, reason and up to three actions.
struct DialogScreen: View {
    var background = "BG01"
    var character = "C01"
    var towerFloors: [String] = ["F06", "F05", "F04", "F03"]
    let title: String
    let lines: [String]
    let actions: [DialogAction]
    @Environment(\.mockMetrics) private var m

    var body: some View {
        MockCanvas {
            BackgroundArt(id: background)
            MockBand(from: 400, to: 735, align: 1) {
                TowerView(spec: .dialog, floors: towerFloors.map { TowerFloor(asset: $0) })
            }
            Palette.overlay
                .frame(width: m.size.width, height: m.size.height)
                .accessibilityHidden(true)
            MockBand(from: 140, to: 670, expandToSafeArea: true) {
                ArtView(character, .fit).placed(144, 147, 103, 143).accessibilityHidden(true)
                CreamCard(radius: 24).placed(20, 296, 350, 365)
                Text(title).mockStyle(23).accessibilityAddTraits(.isHeader).placedText(195, 337, .middle)
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    Text(line).mockStyle(17, Palette.secondary).placedText(195, 373 + 25 * CGFloat(i), .middle)
                }
                ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                    Group {
                        if a.hold {
                            HoldButton(title: a.title, style: a.style, action: a.action)
                        } else {
                            SkinButton(title: a.title, style: a.style, enabled: a.enabled, sound: a.sound, action: a.action)
                        }
                    }
                    .placed(38, 468 + 64 * CGFloat(i), 314, 60)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Hold for 1.5 s to confirm (Clear Progress). VoiceOver gets a separate confirmable action.
struct HoldButton: View {
    let title: String
    var style: SkinStyle = .danger
    var duration: Double = 1.5
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var done = false
    @Environment(\.uiSound) private var uiSound

    var body: some View {
        GeometryReader { proxy in
            UIAsset(holding ? "button_\(style.rawValue)_pressed" : "button_\(style.rawValue)_normal")
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(Color.white.opacity(0.28))
                        .frame(width: max(0, (proxy.size.width - 4) * progress), height: 52)
                        .offset(x: 2, y: holding ? 4 : 1)
                }
                .overlay(alignment: .top) {
                    Text(title)
                        .font(Typo.font(19))
                        .foregroundColor(style.textColor)
                        .alignmentGuide(.top) { d in d[.firstTextBaseline] }
                        .offset(y: 36 + (holding ? 3 : 0))
                }
            .scaleEffect(holding ? 0.97 : 1)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 40, pressing: { pressing in
                guard !done else { return }
                holding = pressing
                if pressing {
                    uiSound(.tap)
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }, perform: {
                guard !done else { return }
                done = true
                holding = false
                action()
            })
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("Hold for one and a half seconds")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Clear Progress") { action() }
    }
}
