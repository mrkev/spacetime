import CoreGraphics
import Foundation

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
    /// The app's tint (system red), for pins and events with no color of their own.
    static let tint = "#FF3B30"
    /// System blue, the color of an event whose calendar is unknown.
    static let blue = "#007AFF"

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
