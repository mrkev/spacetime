import SwiftUI

#if os(iOS)
import UIKit

/// The iPhone app is portrait, except while a screen that also works on its side (the day view) is
/// showing. The Info.plist lists landscape so this can allow it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.landscapeAllowed ? .allButUpsideDown : .portrait
    }
}

enum Orientation {
    fileprivate(set) static var landscapeAllowed = false

    /// Allows turning to landscape, or turns back to portrait.
    static func allowLandscape(_ allowed: Bool) {
        guard allowed != landscapeAllowed else { return }
        landscapeAllowed = allowed
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if !allowed { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
        }
    }
}
#endif

extension View {
    /// Lets the iPhone turn to landscape while `allowed` and this view is showing.
    func allowsLandscape(_ allowed: Bool) -> some View {
        #if os(iOS)
        onChange(of: allowed, initial: true) { _, allowed in Orientation.allowLandscape(allowed) }
            .onDisappear { Orientation.allowLandscape(false) }
        #else
        self
        #endif
    }

    /// Hides the navigation and tab bars, for a screen that takes up all of a sideways phone.
    @ViewBuilder
    func barsHidden(_ hidden: Bool) -> some View {
        #if os(iOS)
        toolbar(hidden ? .hidden : .automatic, for: .navigationBar, .tabBar)
        #else
        self
        #endif
    }
}
