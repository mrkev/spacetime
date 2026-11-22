import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        let tab = Binding<AppTab>(
            get: { model.tab },
            set: { next in
                if next == .now {
                    model.runNowAction()
                } else {
                    if next == .time { model.time.openFirstTime() }
                    model.tab = next
                }
            })
        TabView(selection: tab) {
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

    private var nowTabRole: TabRole? {
        #if os(iOS)
        .search
        #else
        nil
        #endif
    }
}
