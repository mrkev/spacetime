import EventKit
#if os(iOS)
import EventKitUI
import UIKit
#endif

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

    init(_ event: CalendarEvent) {
        title = event.title
        durationMinutes = Int((event.end.timeIntervalSince(event.start) / 60).rounded())
        calendarId = event.calendarId
        location = event.location
        place = event.place
        notes = event.ek?.notes
        url = event.ek?.url
        alarms = (event.ek?.alarms ?? []).compactMap { $0.copy() as? EKAlarm }
        availability = event.ek?.availability ?? .busy
    }
}

/// Whether a change to a repeating event applies to later ones too.
enum Span: Hashable {
    case this, future

    var ek: EKSpan { self == .this ? .thisEvent : .futureEvents }
}

/// Creating, opening, and changing events and reminders, like Calendar does.
enum TimeActions {
    static var clipboard: CopiedEvent?

    /// Next half hour from now, on the given day.
    static func defaultStart(on day: Date? = nil) -> Date {
        let now = Date()
        let minutes = Dates.minutesIntoDay(now)
        let rounded = (minutes / 60) * 60 + (minutes % 60 < 30 ? 30 : 60)
        return Dates.date(day ?? now, atMinute: rounded)
    }

    /// Like Calendar, asks whether a change to a repeating event applies to later ones too.
    static func chooseSpan(_ event: CalendarEvent, verb: String) async -> Span? {
        guard event.recurring else { return .this }
        let delete = verb == "Delete"
        let choice = await Presenter.actionSheet(
            title: delete ? "Are you sure you want to delete this event? This is a repeating event."
                : "This is a repeating event.",
            options: [.init(label: "\(verb) This Event Only", destructive: delete),
                      .init(label: "\(verb) All Future Events", destructive: delete)])
        return choice.map { $0 == 0 ? .this : .future }
    }

    /// Opens the system editor for a new event, optionally at a place.
    static func createEvent(start: Date? = nil, place: EventLocation? = nil, calendar: CalendarStore) async {
        guard calendar.status == .granted else {
            await calendar.requestAccess()
            return
        }
        guard let target = calendar.defaultEventCalendar() else {
            Presenter.alert(title: "No Calendar", message: "Add a calendar account in Settings to create events.")
            return
        }
        let startDate = start ?? defaultStart()
        let event = EKEvent(eventStore: calendar.store)
        event.calendar = target
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(3600)
        if let place {
            event.location = place.title
            event.structuredLocation = place.structuredLocation
        }
        #if os(iOS)
        // The system editor, so events get every field Calendar supports.
        let editor = EKEventEditViewController()
        editor.eventStore = calendar.store
        editor.event = event
        let delegate = EditorDelegate { calendar.refresh() }
        editor.editViewDelegate = delegate
        delegate.retain(in: editor)
        Presenter.topViewController?.present(editor, animated: true)
        #else
        Presenter.present { close in
            EventEditorView(event: event, occurrence: nil, calendar: calendar, close: close)
        }
        #endif
    }

    /// Shows an event's details, where it can be edited or deleted, like in Calendar.
    static func openEvent(_ event: CalendarEvent, calendar: CalendarStore) {
        guard let ek = event.ek, calendar.store.event(withIdentifier: event.eventId) != nil else {
            Presenter.alert(title: "Couldn’t Open Event", message: "It may have been deleted. Try again in a moment.")
            calendar.refresh()
            return
        }
        #if os(iOS)
        let viewer = EKEventViewController()
        viewer.event = ek
        viewer.allowsEditing = true
        viewer.allowsCalendarPreview = true
        let delegate = ViewerDelegate { calendar.refresh() }
        viewer.delegate = delegate
        delegate.retain(in: viewer)
        let navigation = ToolbarlessNavigationController(rootViewController: viewer)
        Presenter.topViewController?.present(navigation, animated: true)
        #else
        Presenter.present { close in
            EventEditorView(event: ek, occurrence: event, calendar: calendar, close: close)
        }
        #endif
    }

