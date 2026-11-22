import EventKit
import Foundation

/// Reminders uses its own default when a location alarm's radius is 0.
let defaultRadius: Double = 100

/// A reminder in Apple Reminders with a location alarm, which Reminders fires when you arrive at or
/// leave the place. These are the places in the Reminders collection.
struct LocationReminder: Identifiable, Hashable, Located {
    /// The reminder's ID.
    var id: String
    var title: String
    var placeName: String
    var address: String?
    var notes: String?
    var latitude: Double
    var longitude: Double
    var trigger: ReminderTrigger
    /// In meters.
    var radius: Double
    var completed: Bool
    var reminder: CalendarReminder
}

/// What the place form saves as a location reminder.
struct LocationReminderInput {
    var title: String
    var placeName: String
    var address: String?
    var notes: String?
    var trigger: ReminderTrigger
    var radius: Double
    var latitude: Double
    var longitude: Double
}

enum LocationReminders {
    static func from(_ reminder: CalendarReminder, meta: ReminderMetaStore?) -> LocationReminder? {
        guard let alarm = reminder.locatedAlarm else { return nil }
        return LocationReminder(
            id: reminder.key, title: reminder.title,
            placeName: alarm.title.isEmpty ? "Location" : alarm.title,
            address: meta?.meta(for: reminder.ref).address,
            notes: reminder.notes,
            latitude: alarm.latitude, longitude: alarm.longitude,
            trigger: alarm.proximity == .leave ? .leave : .arrive,
            radius: alarm.radius > 0 ? alarm.radius : defaultRadius,
            completed: reminder.completed, reminder: reminder)
    }

    /// Every incomplete reminder with a location, from any list (including ones made in Reminders).
    static func all(_ calendar: CalendarStore) -> [LocationReminder] {
        calendar.openReminders.compactMap { from($0, meta: calendar.meta) }
    }

    static func alarm(placeName: String, trigger: ReminderTrigger, radius: Double, latitude: Double,
                      longitude: Double) -> EKAlarm {
        let location = EKStructuredLocation(title: placeName)
        location.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
        location.radius = radius
        let alarm = EKAlarm()
        alarm.structuredLocation = location
        alarm.proximity = trigger == .leave ? .leave : .enter
        return alarm
    }

    private static func isLocated(_ alarm: EKAlarm) -> Bool {
        alarm.structuredLocation?.geoLocation != nil
    }

    static func create(in list: EKCalendar, _ input: LocationReminderInput, completed: Bool = false,
                       calendar: CalendarStore) throws {
        let reminder = EKReminder(eventStore: calendar.store)
        reminder.calendar = list
        reminder.title = input.title
        reminder.notes = input.notes
        reminder.addAlarm(alarm(placeName: input.placeName, trigger: input.trigger, radius: input.radius,
                                latitude: input.latitude, longitude: input.longitude))
        reminder.isCompleted = completed
        try calendar.store.save(reminder, commit: true)
        calendar.meta.set(ReminderMeta(address: input.address),
                          for: ReminderRef(id: reminder.calendarItemIdentifier,
                                           externalId: reminder.calendarItemExternalIdentifier))
        calendar.refresh()
    }

    static func update(_ existing: LocationReminder, _ input: LocationReminderInput,
                       calendar: CalendarStore) throws {
        guard let ek = existing.reminder.ek else { return }
        ek.title = input.title
        ek.notes = input.notes
        // Keep any other alarms (e.g. a time set in Reminders); only the location one is replaced.
        ek.alarms = (ek.alarms ?? []).filter { !isLocated($0) } + [
            alarm(placeName: input.placeName, trigger: input.trigger, radius: input.radius,
                  latitude: input.latitude, longitude: input.longitude),
        ]
        try calendar.store.save(ek, commit: true)
        let ref = existing.reminder.ref
        var meta = calendar.meta.meta(for: ref)
        meta.address = input.address
        calendar.meta.set(meta, for: ref)
        calendar.refresh()
    }

    /// Gives a reminder a location: a place it reminds you at, replacing any it had. It keeps its
    /// trigger and radius if it had a location, or else gets `defaults`.
    static func move(_ reminder: CalendarReminder, to place: some Located, name: String, address: String?,
                     defaults: (trigger: ReminderTrigger, radius: Double), calendar: CalendarStore) throws {
        guard let ek = reminder.ek else { return }
        ek.alarms = movedAlarms(reminder, alarms: ek.alarms ?? [], to: place, name: name, defaults: defaults)
        try calendar.store.save(ek, commit: true)
        var meta = calendar.meta.meta(for: reminder.ref)
        meta.address = address
        calendar.meta.set(meta, for: reminder.ref)
        calendar.refresh()
    }

    /// A reminder's alarms with its location alarm (if any) replaced by one at `place`, keeping the
    /// trigger and radius it had, or else using `defaults`.
    static func movedAlarms(_ reminder: CalendarReminder, alarms: [EKAlarm], to place: some Located, name: String,
                            defaults: (trigger: ReminderTrigger, radius: Double)) -> [EKAlarm] {
        let located = from(reminder, meta: nil)
        return alarms.filter { !isLocated($0) } + [
            alarm(placeName: name, trigger: located?.trigger ?? defaults.trigger,
                  radius: located?.radius ?? defaults.radius, latitude: place.latitude, longitude: place.longitude),
        ]
    }

    static func describeTrigger(trigger: ReminderTrigger, radius: Double) -> String {
        let when = trigger == .arrive ? "Arriving" : "Leaving"
        let distance = radius >= 1000 ? "\(formatNumber(radius / 1000)) km" : "\(formatNumber(radius)) m"
        return "\(when) · \(distance)"
    }

    static func describeTrigger(_ reminder: LocationReminder) -> String {
        describeTrigger(trigger: reminder.trigger, radius: reminder.radius)
    }

    private static func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
