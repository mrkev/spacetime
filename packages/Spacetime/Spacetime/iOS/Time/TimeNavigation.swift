#if os(iOS)
import SwiftUI

/// The screens pushed over the calendar.
enum TimeRoute: Hashable {
    case reminders
    case alarms
}

/// The calendar's levels: a year of tiny months, a scrolling list of months, and a day.
enum TimeLevel: String {
    case year, month, day
}

/// The coordinate space each level of the calendar is measured in: the Time tab's, before a
/// transition scales or moves the level.
let timeLevelSpace = "timeLevel"

/// A change between levels, animated like Calendar's: the month view zooms into its month in the
/// year view, and splits open at a week, which becomes the day view's week strip.
struct TimeTransition: Equatable {
    let id = UUID()
    let from: TimeLevel
    let to: TimeLevel
    /// The month zoomed between the year and month views.
    let month: Date
    /// The day whose week the month view splits at, between the month and day views.
    let day: Date
    /// From 0, with only `from` showing, to 1, with only `to`.
    var progress: CGFloat = 0

    /// Whether this is between the year and month views, rather than the month and day views.
    var isZoom: Bool { from != .day && to != .day }

    /// How far `level` is from showing: 0 when it's all that shows, and 1 when it's gone.
    func hiddenness(of level: TimeLevel) -> CGFloat? {
        if level == to { return 1 - progress }
        if level == from { return progress }
        return nil
    }
}

/// How a level is scaled, moved, and faded in a zoom between the year and month views.
struct LevelZoom {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var opacity: Double = 1
}

/// How the month view's weeks move apart in a change to or from the day view: the week becoming the
/// day view's strip, and those above it, move by `up`, and the weeks below it by `down`. All but
/// that week fade to `opacity`.
struct MonthSplit {
    var day: Date
    var up: CGFloat
    var down: CGFloat
    var opacity: Double
}

/// The Time tab's navigation: which level of the calendar shows, the changes between them, and the
/// Reminders and Alarms screens pushed over it.
@Observable
final class TimeNavigation {
    private static let levelKey = "spacetime.time.level"
    private static let zoomKey = "spacetime.time.hourHeight"
    private static let sidewaysZoomKey = "spacetime.time.hourWidth"
    private static let animation = Animation.smooth(duration: 0.4)

    /// Reminders and Alarms, over the calendar.
    var path: [TimeRoute] = []
    /// The level showing, or being changed to.
    private(set) var level = TimeLevel.year
    /// The level the navigation bar shows the buttons of. It changes as a transition starts, in its
    /// animation, so the bar's buttons change with it.
    private(set) var barLevel = TimeLevel.year
    private(set) var transition: TimeTransition?
    /// Where the transition's month or week is in each level, in `timeLevelSpace`: the month's grid
    /// of days in the year and month views, or the week in the month view and the day view's strip.
    private(set) var anchors: [TimeLevel: CGRect] = [:]
    /// The month at the top of the month view, or that it opens at.
    var month = Dates.startOfMonth(Date())
    /// The day the day view is showing, or opens at.
    var day = Dates.startOfDay(Date())
    /// The alarm editor showing, if any; it's shown over the whole Time tab.
    var alarmEditor: AlarmEditRequest?

    @ObservationIgnored private var opened = false
    @ObservationIgnored private let storage: KeyValueStorage

    init(storage: KeyValueStorage) {
        self.storage = storage
    }

    /// Runs as the Time tab is first selected, to reopen it at the level it was left on (showing
    /// today, like Calendar).
    func openFirstTime() {
        guard !opened else { return }
        opened = true
        let today = Date()
        month = Dates.startOfMonth(today)
        day = Dates.startOfDay(today)
        level = TimeLevel(rawValue: storage.string(forKey: Self.levelKey) ?? "") ?? .month
        barLevel = level
    }

    /// Records `level` as where to reopen the Time tab.
    func remember(_ level: TimeLevel) {
        storage.set(level.rawValue, forKey: Self.levelKey)
    }

    /// How tall an hour of the day view was last zoomed to.
    var savedHourHeight: CGFloat {
        let saved = Double(storage.string(forKey: Self.zoomKey) ?? "") ?? 0
        return saved >= Timeline.minHourHeight && saved <= Timeline.maxHourHeight
            ? CGFloat(saved) : Timeline.defaultHourHeight
    }

