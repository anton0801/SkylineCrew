import SwiftUI
import CoreText

// MARK: - Environment: UI sound hook

private struct UISoundKey: EnvironmentKey {
    static let defaultValue: (SoundCue) -> Void = { _ in }
}

extension EnvironmentValues {
    var uiSound: (SoundCue) -> Void {
        get { self[UISoundKey.self] }
        set { self[UISoundKey.self] = newValue }
    }
}

// MARK: - Art

enum ArtMode { case stretch, fit, fill }

/// Renders a production PNG from the catalog by its manifest ID (alpha-bounds crop, never redrawn).
struct ArtView: View {
    let id: String
    var mode: ArtMode = .stretch

    init(_ id: String, _ mode: ArtMode = .stretch) {
        self.id = id
        self.mode = mode
    }

    var body: some View {
        switch mode {
        case .fill:
            Image(uiImage: ArtCache.shared.full(id)).resizable().aspectRatio(contentMode: .fill).accessibilityHidden(true)
        case .fit:
            Image(uiImage: ArtCache.shared.image(id)).resizable().aspectRatio(contentMode: .fit).accessibilityHidden(true)
        case .stretch:
            Image(uiImage: ArtCache.shared.image(id)).resizable().accessibilityHidden(true)
        }
    }
}

/// One VoiceOver element exactly over a composed group whose own layers stay hidden.
struct AXLabel: View {
    let label: String
    var traits: AccessibilityTraits = .isStaticText

    var body: some View {
        Color.clear
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(traits)
            .allowsHitTesting(false)
    }
}

/// Full-bleed screen background (aspectFill, centered — SVG `xMidYMid slice`).
struct BackgroundArt: View {
    let id: String
    @Environment(\.mockMetrics) private var m

    var body: some View {
        ArtView(id, .fill)
            .frame(width: m.size.width, height: m.size.height)
            .clipped()
            .accessibilityHidden(true)
    }
}

/// UI component PNG from assets/ui (stretched like the SVG `preserveAspectRatio="none"`).
struct UIAsset: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        Image(name).resizable().accessibilityHidden(true)
    }
}

// MARK: - Text helpers

extension Text {
    func mockStyle(_ size: CGFloat, _ color: Color = Palette.text) -> some View {
        self.font(Typo.font(size)).foregroundColor(color)
    }
}

/// Converts a string to glyph outlines (baseline at y = 0, y pointing down).
enum GlyphPath {
    static func path(_ string: String, font: UIFont) -> CGPath {
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let attributed = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): ctFont])
        let line = CTLineCreateWithAttributedString(attributed)
        let result = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) else { continue }
                var t = CGAffineTransform(translationX: positions[i].x, y: 0).scaledBy(x: 1, y: -1)
                if let moved = glyph.copy(using: &t) { result.addPath(moved) }
            }
        }
        return result
    }
}

/// “SKYLINE / CREW” wordmark exactly as in the SVG group (Arial 900, 6 pt #103677 stroke, paint-order stroke).
struct LogoView: View {
    var scale: CGFloat = 1

    private static let skyline: CGPath = {
        var t = CGAffineTransform(translationX: 0, y: 22)
        return GlyphPath.path("SKYLINE", font: Typo.uiFont(32)).copy(using: &t)!
    }()
    private static let crew: CGPath = {
        var t = CGAffineTransform(translationX: 18, y: 53)
        return GlyphPath.path("CREW", font: Typo.uiFont(34)).copy(using: &t)!
    }()

