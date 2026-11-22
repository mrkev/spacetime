import EventKit

/// What "Copy" or "Cut" put aside, so "Paste" can recreate it.
struct CopiedEvent {
    var title: String
    var durationMinutes: Int
    var calendarId: String
    var location: String?
    var place: EventLocation?
    var notes: String?
    var url: URL?
    var alarms: [EKAlarm]
    var availability: EKEventAvailability

    init(_ event: CalendarEvent, ek: EKEvent?) {
        title = event.title
        durationMinutes = Int((event.end.timeIntervalSince(event.start) / 60).rounded())
        calendarId = event.calendarId
        location = event.location
        place = event.place
        notes = ek?.notes
        url = ek?.url
        alarms = (ek?.alarms ?? []).compactMap { $0.copy() as? EKAlarm }
        availability = ek?.availability ?? .busy
    }
}

/// Whether a change to a repeating event applies to later ones too.
enum Span: Hashable {
    case this, future

    var ek: EKSpan { self == .this ? .thisEvent : .futureEvents }
}

enum EventChangeError: LocalizedError {
    /// There's no writable calendar to put a new event in.
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .noCalendar: "Add a calendar account in Settings to create events."
        }
    }
}

/// Creating and changing events. Asking which events a change to a repeating one applies to, and saying
/// what went wrong, is up to the UI (see `TimeActions`).
extension CalendarStore {
    /// A new event an hour long in the default calendar, optionally at a place, not saved yet, for an
    /// editor to fill in. Nil if there's no calendar to put it in.
    func newEvent(start: Date, place: EventLocation? = nil) -> EKEvent? {
        guard let target = defaultEventCalendar() else { return nil }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        if let place {
            event.location = place.title
            event.structuredLocation = place.structuredLocation
        }
        return event
    }

    /// Saves new times for an event, for the span picked. If that fails, the event goes back to where it
    /// was.
    func move(_ ek: EKEvent, start: Date, end: Date, span: Span) throws {
        ek.startDate = start
        ek.endDate = end
        do {
            try store.save(ek, span: span.ek, commit: true)
        } catch {
            store.reset()
            refresh()
            throw error
        }
        refresh()
    }

    func delete(_ ek: EKEvent, span: Span) throws {
        defer { refresh() }
        try store.remove(ek, span: span.ek, commit: true)
    }

    /// Saves a copy of an event starting at `start`, in the original's calendar if it's still writable,
    /// or else the default one.
    func insert(_ copied: CopiedEvent, at start: Date) throws {
        guard let target = writableCalendar(copied.calendarId) ?? defaultEventCalendar() else {
            throw EventChangeError.noCalendar
        }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = copied.title
        event.startDate = start
        event.endDate = start.addingTimeInterval(Double(copied.durationMinutes) * 60)
        event.location = copied.location
        if let place = copied.place { event.structuredLocation = place.structuredLocation }
        event.notes = copied.notes
        event.url = copied.url
        event.alarms = copied.alarms.compactMap { $0.copy() as? EKAlarm }
        event.availability = copied.availability
        defer { refresh() }
        try store.save(event, span: .thisEvent, commit: true)
    }

    /// Sets (or with nil, clears) where an event is, for the span picked.
    func setPlace(_ location: EventLocation?, of event: CalendarEvent, span: Span) throws {
        guard let ek = ekEvent(for: event) else { return }
        ek.location = location?.title
        ek.structuredLocation = location?.structuredLocation
        try store.save(ek, span: span.ek, commit: true)
        refresh()
    }
}