    func saveHourHeight(_ height: CGFloat) {
        storage.set(String(Double(height)), forKey: Self.zoomKey)
    }

    /// How wide an hour of the sideways day view was last zoomed to.
    var savedHourWidth: CGFloat {
        let saved = Double(storage.string(forKey: Self.sidewaysZoomKey) ?? "") ?? 0
        return saved >= ContinuousTimeline.minHourWidth && saved <= ContinuousTimeline.maxHourWidth
            ? CGFloat(saved) : ContinuousTimeline.defaultHourWidth
    }

    func saveHourWidth(_ width: CGFloat) {
        storage.set(String(Double(width)), forKey: Self.sidewaysZoomKey)
    }

    /// Whether `level` is what's on screen, with nothing over it or changing.
    func isShowing(_ level: TimeLevel) -> Bool {
        self.level == level && transition == nil && path.isEmpty
    }

    /// Whether `level` is drawn: what's showing, or what a transition is leaving.
    func isDrawn(_ level: TimeLevel) -> Bool {
        self.level == level || transition?.from == level
    }

    // MARK: Transitions

    /// Changes to `next`, opening the month view at `month` or the day view at `day`.
    ///
    /// Both levels are drawn first, as the transition starts them, and each reports where its anchor
    /// is (`report`); the animation runs once both have, or after a moment if one can't.
    func show(_ next: TimeLevel, month: Date? = nil, day: Date? = nil) {
        guard transition == nil, next != level else { return }
        if let day { self.day = Dates.startOfDay(day) }
        if let month {
            self.month = Dates.startOfMonth(month)
        } else if next == .month && level == .day {
            self.month = Dates.startOfMonth(self.day)
        }
        let transition = TimeTransition(from: level, to: next, month: self.month, day: self.day)
        anchors = [:]
        self.transition = transition
        level = next
        remember(next)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.start(transition.id) }
    }

    /// Where `level`'s anchor for the transition `id` is.
    func report(_ level: TimeLevel, _ rect: CGRect, transition id: UUID) {
        guard let transition, transition.id == id, transition.progress == 0 else { return }
        anchors[level] = rect
        if anchors[transition.from] != nil && anchors[transition.to] != nil {
            // After the levels have been drawn where the anchors put them.
            DispatchQueue.main.async { [weak self] in self?.start(id) }
        }
    }

    private func start(_ id: UUID) {
        guard let transition, transition.id == id, transition.progress == 0 else { return }
        withAnimation(Self.animation) {
            self.transition?.progress = 1
            barLevel = transition.to
        } completion: { [weak self] in
            guard let self, self.transition?.id == id else { return }
            self.transition = nil
            self.anchors = [:]
        }
    }

    /// How `level` is zoomed, if the transition is between the year and month views: shown, it's as
    /// it is, and hidden, its month is scaled and moved onto the other level's.
    func zoom(_ level: TimeLevel) -> LevelZoom {
        guard let transition, transition.isZoom, let hidden = transition.hiddenness(of: level) else {
            return LevelZoom()
        }
        guard let own = anchors[level], let other = anchors[level == .year ? .month : .year], own.width > 0 else {
            return LevelZoom(opacity: 1 - hidden)
        }
        // The scale and offset that put `own` onto `other`, partway there. A point on the way moves
        // in a straight line, since both change linearly.
        let scale = other.width / own.width
        let offset = CGSize(width: other.minX - scale * own.minX, height: other.minY - scale * own.minY)
        return LevelZoom(scale: 1 + (scale - 1) * hidden,
                         offset: CGSize(width: offset.width * hidden, height: offset.height * hidden),
                         opacity: 1 - hidden)
    }

    /// How far the month view's week is below the day view's strip, in a change between them.
    private var splitDistance: CGFloat {
        guard let week = anchors[.month], let strip = anchors[.day] else { return 0 }
        return week.minY - strip.minY
    }

    /// How the month view's weeks move apart, in a change to or from the day view.
    var monthSplit: MonthSplit? {
        guard let transition, !transition.isZoom, let hidden = transition.hiddenness(of: .month) else { return nil }
        return MonthSplit(day: transition.day, up: -splitDistance * hidden, down: 240 * hidden,
                          opacity: 1 - hidden)
    }

    /// How far the day view's strip and timeline are moved down, onto the month view's week, and how
    /// faded, in a change to or from the month view.
    var dayOffset: (y: CGFloat, opacity: Double) {
        guard let transition, let hidden = transition.hiddenness(of: .day) else { return (0, 1) }
        return (splitDistance * hidden, 1 - hidden)
    }
}

