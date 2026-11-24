#if os(iOS)
import SwiftUI

/// The app's two surfaces, the map and the calendar. One shows at a time, and each has a button
/// that switches to the other.
enum AppTab: Hashable {
    case space, time
}

/// The app's shared state.
@Observable
final class AppModel {
    let space: SpaceStore
    let calendar: CalendarStore
    let location = LocationModel()
    let alarms = AlarmStore.shared
    let health: HealthStore
    let layers: MapLayers
    let time: TimeNavigation

    var tab: AppTab = .space
    var showsSettings = false
    /// Bumped by the Here and Today buttons, for the screen showing to act on.
    private(set) var hereRequests = 0
    private(set) var todayRequests = 0

    init(storage: FileStorage = .shared) {
        ExpoStorageImport.runIfNeeded(into: storage)
        space = SpaceStore(storage: storage)
        calendar = CalendarStore(meta: ReminderMetaStore(storage: storage))
        health = HealthStore(storage: storage)
        layers = MapLayers(storage: storage)
        layers.load()
        time = TimeNavigation(storage: storage)
    }

    /// Switches to the other surface. The calendar opens where it was left the first time it shows.
    func switchTab() {
        let next: AppTab = tab == .space ? .time : .space
        if next == .time { time.openFirstTime() }
        withAnimation(.smooth(duration: 0.25)) { tab = next }
    }

    /// Centers the map on where you are.
    func goHere() { hereRequests += 1 }

    /// Scrolls the calendar to today.
    func goToToday() { todayRequests += 1 }
}
#endif
