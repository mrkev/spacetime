import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The system colors, so the app feels at home next to Calendar and Maps.
enum Theme {
    #if os(iOS)
    static let tint = Color(uiColor: .systemRed)
    static let blue = Color(uiColor: .systemBlue)
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let fill = Color(uiColor: .systemGray5)
    static let secondaryText = Color(uiColor: .systemGray)
    static let tertiaryText = Color(uiColor: .systemGray3)
    static let separator = Color(uiColor: .separator)
    static let hourLine = Color(uiColor: .systemGray5)
    #else
    static let tint = Color(nsColor: .systemRed)
    static let blue = Color(nsColor: .systemBlue)
    static let background = Color(nsColor: .textBackgroundColor)
    static let groupedBackground = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let fill = Color(nsColor: .quaternarySystemFill)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let hourLine = Color(nsColor: .separatorColor)
    #endif

    /// Alarms are orange, like Clock's.
    static let alarm = Color.orange

    static let tintHex = "#FF3B30"
    static let blueHex = "#007AFF"
}

/// Colors collections can pick for their pins.
nonisolated let pinColors = [
    "#FF3B30", // red
    "#FF9500", // orange
    "#FFCC00", // yellow
    "#34C759", // green
    "#00C7BE", // mint
    "#30B0C7", // teal
    "#007AFF", // blue
    "#5856D6", // indigo
    "#AF52DE", // purple
    "#FF2D55", // pink
    "#A2845E", // brown
    "#8E8E93", // gray
]

nonisolated enum Hex {
    /// RGB components (0–1) of a `#RRGGBB` or `#RGB` color.
    static func components(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 8 {
            return (Double((value >> 24) & 0xFF) / 255, Double((value >> 16) & 0xFF) / 255,
                    Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
        }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255, 1)
    }

    static func string(from color: CGColor) -> String {
        let converted = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? color
        let c = converted.components ?? [0, 0, 0]
        let r = c.count >= 3 ? c[0] : c[0]
        let g = c.count >= 3 ? c[1] : c[0]
        let b = c.count >= 3 ? c[2] : c[0]
        func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

extension Color {
    init(hex: String) {
        if let c = Hex.components(hex) {
            self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
        } else {
            self = .gray
        }
    }
}

extension PlatformColor {
    convenience init(hex: String) {
        if let c = Hex.components(hex) {
            self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        } else {
            self.init(white: 0.5, alpha: 1)
        }
    }
}