extension View {
    /// Reports this view's frame in `timeLevelSpace` for the transition `id`, if there is one.
    func reportsFrame(for id: UUID?, _ action: @escaping (CGRect) -> Void) -> some View {
        background {
            if let id {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(timeLevelSpace)) } action: { action($0) }
                    .id(id)
            }
        }
    }
}

/// The Time tab: the calendar, with Reminders and Alarms pushed over it.
///
/// Each screen pushed gets the app's environment again. When a screen with a toolbar is pushed after
/// going back, UIKit asks the toolbar's buttons for their accessibility labels (as VoiceOver and UI
/// tests do), and SwiftUI updates the screen to answer without the environment it inherits, so
/// reading an `@Environment` object crashes. Seen on iOS 26.3.
struct TimeTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var nav = model.time
        NavigationStack(path: $nav.path) {
            TimeLevels()
                .navigationDestination(for: TimeRoute.self) { route in
                    Group {
                        switch route {
                        case .reminders: RemindersView()
                        case .alarms: AlarmsView()
                        }
                    }
                    .appEnvironment(model)
                }
        }
        .sheet(item: $nav.alarmEditor) { request in
            NavigationStack { AlarmEditorView(alarm: request.alarm, day: request.day) }
        }
    }
}

/// The calendar's levels: the one showing, or two in a transition between them, and the navigation
/// bar, whose back button goes up a level.
private struct TimeLevels: View {
    @Environment(AppModel.self) private var model
    @State private var newReminder: NewReminderRequest?

    var body: some View {
        let nav = model.time
        ZStack {
            if nav.isDrawn(.year) {
                level(.year) { YearView(initialMonth: nav.month) }
            }
            if nav.isDrawn(.month) {
                level(.month) { MonthView(initialMonth: nav.month) }
            }
            if nav.isDrawn(.day) {
                level(.day) { DayView(initialDay: nav.day, hourHeight: nav.savedHourHeight) }
            }
        }
        .background(Theme.background)
        .allowsHitTesting(nav.transition == nil)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if nav.barLevel != .year {
                ToolbarItem(placement: .topBarLeading) { backButton }
            }
            ToolbarItem(placement: .principal) { Text("") }
            TimeToolbar(showsReminders: nav.barLevel != .day, day: nav.barLevel == .day ? nav.day : nil) {
                newReminder = NewReminderRequest(date: $0)
            }
        }
        .sheet(item: $newReminder) { request in
            NavigationStack { ReminderEditorView(date: request.date) }
        }
    }

    /// Like Calendar's: the month view's names the year it's showing, and the day view's the month.
    private var backButton: some View {
        let nav = model.time
        let toMonth = nav.barLevel == .day
        let title = toMonth ? Dates.formatMonth(nav.day) : String(Calendar.current.component(.year, from: nav.month))
        return Button {
            nav.show(toMonth ? .month : .year)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").fontWeight(.semibold)
                Text(title)
            }
        }
        .accessibilityLabel(title)
    }

    /// `content` filling the tab, measured in `timeLevelSpace`, and zoomed for a transition.
    private func level(_ level: TimeLevel, @ViewBuilder content: () -> some View) -> some View {
        let zoom = model.time.zoom(level)
        return content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(.named(timeLevelSpace))
            .scaleEffect(zoom.scale, anchor: .topLeading)
            .offset(zoom.offset)
            .opacity(zoom.opacity)
            .transition(.identity)
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
                    await TimeActions.createEvent(start: day.map { Dates.nextHalfHour(on: $0) },
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
                     : "Spacetime reads the calendars and reminders already on your phone.")
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

/// A new reminder, optionally on a day, for `.sheet(item:)`.
struct NewReminderRequest: Identifiable {
    let id = UUID()
    var date: Date?
}

/// The alarm editor to show: a new alarm (on `day`, if given) or an existing one.
struct AlarmEditRequest: Identifiable {
    let id = UUID()
    var alarm: SpacetimeAlarm?
    var day: Date?
}
#endif
