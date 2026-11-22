import SwiftUI

enum TimeRoute: Hashable {
    case month(Date)
    case day(Date)
    case reminders
}

/// Which level of the calendar the Time tab was last left on.
enum TimeLevel: String {
    case year, month, day
}

/// The Time tab's navigation: the year view at the bottom, then the month view, then a day, like
/// Calendar, so back (or a swipe) goes up a level.
@Observable
final class TimeNavigation {
    private static let levelKey = "spacetime.time.level"

    var path: [TimeRoute] = []
    /// The year the month view is showing, which its back button shows.
    var monthViewYear = Calendar.current.component(.year, from: Date())
    /// The day the day view is showing, whose month its back button shows.
    var dayViewDate = Date()

    @ObservationIgnored private var opened = false

    /// Runs as the Time tab is first selected, to reopen it at the level it was left on (showing
    /// today, like Calendar).
    func openFirstTime() {
        guard !opened else { return }
        opened = true
        let today = Date()
        switch TimeLevel(rawValue: FileStorage.shared.string(forKey: Self.levelKey) ?? "") ?? .month {
        case .year: path = []
        case .month: path = [.month(Dates.startOfMonth(today))]
        case .day: path = [.month(Dates.startOfMonth(today)), .day(Dates.startOfDay(today))]
        }
    }

    /// Records `level` as where to reopen the Time tab.
    static func remember(_ level: TimeLevel) {
        FileStorage.shared.set(level.rawValue, forKey: levelKey)
    }

    func isTop(_ route: TimeRoute?) -> Bool {
        path.last == route
    }
}

struct TimeTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var nav = model.time
        NavigationStack(path: $nav.path) {
            YearView()
                .navigationDestination(for: TimeRoute.self) { route in
                    switch route {
                    case .month(let month): MonthView(route: route, initialMonth: month)
                    case .day(let day): DayView(route: route, initialDay: day)
                    case .reminders: RemindersView()
                    }
                }
        }
    }
}

/// The toolbar buttons the calendar's levels share: Reminders and the "+" menu.
struct TimeToolbar: ToolbarContent {
    var showsReminders = true
    var day: Date?
    var onNewReminder: (Date?) -> Void
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if showsReminders {
                Button("Reminders", systemImage: "checklist") {
                    model.time.path.append(.reminders)
                }
            }
            AddMenu(day: day, onNewReminder: onNewReminder)
        }
    }
}

/// The "+" menu: a new event or reminder, on `day` if given.
struct AddMenu: View {
    var day: Date?
    var onNewReminder: (Date?) -> Void
    @Environment(CalendarStore.self) private var calendar

    var body: some View {
        Menu("Add", systemImage: "plus") {
            Button("New Event", systemImage: "calendar.badge.plus") {
                Task {
                    await TimeActions.createEvent(start: day.map { TimeActions.defaultStart(on: $0) },
                                                  calendar: calendar)
                }
            }
            Button("New Reminder", systemImage: "checklist") { onNewReminder(day) }
        }
    }
}

/// Explains why the calendar is empty and offers to fix it.
struct AccessBanner: View {
    @Environment(CalendarStore.self) private var calendar

    var body: some View {
        if calendar.status == .undetermined || calendar.status == .denied {
            let denied = calendar.status == .denied
            VStack(alignment: .leading, spacing: 6) {
                Text("See your events and reminders").font(.subheadline.weight(.semibold))
                Text(denied
                     ? "Calendar access is turned off. Allow it in Settings to show your events here."
                     : "Spacetime reads the calendars and reminders already on your \(deviceNoun).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(denied ? "Open Settings" : "Allow Access") {
                    if denied { Presenter.openSettings() } else { Task { await calendar.requestAccess() } }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 12))
            .padding(12)
        }
    }
}

/// A new reminder, optionally on a day, for `.sizedSheet(item:)`.
struct NewReminderRequest: Identifiable {
    let id = UUID()
    var date: Date?
}
