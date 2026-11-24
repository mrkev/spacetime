#if os(iOS)
import SwiftUI

/// The map and the calendar, one over the other. Both stay alive once shown, as tabs would, so the
/// map isn't rebuilt and the calendar keeps its place; each has its own button to switch to the other,
/// in place of a tab bar.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the calendar has been shown yet. It isn't built until it is.
    @State private var timeBuilt = false

    var body: some View {
        ZStack {
            surface(.space) {
                SpaceView(region: model.space.savedMapRegion())
            }
            if timeBuilt || model.tab == .time {
                surface(.time) { TimeTab() }
                    .onAppear { timeBuilt = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Events may have changed in Calendar while we were in the background, and access may
            // have changed in Settings.
            if phase == .active {
                model.calendar.checkPermissions()
                model.calendar.reloadCalendars()
                model.health.refresh()
            }
        }
        .sheet(isPresented: Binding(get: { model.showsSettings }, set: { model.showsSettings = $0 })) {
            NavigationStack { SettingsView() }.appEnvironment(model)
        }
        .task { await LegacyReminderMigration.run(space: model.space, calendar: model.calendar) }
    }

    /// `content`, shown while `tab` is selected, and otherwise kept but hidden.
    private func surface(_ tab: AppTab, @ViewBuilder content: () -> some View) -> some View {
        let shown = model.tab == tab
        return content()
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .zIndex(shown ? 1 : 0)
    }
}
#endif
