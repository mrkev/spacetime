#if os(iOS)
import SwiftUI
import UIKit

/// The system colors, so the app feels at home next to Calendar and Maps.
enum Theme {
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

extension UIColor {
    convenience init(hex: String) {
        if let c = Hex.components(hex) {
            self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        } else {
            self.init(white: 0.5, alpha: 1)
        }
    }
}
#endif
