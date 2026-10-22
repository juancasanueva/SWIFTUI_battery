import AppKit
import SwiftUI

/// Colors, type and metrics of the panel, ported from Matchday: an opaque navy dark palette with a
/// legible light equivalent, tones derived from the foreground, and tabular digits everywhere.
enum Theme {
    // MARK: Colors

    static let background = adaptive(light: 0xF5F7FA, dark: 0x0D1724)
    static let foreground = adaptive(light: 0x1A2433, dark: 0xD9DFE8)
    /// Secondary text.
    static let dim = foreground.opacity(0.58)
    /// Hairlines and card borders.
    static let faint = foreground.opacity(0.14)
    /// Card fill.
    static let fill = foreground.opacity(0.04)
    static let hover = foreground.opacity(0.08)
    /// Low battery, failures.
    static let urgent = adaptive(light: 0xD93636, dark: 0xF0524F)
    /// Getting low.
    static let warning = adaptive(light: 0xD9801A, dark: 0xF0A040)
    /// Healthy battery.
    static let win = adaptive(light: 0x2E9E4F, dark: 0x3FBF5F)
    static let accent = Color.accentColor

    // MARK: Metrics

    static let cornerRadius: CGFloat = 8
    static let panelWidth: CGFloat = 340

    // MARK: Type

    /// System font (SF Pro) with tabular digits so percentages line up.
    static func font(_ size: Size, weight: Font.Weight = .regular) -> Font {
        .system(size: size.rawValue, weight: weight).monospacedDigit()
    }

    enum Size: CGFloat {
        case caption = 10.5
        case small = 11.5
        case body = 13
        case title = 14.5
        case heading = 17
        case display = 22
    }

    // MARK: Helpers

    /// A color that resolves per appearance.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}
