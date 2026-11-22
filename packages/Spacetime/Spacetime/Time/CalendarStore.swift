import EventKit
import SwiftUI

enum AccessStatus {
    case loading, undetermined, granted, denied
}

/// A place on the map, for an event's location. The title is what the event shows as its location.
nonisolated struct EventLocation: Hashable, Sendable, Located {
    var title: String
    var latitude: Double
    var longitude: Double

    var structuredLocation: EKStructuredLocation {
        let location = EKStructuredLocation(title: title)
        location.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
        return location
    }
}

struct CalendarEvent: Identifiable, Hashable {
    /// Unique per occurrence, so recurring events get distinct keys.
    var key: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var color: String
    var calendarTitle: String
    var location: String?
    /// Where it is on the map, if its location has coordinates.
    var place: EventLocation?
    /// False for read-only calendars (subscriptions, birthdays, invitations we can't change).
    var editable: Bool
    var recurring: Bool
    /// The event's ID, the same for every occurrence.
    var eventId: String
    var calendarId: String
    var ek: EKEvent?

    var id: String { key }

    /// Unique per occurrence, so recurring events get distinct keys.
    static func key(eventId: String, start: Date) -> String {
        "\(eventId):\(Int((start.timeIntervalSince1970 * 1000).rounded()))"
    }
}

/// A reminder's location alarm, which Reminders fires when you arrive at or leave a place.
nonisolated struct LocatedAlarm: Hashable, Sendable {
    var title: String
    var proximity: EKAlarmProximity
    var radius: Double
    var latitude: Double
    var longitude: Double
}

struct CalendarReminder: Identifiable, Hashable {
    var key: String
    /// The server's ID, shared across devices (see `ReminderRef`).
    var externalId: String?
    var title: String
    var due: Date?
    /// True when the reminder has a date but no time.
    var allDay: Bool
    var completed: Bool
    var color: String
    var listTitle: String
    var notes: String?
    var locatedAlarm: LocatedAlarm?
    var ek: EKReminder?

    var id: String { key }
    var ref: ReminderRef { ReminderRef(id: key, externalId: externalId) }
}

struct DayItems: Equatable {
    var events: [CalendarEvent] = []
    var reminders: [CalendarReminder] = []

    static let empty = DayItems()
}

/// How far ahead events show at their places on the map.
let upcomingDays = 30

/// The events and reminders already on the phone, through EventKit.
@Observable
final class CalendarStore {
    @ObservationIgnored let store = EKEventStore()
    let meta: ReminderMetaStore

    private(set) var status: AccessStatus = .loading
    private(set) var remindersStatus: AccessStatus = .loading
    private(set) var eventCalendars: [EKCalendar] = []
    private(set) var reminderLists: [EKCalendar] = []
    /// Incomplete reminders across all lists.
    private(set) var openReminders: [CalendarReminder] = []
    /// The next occurrence of each event in the coming `upcomingDays` that has a place on the map,
    /// soonest first.
    private(set) var upcomingEvents: [CalendarEvent] = []
    /// Loaded months' events, by month key and then day key.
    private var monthEvents: [String: [String: [CalendarEvent]]] = [:]
    /// Reminders with a due date, by day key.
    private var datedReminders: [String: [CalendarReminder]] = [:]

    /// Months we've been asked for, so a refresh can reload exactly what's on screen.
    @ObservationIgnored private var requested = Set<String>()
    @ObservationIgnored private var reminderGeneration = 0
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    init(meta: ReminderMetaStore) {
        self.meta = meta
        checkPermissions()
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }

    // MARK: Access

    private static func status(_ status: EKAuthorizationStatus) -> AccessStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    /// Re-reads access, e.g. when coming back from Settings, and reloads if it changed.
    func checkPermissions() {
        let events = Self.status(EKEventStore.authorizationStatus(for: .event))
        let reminders = Self.status(EKEventStore.authorizationStatus(for: .reminder))
        guard events != status || reminders != remindersStatus else { return }
        status = events
        remindersStatus = reminders
        reloadCalendars()
    }

