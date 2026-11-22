import SwiftUI

extension View {
    /// The app's shared state, for views to read from the environment.
    func appEnvironment(_ model: AppModel) -> some View {
        environment(model)
            .environment(model.space)
            .environment(model.calendar)
            .environment(model.location)
            .environment(model.alarms)
    }
}

@main
struct SpacetimeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(model)
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
