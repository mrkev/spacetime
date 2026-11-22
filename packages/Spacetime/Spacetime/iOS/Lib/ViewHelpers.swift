#if os(iOS)
import SwiftUI
import UIKit

extension View {
    /// Liquid Glass in `shape`, optionally tinted, and reacting to touch if `interactive`.
    func glass(in shape: some Shape, interactive: Bool = false, tint: Color? = nil) -> some View {
        glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
    }

    /// Keeps the scroll view this is inside from scrolling to its top when the status bar is tapped,
    /// for a list that starts years back, whose top isn't somewhere to go. Apply it to the scroll
    /// view's content. (Tapping the selected tab scrolls to the top anyway; see `RootView.reselect`.)
    func noScrollToTop() -> some View {
        background(NoScrollToTop())
    }
}

/// Turns off `scrollsToTop` on the scroll view it's in, once it's in a window.
private struct NoScrollToTop: UIViewRepresentable {
    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            (view as? UIScrollView)?.scrollsToTop = false
        }
    }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ uiView: Probe, context: Context) {}
}
#endif
