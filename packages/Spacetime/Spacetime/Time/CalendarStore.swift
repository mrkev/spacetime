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

/// An occurrence of an event, as read from EventKit. To show or change it, `CalendarStore.ekEvent(for:)`
/// finds the EventKit object again.
nonisolated struct CalendarEvent: Identifiable, Hashable, Sendable {
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

    var id: String { key }

    /// Unique per occurrence, so recurring events get distinct keys.
    static func key(eventId: String, start: Date) -> String {
        "\(eventId):\(Int((start.timeIntervalSince1970 * 1000).rounded()))"
    }
}

extension CalendarEvent {
    /// Reads an occurrence, on whichever thread its store is used on.
    nonisolated init?(_ e: EKEvent) {
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
        self.init(
            key: CalendarEvent.key(eventId: eventId, start: start),
            title: e.title?.isEmpty == false ? e.title! : "New Event",
            start: start, end: end, allDay: e.isAllDay,
            color: calendar.map { Hex.string(from: $0.cgColor) } ?? Theme.blueHex,
            calendarTitle: calendar?.title ?? "",
            location: location, place: place,
            editable: calendar?.allowsContentModifications ?? false,
            recurring: e.hasRecurrenceRules,
            eventId: eventId, calendarId: calendar?.calendarIdentifier ?? "")
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

/// Keys in the order they were last used, keeping only the latest `limit`.
nonisolated struct RecentKeys {
    let limit: Int
    private(set) var keys: [String] = []

    /// Marks `key` as just used, and returns the keys dropped to stay within the limit.
    mutating func use(_ key: String) -> [String] {
        keys.removeAll { $0 == key }
        keys.append(key)
        guard keys.count > limit else { return [] }
        let dropped = Array(keys.prefix(keys.count - limit))
        keys.removeFirst(dropped.count)
        return dropped
    }
}

/// How far ahead events show at their places on the map.
let upcomingDays = 30

/// Reads events away from the main thread, so scrolling and saving don't wait on EventKit. It has its own
/// event store, since a store and the events it returns aren't safe to share across threads.
actor EventReader {
    private var store = EKEventStore()
    private var generation = 0

    /// Each month's events, by month key and then day key, plus the next `upcomingDays` days' events if
    /// asked. A newer `generation` (a reload, after a change) starts from a new store, so nothing cached
    /// from before the change is read.
    func read(months: [Date], upcomingDays: Int? = nil, generation: Int)
        -> (months: [String: [String: [CalendarEvent]]], upcoming: [CalendarEvent]) {
        if generation > self.generation {
            self.generation = generation
            store = EKEventStore()
        }
        var loaded: [String: [String: [CalendarEvent]]] = [:]
        for month in months { loaded[Dates.monthKey(month)] = read(month: month) }
        return (loaded, upcomingDays.map(readUpcoming) ?? [])
    }

    private func read(month: Date) -> [String: [CalendarEvent]] {
        let start = Dates.startOfMonth(month)
        let end = Dates.addMonths(month, 1)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var days: [String: [CalendarEvent]] = [:]
        for ek in store.events(matching: predicate) {
            guard let event = CalendarEvent(ek) else { continue }
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

    private func readUpcoming(days: Int) -> [CalendarEvent] {
        let now = Date()
        let end = Dates.addDays(Dates.startOfDay(now), days + 1)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap(CalendarEvent.init)
    }
}

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

    /// The months asked for lately, which stay loaded. A refresh, after every change, reloads them, so
    /// only the most recent are kept: those around the screens you've just been looking at.
    @ObservationIgnored private var requested = RecentKeys(limit: 24)
    @ObservationIgnored private let reader = EventReader()
    /// Bumped by each reload; months read before the latest one are out of date.
    @ObservationIgnored private var generation = 0
    /// Months being read, so each is only asked for once.
    @ObservationIgnored private var loading = Set<String>()
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

    /// Reloads what's on screen: the loaded months, upcoming events, and reminders. What's showing
    /// stays until the new events are read.
    func refresh() {
        generation += 1
        loading = []
        loadReminders()
        guard status == .granted else {
            monthEvents = [:]
            upcomingEvents = []
            return
        }
        let generation = generation
        let months = requested.keys.compactMap(Dates.parseMonthKey)
        Task {
            let read = await reader.read(months: months, upcomingDays: upcomingDays, generation: generation)
            guard generation == self.generation else { return }
            // Months asked for since this began were read on their own.
            var next = monthEvents.filter { requested.keys.contains($0.key) }
            next.merge(read.months) { $1 }
            monthEvents = next
            upcomingEvents = Self.nextOccurrences(read.upcoming).filter { $0.place != nil }
        }
    }

    /// Starts reading the months around `date`, unless they're read or being read.
    func ensureMonths(_ date: Date, radius: Int = 1) {
        guard status == .granted else { return }
        var needed: [Date] = []
        for offset in -radius...radius {
            let month = Dates.addMonths(date, offset)
            let key = Dates.monthKey(month)
            for dropped in requested.use(key) { monthEvents[dropped] = nil }
            if monthEvents[key] == nil && loading.insert(key).inserted { needed.append(month) }
        }
        guard !needed.isEmpty else { return }
        let generation = generation
        Task {
            let read = await reader.read(months: needed, generation: generation)
            // A reload since this began reads these months again.
            guard generation == self.generation else { return }
            loading.subtract(read.months.keys)
            for (key, days) in read.months where requested.keys.contains(key) { monthEvents[key] = days }
        }
    }

    /// Items for a given day, or nil if that month hasn't loaded yet.
    func day(_ date: Date) -> DayItems? {
        guard let month = monthEvents[Dates.monthKey(date)] else { return nil }
        let key = Dates.dayKey(date)
        return DayItems(events: month[key] ?? [], reminders: datedReminders[key] ?? [])
    }

    /// The next occurrence of every event in the coming `upcomingDays`, soonest first.
    func listUpcomingEvents() async -> [CalendarEvent] {
        guard status == .granted else { return [] }
        let read = await reader.read(months: [], upcomingDays: upcomingDays, generation: generation)
        return Self.nextOccurrences(read.upcoming)
    }

    /// The next occurrence of each event that hasn't ended, soonest first.
    private static func nextOccurrences(_ events: [CalendarEvent]) -> [CalendarEvent] {
        let now = Date()
        var next: [String: CalendarEvent] = [:]
        for event in events where event.end > now {
            if let seen = next[event.eventId], seen.start <= event.start { continue }
            next[event.eventId] = event
        }
        return next.values.sorted { $0.start < $1.start }
    }

    /// The EventKit occurrence behind `event`, from this store, to show or change. (Events are read
    /// with another store, on another thread.)
    func ekEvent(for event: CalendarEvent) -> EKEvent? {
        guard status == .granted else { return nil }
        let end = max(event.end, event.start.addingTimeInterval(60))
        let predicate = store.predicateForEvents(withStart: event.start, end: end, calendars: nil)
        return store.events(matching: predicate).first {
            ($0.eventIdentifier ?? $0.calendarItemIdentifier) == event.eventId && $0.startDate == event.start
        }
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

    /// The color of the calendar new events go into, for drawing one before it's saved.
    var defaultEventColor: String {
        defaultEventCalendar().map { Hex.string(from: $0.cgColor) } ?? Theme.blueHex
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
