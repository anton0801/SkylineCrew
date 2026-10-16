import SwiftUI
import UIKit

// MARK: - Palette (integration/design_tokens.json + values used in design/screens/*.svg)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

enum Palette {
    static let sky = Color(hex: 0x53C5F4)
    static let deepBlue = Color(hex: 0x103677)
    static let royalBlue = Color(hex: 0x165ACA)
    static let gold = Color(hex: 0xFFD437)
    static let amber = Color(hex: 0xEC9A19)
    static let cream = Color(hex: 0xFFF7E5)
    static let text = Color(hex: 0x12335B)
    static let secondary = Color(hex: 0x49657F)
    static let success = Color(hex: 0x22735A)
    static let warning = Color(hex: 0x895017)
    static let danger = Color(hex: 0xB94142)
    static let panel = Color(hex: 0xFFFCF3)
    static let panelShadow = Color(hex: 0xD5BC8D)
    static let dotOff = Color(hex: 0xB5C7CB)
    static let tileStroke = Color(hex: 0x1B5190)
    static let lockedFill = Color(hex: 0xDCE5DE)
    static let lockedStroke = Color(hex: 0xBCCBD0)
    static let starText = Color(hex: 0x7C5414)
    static let rope = Color(hex: 0x455B65)
    static let strainTrack = Color(hex: 0xDBD8C5)
    static let strainWarn = Color(hex: 0xB47518)
    static let white = Color.white
    static let overlay = Color(hex: 0x103677, opacity: 0.65)

    static let goldGradient = LinearGradient(stops: [
        .init(color: Color(hex: 0xFFE872), location: 0),
        .init(color: Color(hex: 0xFFD437), location: 0.48),
        .init(color: Color(hex: 0xF5B718), location: 1)
    ], startPoint: .top, endPoint: .bottom)

    /// Strain bar colour complements the number: calm / warning (≥60) / critical (≥85).
    static func strain(_ value: Int) -> Color {
        if value >= RunRules.strainCritical { return danger }
        if value >= RunRules.strainWarning { return strainWarn }
        return success
    }
}

// MARK: - Typography
//
// The approved screens are rendered with Arial (font-family="Arial, Helvetica, sans-serif");
// every weight 600–900 resolves to Arial Bold, which iOS ships as "Arial-BoldMT".
// Using the same face keeps the live UI 1:1 with design/screens/*.png.

enum Typo {
    static let faceName = "Arial-BoldMT"

    static func font(_ size: CGFloat) -> Font {
        Font.custom(faceName, fixedSize: size)
    }

    /// Scales with Dynamic Type (menus, help) while matching the mockup at the default size.
    static func scaled(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(faceName, size: size, relativeTo: style)
    }

    static func uiFont(_ size: CGFloat) -> UIFont {
        UIFont(name: faceName, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }
}

enum DesignRef {
    static let reference = CGSize(width: 390, height: 844)
    static let refSafeTop: CGFloat = 47
    static let refSafeBottom: CGFloat = 34
}
