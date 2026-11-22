#if os(iOS)
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
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(model)
                .tint(Theme.tint)
        }
    }
}
#endif
