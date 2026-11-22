import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// The tab bar's selection. The "now" button selects its tab for a moment; it's then switched back,
    /// which a binding that refused the change wouldn't do: the tab bar would stay on that empty tab.
    @State private var selection = AppTab.space

    var body: some View {
        TabView(selection: Binding(get: { selection }, set: { next in
            if next == selection { reselect(next) }
            selection = next
        })) {
            Tab("Space", systemImage: "map", value: AppTab.space) {
                SpaceView()
            }
            Tab("Time", systemImage: "calendar", value: AppTab.time) {
                TimeTab()
            }
            // Not really a tab: picking it runs its action (see `tab` above). On the iPhone, the search
            // role sets it apart at the end of the tab bar.
            Tab(value: AppTab.now, role: nowTabRole) {
                Color.clear
            } label: {
                if model.tab == .time {
                    Label("Today", systemImage: "calendar.badge.clock")
                } else {
                    Label("Here", systemImage: "location.fill")
                }
            }
        }
        .onChange(of: selection) { previous, next in
            if next == .now {
                model.runNowAction()
                selection = previous
            } else if previous != .now {
                if next == .time { model.time.openFirstTime() }
                model.tab = next
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Events may have changed in Calendar while we were in the background, and access may
            // have changed in Settings.
            if phase == .active {
                model.calendar.checkPermissions()
                model.calendar.reloadCalendars()
            }
        }
        .task { await LegacyReminderMigration.run(space: model.space, calendar: model.calendar) }
    }

    /// The selected tab tapped again, after the tab bar has popped to its first screen. The tab bar
    /// then scrolls that screen to the top, which for the year view is ten years back, so the Time
    /// tab scrolls on to this year instead, as Today does.
    private func reselect(_ tab: AppTab) {
        if tab == .time && model.time.path.isEmpty { model.runNowAction() }
    }

    private var nowTabRole: TabRole? {
        #if os(iOS)
        .search
        #else
        nil
        #endif
    }
}
