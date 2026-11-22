#if os(macOS)
import SwiftUI
import AppKit

/// The system colors, so the app feels at home next to Calendar and Maps.
enum Theme {
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

    /// Alarms are orange, like Clock's.
    static let alarm = Color.orange
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
#endif
