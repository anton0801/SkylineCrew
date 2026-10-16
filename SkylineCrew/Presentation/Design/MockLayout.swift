import SwiftUI

// Every screen is authored in the 390×844 pt reference space of design/screens/*.svg
// (safe area 47 top / 34 bottom). Elements are pinned to the real safe area so the
// iPhone 12–16 class renders the mockup 1:1, while smaller phones shrink the
// illustration bands (never the text) and scroll lists.

struct MockMetrics: Equatable {
    var size: CGSize
    var safeTop: CGFloat
    var safeBottom: CGFloat

    static let reference = MockMetrics(size: DesignRef.reference, safeTop: DesignRef.refSafeTop, safeBottom: DesignRef.refSafeBottom)

    var topShift: CGFloat { safeTop - DesignRef.refSafeTop }
    var bottomShift: CGFloat { (size.height - safeBottom) - (DesignRef.reference.height - DesignRef.refSafeBottom) }
    var widthDelta: CGFloat { size.width - DesignRef.reference.width }

    func y(_ y: CGFloat, _ pin: VPin) -> CGFloat {
        switch pin {
        case .top: return y + topShift
        case .bottom: return y + bottomShift
        case .raw: return y
        }
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ v: VPin, _ hp: HPin) -> CGRect {
        var X = x, W = w
        switch hp {
        case .leading, .raw: break
        case .center: X = x + widthDelta / 2
        case .trailing: X = x + widthDelta
        case .stretch: W = w + widthDelta
        }
        return CGRect(x: X, y: self.y(y, v), width: W, height: h)
    }

    func x(_ x: CGFloat, _ hp: HPin) -> CGFloat {
        switch hp {
        case .leading, .raw, .stretch: return x
        case .center: return x + widthDelta / 2
        case .trailing: return x + widthDelta
        }
    }
}

enum VPin { case top, bottom, raw }
enum HPin { case leading, center, trailing, stretch, raw }
enum TextAnchor { case start, middle, end }

private struct MockMetricsKey: EnvironmentKey {
    static let defaultValue = MockMetrics.reference
}

extension EnvironmentValues {
    var mockMetrics: MockMetrics {
        get { self[MockMetricsKey.self] }
        set { self[MockMetricsKey.self] = newValue }
    }
}

// MARK: - Raw placement (absolute design coordinates inside a canvas)

extension View {
    /// Places the view as an SVG `<rect x y width height>` would, without affecting layout of siblings.
    /// The element is centred with `.position` inside the parent canvas, so its hit area always lies
    /// within its ancestors' bounds (required for buttons inside ScrollView).
    func placed(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        self.frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
    }

    /// Places text like SVG `<text x y text-anchor>`: `y` is the baseline.
    func placedText(_ x: CGFloat, _ baseline: CGFloat, _ anchor: TextAnchor) -> some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                self.fixedSize()
                    .alignmentGuide(.leading) { d in
                        switch anchor {
                        case .start: return 0
                        case .middle: return d.width / 2
                        case .end: return d.width
                        }
                    }
                    .alignmentGuide(.top) { d in d[.firstTextBaseline] }
                    .offset(x: x, y: baseline)
            }
    }

    func mock(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, v: VPin = .top, h hp: HPin = .center) -> some View {
        modifier(MockBox(x: x, y: y, w: w, h: h, v: v, hp: hp))
    }

    func mockText(_ x: CGFloat, _ baseline: CGFloat, _ anchor: TextAnchor, v: VPin = .top, h hp: HPin? = nil) -> some View {
        modifier(MockTextBox(x: x, baseline: baseline, anchor: anchor, v: v, hp: hp ?? Self.defaultPin(for: anchor)))
    }

    static func defaultPin(for anchor: TextAnchor) -> HPin {
        switch anchor {
        case .start: return .leading
        case .middle: return .center
        case .end: return .trailing
        }
    }
}

private struct MockBox: ViewModifier {
    let x, y, w, h: CGFloat
    let v: VPin
    let hp: HPin
    @Environment(\.mockMetrics) private var m

    func body(content: Content) -> some View {
        let r = m.rect(x, y, w, h, v, hp)
        return content.placed(r.minX, r.minY, r.width, r.height)
    }
}

