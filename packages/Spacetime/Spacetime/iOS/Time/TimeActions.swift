#if os(iOS)
import EventKit
import EventKitUI
import UIKit

/// Creating, opening, and changing events and reminders, like Calendar does.
enum TimeActions {
    static var clipboard: CopiedEvent?

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

    /// Opens the system editor for a new event, optionally at a place. `onClose` runs once the editor
    /// is gone, or right away if it couldn't open.
    static func createEvent(start: Date? = nil, place: EventLocation? = nil, calendar: CalendarStore,
                            onClose: @escaping () -> Void = {}) async {
        guard calendar.status == .granted else {
            await calendar.requestAccess()
            onClose()
            return
        }
        guard let event = calendar.newEvent(start: start ?? Dates.nextHalfHour(), place: place) else {
            noCalendarAlert()
            onClose()
            return
        }
        // The system editor, so events get every field Calendar supports.
        let editor = NewEventEditor()
        editor.eventStore = calendar.store
        editor.event = event
        editor.onClose = onClose
        let delegate = EditorDelegate { calendar.refresh() }
        editor.editViewDelegate = delegate
        delegate.retain(in: editor)
        guard let presenter = Presenter.topViewController else {
            onClose()
            return
        }
        presenter.present(editor, animated: true)
    }

    /// Shows an event's details, where it can be edited or deleted, like in Calendar.
    static func openEvent(_ event: CalendarEvent, calendar: CalendarStore) {
        guard let ek = calendar.ekEvent(for: event) else {
            Presenter.alert(title: "Couldn’t Open Event", message: "It may have been deleted. Try again in a moment.")
            calendar.refresh()
            return
        }
        let viewer = EKEventViewController()
        viewer.event = ek
        viewer.allowsEditing = true
        viewer.allowsCalendarPreview = true
        let delegate = ViewerDelegate { calendar.refresh() }
        viewer.delegate = delegate
        delegate.retain(in: viewer)
        let navigation = ToolbarlessNavigationController(rootViewController: viewer)
        Presenter.topViewController?.present(navigation, animated: true)
    }

    /// Saves new times for a dragged event. Returns false if it wasn't saved.
    static func reschedule(_ event: CalendarEvent, start: Date, end: Date, calendar: CalendarStore) async -> Bool {
        guard let ek = calendar.ekEvent(for: event), let span = await chooseSpan(event, verb: "Save") else {
            return false
        }
        do {
            try calendar.move(ek, start: start, end: end, span: span)
            return true
        } catch {
            Presenter.showError("Couldn’t Move Event", error)
            return false
        }
    }

    @discardableResult
    static func delete(_ event: CalendarEvent, calendar: CalendarStore) async -> Bool {
        guard let ek = calendar.ekEvent(for: event), let span = await chooseSpan(event, verb: "Delete") else {
            return false
        }
        do {
            try calendar.delete(ek, span: span)
            return true
        } catch {
            Presenter.showError("Couldn’t Delete Event", error)
            return false
        }
    }

    static func copy(_ event: CalendarEvent, calendar: CalendarStore) {
        clipboard = CopiedEvent(event, ek: calendar.ekEvent(for: event))
    }

    static func cut(_ event: CalendarEvent, calendar: CalendarStore) async {
        copy(event, calendar: calendar)
        await delete(event, calendar: calendar)
    }

    static func paste(at start: Date, calendar: CalendarStore) {
        if let clipboard { insert(clipboard, at: start, calendar: calendar) }
    }

    /// Calendar puts the duplicate at the same time, alongside the original.
    static func duplicate(_ event: CalendarEvent, calendar: CalendarStore) {
        insert(CopiedEvent(event, ek: calendar.ekEvent(for: event)), at: event.start, calendar: calendar)
    }

    private static func insert(_ copied: CopiedEvent, at start: Date, calendar: CalendarStore) {
        do {
            try calendar.insert(copied, at: start)
        } catch EventChangeError.noCalendar {
            noCalendarAlert()
        } catch {
            Presenter.showError("Couldn’t Paste Event", error)
        }
    }

    private static func noCalendarAlert() {
        Presenter.alert(title: "No Calendar", message: EventChangeError.noCalendar.localizedDescription)
    }

    /// Opens a reminder in the Reminders app (an undocumented URL), or just the app if that fails.
    static func showInReminders(_ reminderId: String) {
        guard let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(reminderId)") else { return }
        UIApplication.shared.open(url) { opened in
            if !opened, let app = URL(string: "x-apple-reminderkit://") { UIApplication.shared.open(app) }
        }
    }
}

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

/// The system's new-event editor, saying when it's gone: saved, cancelled, or swiped away.
private final class NewEventEditor: EKEventEditViewController {
    var onClose: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed, let onClose else { return }
        self.onClose = nil
        onClose()
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
