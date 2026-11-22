import SwiftUI

enum AppTab: Hashable {
    case space, time
    /// The floating button at the trailing end of the tab bar ("Here" on Space, "Today" on Time). It
    /// never stays selected; pressing it runs the current tab's action.
    case now
}

/// The app's shared state.
@Observable
final class AppModel {
    let space: SpaceStore
    let calendar: CalendarStore
    let location = LocationModel()
    let alarms = AlarmStore.shared
    let time = TimeNavigation()

    var tab: AppTab = .space
    /// Bumped by the floating button on each tab, for the screen showing to act on.
    private(set) var hereRequests = 0
    private(set) var todayRequests = 0

    init(storage: FileStorage = .shared) {
        ExpoStorageImport.runIfNeeded(into: storage)
        space = SpaceStore(storage: storage)
        calendar = CalendarStore(meta: ReminderMetaStore(storage: storage))
    }

    func runNowAction() {
        switch tab {
        case .space: hereRequests += 1
        case .time: todayRequests += 1
        case .now: break
        }
    }
}
