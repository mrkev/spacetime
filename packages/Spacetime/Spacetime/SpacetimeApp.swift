import SwiftUI

@main
struct SpacetimeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.space)
                .environment(model.calendar)
                .environment(model.location)
                .tint(Theme.tint)
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 560)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 780)
        #endif
    }
}