    var body: some View {
        let stroke = StrokeStyle(lineWidth: 6, lineCap: .butt, lineJoin: .miter, miterLimit: 4)
        ZStack(alignment: .topLeading) {
            Path(Self.skyline).stroke(Palette.deepBlue, style: stroke)
            Path(Self.skyline).fill(Color.white)
            Path(Self.crew).stroke(Palette.deepBlue, style: stroke)
            Path(Self.crew).fill(Palette.gold)
        }
        .frame(width: 220, height: 64, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 220 * scale, height: 64 * scale, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel("Skyline Crew")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Panels

/// Cream card with the 3 pt sand shadow rect used throughout the SVGs.
struct CreamCard: View {
    var radius: CGFloat = 24
    var shadow = true
    var fill: Color = Palette.cream

    var body: some View {
        ZStack(alignment: .topLeading) {
            if shadow {
                RoundedRectangle(cornerRadius: radius, style: .circular).fill(Palette.panelShadow).offset(y: 3)
            }
            RoundedRectangle(cornerRadius: radius, style: .circular).fill(fill)
        }
    }
}

// MARK: - Buttons

enum SkinStyle: String {
    case primary, secondary, quiet, danger

    var textColor: Color {
        switch self {
        case .primary, .quiet: return Palette.text
        case .secondary, .danger: return .white
        }
    }
}

struct SkinButtonStyle: ButtonStyle {
    let title: String
    let style: SkinStyle
    let enabled: Bool
    var titleSize: CGFloat = 19
    var baseline: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        let image = enabled ? (pressed ? "button_\(style.rawValue)_pressed" : "button_\(style.rawValue)_normal")
                            : "button_\(style.rawValue)_disabled"
        return UIAsset(image)
            .overlay(alignment: .top) {
                Text(title)
                    .font(Typo.font(titleSize))
                    .foregroundColor(enabled ? style.textColor : Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .alignmentGuide(.top) { d in d[.firstTextBaseline] }
                    .offset(y: baseline + (pressed ? 3 : 0))
            }
            .contentShape(Rectangle())
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

struct SkinButton: View {
    let title: String
    var style: SkinStyle = .primary
    var enabled = true
    var sound: SoundCue? = .tap
    var accessibilityHint: String?
    let action: () -> Void
    @Environment(\.uiSound) private var uiSound

    var body: some View {
        Button {
            if let sound { uiSound(sound) }
            action()
        } label: { EmptyView() }
        .buttonStyle(SkinButtonStyle(title: title, style: style, enabled: enabled))
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

/// 44×44 pt icon control (hit area never smaller than the visible stroke).
struct IconButton: View {
    let icon: String
    var label: String
    var sound: SoundCue? = .tap
    let action: () -> Void
    @Environment(\.uiSound) private var uiSound

    var body: some View {
        Button {
            if let sound { uiSound(sound) }
            action()
        } label: {
            UIAsset(icon).contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Invisible tappable area (whole cards / rows).
struct TapArea: View {
    var label: String
    var hint: String = ""
    var sound: SoundCue? = .tap
    let action: () -> Void
    @Environment(\.uiSound) private var uiSound

    var body: some View {
        Button {
            if let sound { uiSound(sound) }
            action()
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

// MARK: - Small widgets

struct ToggleSkin: View {
    let isOn: Bool
    var body: some View {
        UIAsset(isOn ? "toggle_on" : "toggle_off")
    }
}

// MARK: - Towers made from production sprites

/// Geometry of a decorative tower as authored in a mockup:
/// base rect, lowest floor rect, vertical step between floors, roof 55 pt high sitting 50 pt above the top floor.
struct TowerSpec {
    var base: CGRect
    var floorX: CGFloat
    var floorY: CGFloat
    var floorW: CGFloat
    var floorH: CGFloat
    var step: CGFloat
    var roofH: CGFloat = 55
    var roofLift: CGFloat = 50
    var roofFit = false

    static let home = TowerSpec(base: CGRect(x: 66, y: 622, width: 258, height: 54), floorX: 101, floorY: 564, floorW: 188, floorH: 70, step: 64)
    static let brief = TowerSpec(base: CGRect(x: 40, y: 469, width: 243, height: 54), floorX: 75, floorY: 421, floorW: 173, floorH: 60, step: 54)
    static let dialog = TowerSpec(base: CGRect(x: 85, y: 674, width: 230, height: 54), floorX: 120, floorY: 626, floorW: 160, floorH: 60, step: 54)
    static let showcase = TowerSpec(base: CGRect(x: 81, y: 652, width: 230, height: 54), floorX: 116, floorY: 604, floorW: 160, floorH: 60, step: 54)
    static let result = TowerSpec(base: CGRect(x: 76, y: 584, width: 238, height: 54), floorX: 111, floorY: 550, floorW: 168, floorH: 46, step: 40)
    static let cityComplete = TowerSpec(base: CGRect(x: 76, y: 584, width: 238, height: 54), floorX: 111, floorY: 538, floorW: 168, floorH: 58, step: 52)

    static func collectionTile(originX: CGFloat, originY: CGFloat) -> TowerSpec {
        // Tile 1 in 26_tower_collection: card (20,166); base (23,362); floors x 58, first 334, step 34, 93×40.
        TowerSpec(base: CGRect(x: originX + 3, y: originY + 196, width: 163, height: 54),
                  floorX: originX + 38, floorY: originY + 168, floorW: 93, floorH: 40, step: 34, roofFit: true)
    }
}

struct TowerFloor: Equatable {
    var asset: String
    /// Horizontal offset in points at the spec's floor scale.
    var offset: CGFloat = 0
}

/// Decorative/saved tower built only from P02, F01–F06 and P03.
/// `fitTop` enables fit-to-height: the tower scales around the base when it would rise above that line.
struct TowerView: View {
    let spec: TowerSpec
    let floors: [TowerFloor]
    var roof = true
    var fitTop: CGFloat?
    var hideBase = false

    private var naturalTop: CGFloat {
        let topFloorY = spec.floorY - spec.step * CGFloat(max(0, floors.count - 1))
        return roof ? topFloorY - spec.roofLift : topFloorY
    }

    /// Fit-to-height: the floors and roof shrink above the plaza (the plaza itself keeps its size).
    var scale: CGFloat {
        guard let fitTop, naturalTop < fitTop else { return 1 }
        let pivot = spec.floorY + spec.floorH
        return max(0.2, (pivot - fitTop) / (pivot - naturalTop))
    }

    var body: some View {
        let s = scale
        let pivotX = spec.floorX + spec.floorW / 2
        let pivotY = spec.floorY + spec.floorH
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: DesignRef.reference.width, height: DesignRef.reference.height)
            if !hideBase {
                ArtView("P02", .fit).placed(spec.base.minX, spec.base.minY, spec.base.width, spec.base.height)
            }
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: DesignRef.reference.width, height: DesignRef.reference.height)
                ForEach(Array(floors.enumerated()), id: \.offset) { i, f in
                    ArtView(f.asset, .stretch)
                        .placed(spec.floorX + f.offset, spec.floorY - spec.step * CGFloat(i), spec.floorW, spec.floorH)
                }
                if roof {
                    let topOffset = floors.last?.offset ?? 0
                    let topY = spec.floorY - spec.step * CGFloat(max(0, floors.count - 1))
                    ArtView("P03", spec.roofFit ? .fit : .stretch)
                        .placed(spec.floorX + topOffset, topY - spec.roofLift, spec.floorW, spec.roofH)
                }
            }
            .frame(width: DesignRef.reference.width, height: DesignRef.reference.height, alignment: .topLeading)
            .scaleEffect(s, anchor: UnitPoint(x: pivotX / DesignRef.reference.width, y: pivotY / DesignRef.reference.height))
        }
        .frame(width: DesignRef.reference.width, height: DesignRef.reference.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

extension Array where Element == Placement {
    /// Saved placements → facade list with offsets in points for the given floor width.
    func towerFloors(floorWidth: CGFloat) -> [TowerFloor] {
        map { TowerFloor(asset: $0.assetID, offset: CGFloat($0.centerX) * floorWidth / 180) }
    }
}

// MARK: - Common header (back + title + subtitle)

struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?
    var titleSize: CGFloat = 27

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let onBack {
                IconButton(icon: "icon_back", label: "Back", sound: .back, action: onBack)
                    .mock(16, 58, 44, 44, h: .leading)
            }
            Text(title).mockStyle(titleSize).lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
                .mockText(70, 89, .start)
            if let subtitle {
                Text(subtitle).mockStyle(16, Palette.secondary).mockText(22, 128, .start)
            }
        }
    }
}

struct BoltsChip: View {
    let amount: Int
    var compact = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if compact {
                RoundedRectangle(cornerRadius: 12).fill(Palette.cream).mock(276, 133, 92, 36, h: .trailing)
                UIAsset("icon_bolt").mock(281, 137, 28, 28, h: .trailing)
                Text("\(amount)").mockStyle(17).accessibilityHidden(true).mockText(357, 158, .end)
                AXLabel(label: "\(amount) Bolts").mock(276, 133, 92, 36, h: .trailing)
            } else {
                RoundedRectangle(cornerRadius: 15).fill(Palette.cream).mock(271, 62, 97, 43, h: .trailing)
                UIAsset("icon_bolt").mock(278, 70, 28, 28, h: .trailing)
                Text("\(amount)").mockStyle(20).accessibilityHidden(true).mockText(355, 91, .end)
                AXLabel(label: "\(amount) Bolts").mock(271, 62, 97, 43, h: .trailing)
            }
        }
    }
}

struct StrainBar: View {
    let value: Int
    var maxValue: Int = 100

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                UIAsset("strain_track")
                RoundedRectangle(cornerRadius: proxy.size.height / 2)
                    .fill(Palette.strain(value))
                    .frame(width: proxy.size.width * CGFloat(min(max(value, 0), maxValue)) / CGFloat(maxValue))
            }
        }
        .accessibilityHidden(true)
    }
}
