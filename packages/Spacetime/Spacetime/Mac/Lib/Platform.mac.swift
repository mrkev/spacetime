#if os(macOS)
import SwiftUI

// What differs between the iPhone and the Mac app, so the rest of the code can mostly ignore it.
// The Mac app runs on macOS 15, so APIs new in macOS 26 (like Liquid Glass) need a fallback there.

import AppKit

typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
typealias PlatformEdgeInsets = NSEdgeInsets

extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}

extension Color {
    init(platformColor: PlatformColor) { self.init(nsColor: platformColor) }
}

let mapPressVerb = "Right-click"
let deviceNoun = "Mac"

/// Opens a URL in the app that handles it. Calls `completion` with whether it opened.
func openURL(_ url: URL, completion: ((Bool) -> Void)? = nil) {
    completion?(NSWorkspace.shared.open(url))
}

extension View {
    /// Liquid Glass where there is some (iOS 26, macOS 26), and a material before that.
    @ViewBuilder
    func glass(in shape: some Shape, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if let tint { shape.fill(tint) }
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            }
        }
    }

    /// The glass button style where there is one (iOS 26, macOS 26).
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26, macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// No fade or blur at a scroll view's edges (iOS 26, macOS 26), for one floating over the map.
    @ViewBuilder
    func scrollEdgeEffectsHidden() -> some View {
        if #available(iOS 26, macOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }

    /// Keeps the scroll view this is inside from scrolling to its top when the status bar is tapped,
    /// for a list that starts years back, whose top isn't somewhere to go. Apply it to the scroll
    /// view's content. (Tapping the selected tab scrolls to the top anyway; see `RootView.reselect`.)
    @ViewBuilder
    func noScrollToTop() -> some View {
        self
    }

    /// A small title in the navigation bar on iOS. The Mac has only the one kind.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        self
    }
}

extension View {
    /// A sheet sized for the Mac, where sheets otherwise shrink to their content's ideal size (and a
    /// list or form has next to none). On the iPhone, a plain sheet.
    func sizedSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item) { content($0).macSheetFrame() }
    }

    func sizedSheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content)
        -> some View {
        sheet(isPresented: isPresented) { content().macSheetFrame() }
    }

    @ViewBuilder
    fileprivate func macSheetFrame() -> some View {
        frame(minWidth: 460, idealWidth: 520, minHeight: 540, idealHeight: 680)
    }
}

extension ButtonRole {
    /// `.confirm` where there is one (iOS 26, macOS 26).
    static var confirmIfAvailable: ButtonRole? {
        if #available(iOS 26, macOS 26, *) { .confirm } else { nil }
    }

    /// `.close` where there is one (iOS 26, macOS 26).
    static var closeIfAvailable: ButtonRole? {
        if #available(iOS 26, macOS 26, *) { .close } else { .cancel }
    }
}

/// Glass shapes that sit close together blend, where there's Liquid Glass.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
#endif
