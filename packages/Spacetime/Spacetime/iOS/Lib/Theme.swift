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
    /// Health's colors for sleep, cycle tracking, and medications.
    static let sleep = Color(uiColor: .systemIndigo)
    static let cycle = Color(uiColor: .systemPink)
    static let medication = Color(uiColor: .systemTeal)

    /// An event's fill, in its calendar's color, as strong as Calendar's.
    static func eventFill(_ hex: String) -> Color {
        Color(hex: hex).opacity(0.28)
    }

    /// An event's text, in its calendar's color like Calendar's: the color itself in dark mode, and
    /// darker in light mode, to read on its fill.
    static func eventText(_ hex: String) -> Color {
        let color = UIColor(hex: hex)
        return Color(uiColor: UIColor { traits in
            guard traits.userInterfaceStyle != .dark else { return color }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r * 0.55, green: g * 0.55, blue: b * 0.55, alpha: a)
        })
    }
}

extension View {
    /// Outlines a timeline block drawn over another in the background's color, so the two stay apart.
    func stacked(_ stacked: Bool) -> some View {
        background {
            if stacked { RoundedRectangle(cornerRadius: 5).fill(Theme.background).padding(-1) }
        }
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
