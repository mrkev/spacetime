import SwiftUI

enum TimeRoute: Hashable {
    case month(Date)
    case day(Date)
    case reminders
    case alarms
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
    /// The alarm editor showing, if any; it's shown over the whole Time tab.
    var alarmEditor: AlarmEditRequest?

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

/// The Time tab's navigation stack.
///
/// Each screen pushed onto it gets the app's environment again. When a screen with a toolbar is pushed
/// after going back, UIKit asks the toolbar's buttons for their accessibility labels (as VoiceOver and
/// UI tests do), and SwiftUI updates the screen to answer without the environment it inherits, so
/// reading an `@Environment` object crashes. Seen on iOS 26.3.
struct TimeTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var nav = model.time
        NavigationStack(path: $nav.path) {
            YearView()
                .navigationDestination(for: TimeRoute.self) { route in
                    Group {
                        switch route {
                        case .month(let month): MonthView(route: route, initialMonth: month)
                        case .day(let day): DayView(route: route, initialDay: day)
                        case .reminders: RemindersView()
                        case .alarms: AlarmsView()
                        }
                    }
                    .appEnvironment(model)
                }
        }
        .sizedSheet(item: $nav.alarmEditor) { request in
            NavigationStack { AlarmEditorView(alarm: request.alarm, day: request.day) }
        }
    }
}

/// The toolbar buttons the calendar's levels share: Reminders, Alarms (where there are any), and the
/// "+" menu.
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
                if AlarmStore.isSupported {
                    Button("Alarms", systemImage: "alarm") {
                        model.time.path.append(.alarms)
                    }
                }
            }
            AddMenu(day: day, onNewReminder: onNewReminder) {
                model.time.alarmEditor = AlarmEditRequest(day: $0)
            }
        }
    }
}

/// The "+" menu: a new event, reminder, or alarm, on `day` if given.
struct AddMenu: View {
    var day: Date?
    var onNewReminder: (Date?) -> Void
    var onNewAlarm: (Date?) -> Void
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
            if AlarmStore.isSupported {
                Button("New Alarm", systemImage: "alarm") { onNewAlarm(day) }
            }
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