    func requestAccess() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        checkPermissions()
    }

    // MARK: Loading

    /// Re-reads the calendar lists, then everything else.
    func reloadCalendars() {
        eventCalendars = status == .granted ? store.calendars(for: .event) : []
        reminderLists = remindersStatus == .granted ? store.calendars(for: .reminder) : []
        refresh()
    }

    /// Calendar and Reminders changes (ours too) arrive in bursts, so they're coalesced.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            reloadCalendars()
        }
    }

    /// Reloads what's on screen: the loaded months, upcoming events, and reminders.
    func refresh() {
        var next: [String: [String: [CalendarEvent]]] = [:]
        if status == .granted {
            for key in requested {
                if let month = Dates.parseMonthKey(key) { next[key] = fetchMonth(month) }
            }
        }
        monthEvents = next
        upcomingEvents = nextOccurrences(fetchUpcoming()).filter { $0.place != nil }
        loadReminders()
    }

    /// Kicks off loading the months around `date` (no-op if cached).
    func ensureMonths(_ date: Date, radius: Int = 1) {
        guard status == .granted else { return }
        for offset in -radius...radius {
            let month = Dates.addMonths(date, offset)
            let key = Dates.monthKey(month)
            requested.insert(key)
            if monthEvents[key] == nil { monthEvents[key] = fetchMonth(month) }
        }
    }

    /// Items for a given day, or nil if that month hasn't loaded yet.
    func day(_ date: Date) -> DayItems? {
        guard let month = monthEvents[Dates.monthKey(date)] else { return nil }
        let key = Dates.dayKey(date)
        return DayItems(events: month[key] ?? [], reminders: datedReminders[key] ?? [])
    }

    private func fetchMonth(_ month: Date) -> [String: [CalendarEvent]] {
        guard !eventCalendars.isEmpty else { return [:] }
        let start = Dates.startOfMonth(month)
        let end = Dates.addMonths(month, 1)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: eventCalendars)
        var days: [String: [CalendarEvent]] = [:]
        for ek in store.events(matching: predicate) {
            guard let event = toEvent(ek) else { continue }
            // Add multi-day events to every day they touch (within this month).
            let lastMoment = max(event.start, event.end.addingTimeInterval(-0.001))
            var day = Dates.startOfDay(event.start)
            while day <= lastMoment && day < end {
                if day >= start { days[Dates.dayKey(day), default: []].append(event) }
                day = Dates.addDays(day, 1)
            }
        }
        for key in days.keys { days[key]!.sort { $0.start < $1.start } }
        return days
    }

    private func fetchUpcoming() -> [CalendarEvent] {
        guard !eventCalendars.isEmpty else { return [] }
        let now = Date()
        let end = Dates.addDays(Dates.startOfDay(now), upcomingDays + 1)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: eventCalendars)
        return store.events(matching: predicate).compactMap(toEvent)
    }

    /// The next occurrence of every event in the coming `upcomingDays`, soonest first.
    func listUpcomingEvents() -> [CalendarEvent] {
        nextOccurrences(fetchUpcoming())
    }

    /// The next occurrence of each event that hasn't ended, soonest first.
    private func nextOccurrences(_ events: [CalendarEvent]) -> [CalendarEvent] {
        let now = Date()
        var next: [String: CalendarEvent] = [:]
        for event in events where event.end > now {
            if let seen = next[event.eventId], seen.start <= event.start { continue }
            next[event.eventId] = event
        }
        return next.values.sorted { $0.start < $1.start }
    }

    private func loadReminders() {
        reminderGeneration += 1
        let generation = reminderGeneration
        guard remindersStatus == .granted, !reminderLists.isEmpty else {
            openReminders = []
            datedReminders = [:]
            return
        }
        let predicate = store.predicateForReminders(in: reminderLists)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            nonisolated(unsafe) let fetched = reminders ?? []
            Task { @MainActor in
                guard let self, generation == self.reminderGeneration else { return }
                self.applyReminders(fetched)
            }
        }
    }

    private func applyReminders(_ fetched: [EKReminder]) {
        let reminders = fetched.compactMap(toReminder)
        openReminders = reminders.filter { !$0.completed }.sorted {
            ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture)
        }
        var dated: [String: [CalendarReminder]] = [:]
        for reminder in reminders {
            if let due = reminder.due { dated[Dates.dayKey(due), default: []].append(reminder) }
        }
        for key in dated.keys { dated[key]!.sort { $0.due! < $1.due! } }
        datedReminders = dated
        // Keep what we store about reminders matched up with them, and forget deleted ones.
        let seen = openReminders.map(\.ref)
        Task {
            await meta.reconcile(seen: seen) { [store] id in store.calendarItem(withIdentifier: id) != nil }
        }
    }

    // MARK: Conversion

    func toEvent(_ e: EKEvent) -> CalendarEvent? {
        guard let start = e.startDate else { return nil }
        let end = e.endDate ?? start
        let eventId = e.eventIdentifier ?? e.calendarItemIdentifier
        let calendar = e.calendar
        var place: EventLocation?
        if let structured = e.structuredLocation, let geo = structured.geoLocation {
            place = EventLocation(title: structured.title ?? "", latitude: geo.coordinate.latitude,
                                  longitude: geo.coordinate.longitude)
        }
        let location = e.location?.isEmpty == false ? e.location : nil
        return CalendarEvent(
            key: CalendarEvent.key(eventId: eventId, start: start),
            title: e.title?.isEmpty == false ? e.title! : "New Event",
            start: start, end: end, allDay: e.isAllDay,
            color: calendar.map { Hex.string(from: $0.cgColor) } ?? Theme.blueHex,
            calendarTitle: calendar?.title ?? "",
            location: location, place: place,
            editable: calendar?.allowsContentModifications ?? false,
            recurring: e.hasRecurrenceRules,
            eventId: eventId, calendarId: calendar?.calendarIdentifier ?? "", ek: e)
    }

    func toReminder(_ r: EKReminder) -> CalendarReminder? {
        let components = r.dueDateComponents ?? r.startDateComponents
        let due = components.flatMap { Calendar.current.date(from: $0) }
        let list = r.calendar
        var located: LocatedAlarm?
        for alarm in r.alarms ?? [] {
            if let location = alarm.structuredLocation, let geo = location.geoLocation {
                located = LocatedAlarm(title: location.title ?? "", proximity: alarm.proximity,
                                       radius: location.radius, latitude: geo.coordinate.latitude,
                                       longitude: geo.coordinate.longitude)
                break
            }
        }
        return CalendarReminder(
            key: r.calendarItemIdentifier, externalId: r.calendarItemExternalIdentifier,
            title: r.title?.isEmpty == false ? r.title! : "Untitled",
            due: due, allDay: due != nil && components?.hour == nil,
            completed: r.isCompleted,
            color: list.map { Hex.string(from: $0.cgColor) } ?? "#FF9500",
            listTitle: list?.title ?? "Reminders",
            notes: r.notes?.isEmpty == false ? r.notes : nil,
            locatedAlarm: located, ek: r)
    }

    // MARK: Lookups

    /// A reminder by ID: a loaded one, or else straight from Reminders (which finds completed ones).
    func reminder(_ id: String) -> CalendarReminder? {
        if let found = openReminders.first(where: { $0.key == id }) { return found }
        for day in datedReminders.values {
            if let found = day.first(where: { $0.key == id }) { return found }
        }
        return (store.calendarItem(withIdentifier: id) as? EKReminder).flatMap(toReminder)
    }

    /// The list new reminders go into by default.
    func defaultReminderList() -> EKCalendar? {
        let writable = reminderLists.filter(\.allowsContentModifications)
        if let preferred = store.defaultCalendarForNewReminders(),
           writable.contains(where: { $0.calendarIdentifier == preferred.calendarIdentifier }) {
            return preferred
        }
        return writable.first
    }

    /// The calendar new events go into by default.
    func defaultEventCalendar() -> EKCalendar? {
        if let preferred = store.defaultCalendarForNewEvents, preferred.allowsContentModifications {
            return preferred
        }
        return eventCalendars.first(where: \.allowsContentModifications)
    }

    /// A writable event calendar by ID.
    func writableCalendar(_ id: String) -> EKCalendar? {
        guard let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications else {
            return nil
        }
        return calendar
    }

    // MARK: Changes

    func toggleReminder(_ reminder: CalendarReminder) throws {
        guard let ek = reminder.ek else { return }
        // EventKit sets or clears the completion date along with the flag.
        ek.isCompleted = !reminder.completed
        try store.save(ek, commit: true)
        refresh()
    }

    func deleteReminder(_ reminder: CalendarReminder) throws {
        guard let ek = reminder.ek else { return }
        try store.remove(ek, commit: true)
        refresh()
    }
}