private struct MockTextBox: ViewModifier {
    let x, baseline: CGFloat
    let anchor: TextAnchor
    let v: VPin
    let hp: HPin
    @Environment(\.mockMetrics) private var m

    func body(content: Content) -> some View {
        content.placedText(m.x(x, hp), m.y(baseline, v), anchor)
    }
}

// MARK: - Canvas

/// Full-screen absolute canvas. Children use `.mock(...)` / `.mockText(...)`.
struct MockCanvas<Content: View>: View {
    @Environment(\.mockMetrics) private var m
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: m.size.width, height: m.size.height)
            content()
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }
}

/// A design-space region [from, to] (mockup y) whose content keeps the mockup composition.
/// It is placed between the top-pinned and bottom-pinned UI and scaled down uniformly
/// when the device has less room (iPhone SE), centred when it has more.
struct MockBand<Content: View>: View {
    let from: CGFloat
    let to: CGFloat
    var align: CGFloat = 0.5
    /// Free-standing compositions (dialogs) may use the whole safe area before shrinking.
    var expandToSafeArea = false
    /// Small overflows (≤ tolerance) keep scale 1 and borrow the band margins.
    var tolerance: CGFloat = 16
    @Environment(\.mockMetrics) private var m
    @ViewBuilder var content: () -> Content

    var body: some View {
        let design = to - from
        var top = from + m.topShift
        var bottom = to + m.bottomShift
        if expandToSafeArea, bottom - top < design {
            let center = (top + bottom) / 2
            let limitTop = m.safeTop + 4
            let limitBottom = m.size.height - max(m.safeBottom, 8)
            top = max(limitTop, min(center - design / 2, limitBottom - design))
            bottom = min(limitBottom, top + design)
        }
        let avail = max(1, bottom - top)
        let fitsWithTolerance = avail >= design - tolerance
        let s = min(fitsWithTolerance ? 1 : avail / design, m.size.width / DesignRef.reference.width)
        let extra = avail - design * s
        return ZStack(alignment: .topLeading) {
            // Content keeps absolute mockup coordinates inside a full-height canvas, then slides up by `from`.
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: DesignRef.reference.width, height: to)
                content()
            }
            .frame(width: DesignRef.reference.width, height: to, alignment: .topLeading)
            .offset(y: -from)
        }
        .frame(width: DesignRef.reference.width, height: design, alignment: .topLeading)
        .scaleEffect(s, anchor: .center)
        .position(x: m.size.width / 2, y: top + extra * align + design * s / 2)
    }
}

/// A scrollable design-space region for lists. Content uses absolute mockup coordinates;
/// it scrolls only when the device band is shorter than the content.
struct MockScrollBand<Content: View>: View {
    let from: CGFloat
    let to: CGFloat
    let contentBottom: CGFloat
    var bottomPin: VPin = .bottom
    @Environment(\.mockMetrics) private var m
    @ViewBuilder var content: () -> Content

    var body: some View {
        let top = from + m.topShift
        let bottom = m.y(to, bottomPin)
        let height = max(1, bottom - top)
        let contentHeight = contentBottom - from
        let inner = ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: m.size.width, height: contentBottom)
                content()
                    .environment(\.mockMetrics, MockMetrics(size: CGSize(width: m.size.width, height: DesignRef.reference.height),
                                                            safeTop: DesignRef.refSafeTop, safeBottom: DesignRef.refSafeBottom))
            }
            .frame(width: m.size.width, height: contentBottom, alignment: .topLeading)
            .offset(y: -from)
        }
        .frame(width: m.size.width, height: contentHeight, alignment: .topLeading)

        return Group {
            if contentHeight <= height + 0.5 {
                inner
            } else {
                ScrollView(.vertical, showsIndicators: true) { inner }
            }
        }
        .frame(width: m.size.width, height: height, alignment: .top)
        .clipped()
        .placed(0, top, m.size.width, height)
    }
}

/// Reads the real screen size and safe area once at the root.
struct MetricsReader<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let metrics = MockMetrics(size: CGSize(width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                                                   height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom),
                                      safeTop: proxy.safeAreaInsets.top,
                                      safeBottom: proxy.safeAreaInsets.bottom)
            content()
                .environment(\.mockMetrics, metrics)
                .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
                .ignoresSafeArea()
        }
    }
}
