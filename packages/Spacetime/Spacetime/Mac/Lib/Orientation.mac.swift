#if os(macOS)
import SwiftUI

extension View {
    /// Lets the iPhone turn to landscape while `allowed` and this view is showing.
    func allowsLandscape(_ allowed: Bool) -> some View {
        self
    }

    /// Hides the navigation and tab bars, for a screen that takes up all of a sideways phone.
    @ViewBuilder
    func barsHidden(_ hidden: Bool) -> some View {
        self
    }
}
#endif