    /// Saves new times for a dragged event. Returns false if it wasn't saved.
    static func reschedule(_ event: CalendarEvent, start: Date, end: Date, calendar: CalendarStore) async -> Bool {
        guard let ek = event.ek, let span = await chooseSpan(event, verb: "Save") else { return false }
        do {
            ek.startDate = start
            ek.endDate = end
            try calendar.store.save(ek, span: span.ek, commit: true)
            calendar.refresh()
            return true
        } catch {
            calendar.store.reset()
            calendar.refresh()
            Presenter.showError("Couldn’t Move Event", error)
            return false
        }
    }

    @discardableResult
    static func delete(_ event: CalendarEvent, calendar: CalendarStore) async -> Bool {
        guard let ek = event.ek, let span = await chooseSpan(event, verb: "Delete") else { return false }
        do {
            try calendar.store.remove(ek, span: span.ek, commit: true)
            calendar.refresh()
            return true
        } catch {
            calendar.refresh()
            Presenter.showError("Couldn’t Delete Event", error)
            return false
        }
    }

    static func copy(_ event: CalendarEvent) {
        clipboard = CopiedEvent(event)
    }

    static func cut(_ event: CalendarEvent, calendar: CalendarStore) async {
        copy(event)
        await delete(event, calendar: calendar)
    }

    static func paste(at start: Date, calendar: CalendarStore) {
        if let clipboard { insert(clipboard, at: start, calendar: calendar) }
    }

    /// Calendar puts the duplicate at the same time, alongside the original.
    static func duplicate(_ event: CalendarEvent, calendar: CalendarStore) {
        insert(CopiedEvent(event), at: event.start, calendar: calendar)
    }

    private static func insert(_ copied: CopiedEvent, at start: Date, calendar: CalendarStore) {
        guard let target = calendar.writableCalendar(copied.calendarId) ?? calendar.defaultEventCalendar() else {
            Presenter.alert(title: "No Calendar", message: "Add a calendar account in Settings to create events.")
            return
        }
        let event = EKEvent(eventStore: calendar.store)
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
        do {
            try calendar.store.save(event, span: .thisEvent, commit: true)
        } catch {
            Presenter.showError("Couldn’t Paste Event", error)
        }
        calendar.refresh()
    }

    /// Sets (or with nil, clears) where an event is, for the span picked.
    static func setPlace(_ location: EventLocation?, of event: CalendarEvent, span: Span,
                         calendar: CalendarStore) throws {
        guard let ek = event.ek else { return }
        ek.location = location?.title
        ek.structuredLocation = location?.structuredLocation
        try calendar.store.save(ek, span: span.ek, commit: true)
        calendar.refresh()
    }

    /// Opens a reminder in the Reminders app (an undocumented URL), or just the app if that fails.
    static func showInReminders(_ reminderId: String) {
        guard let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(reminderId)") else { return }
        openURL(url) { opened in
            if !opened, let app = URL(string: "x-apple-reminderkit://") { openURL(app) }
        }
    }
}

#if os(iOS)

/// Newer iOS versions also put a Delete button in the toolbar of EKEventViewController, which
/// duplicates the one in the event details. Keep the toolbar hidden so there's only one.
private final class ToolbarlessNavigationController: UINavigationController {
    override func setToolbarHidden(_ hidden: Bool, animated: Bool) {
        super.setToolbarHidden(true, animated: animated)
    }

    override var isToolbarHidden: Bool {
        get { super.isToolbarHidden }
        set { super.isToolbarHidden = true }
    }
}

private var delegateKey: UInt8 = 0

private class RetainedDelegate: NSObject {
    /// Delegates are weak, so the controller keeps its own alive.
    func retain(in controller: UIViewController) {
        objc_setAssociatedObject(controller, &delegateKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private final class EditorDelegate: RetainedDelegate, EKEventEditViewDelegate {
    let done: () -> Void
    init(done: @escaping () -> Void) { self.done = done }

    func eventEditViewController(_ controller: EKEventEditViewController,
                                 didCompleteWith action: EKEventEditViewAction) {
        controller.dismiss(animated: true)
        if action != .canceled { done() }
    }
}

private final class ViewerDelegate: RetainedDelegate, EKEventViewDelegate {
    let done: () -> Void
    init(done: @escaping () -> Void) { self.done = done }

    func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
        controller.dismiss(animated: true)
        done()
    }
}
#endif
