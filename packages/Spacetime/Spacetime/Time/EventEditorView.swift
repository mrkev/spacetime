#if os(macOS)
import EventKit
import SwiftUI

/// The Mac's event editor, since EventKitUI's isn't available there. It covers the common fields;
/// "Show in Calendar" opens the event in Calendar for the rest (invitees, alerts, repeating).
struct EventEditorView: View {
    let event: EKEvent
    /// The occurrence being shown, for asking about repeating events; nil for a new event.
    let occurrence: CalendarEvent?
    let calendar: CalendarStore
    let close: () -> Void

    @State private var title: String
    @State private var location: String
    @State private var allDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var calendarId: String
    @State private var url: String
    @State private var notes: String
    @State private var saving = false

    init(event: EKEvent, occurrence: CalendarEvent?, calendar: CalendarStore, close: @escaping () -> Void) {
        self.event = event
        self.occurrence = occurrence
        self.calendar = calendar
        self.close = close
        _title = State(initialValue: event.title ?? "")
        _location = State(initialValue: event.location ?? "")
        _allDay = State(initialValue: event.isAllDay)
        _start = State(initialValue: event.startDate)
        _end = State(initialValue: event.endDate)
        _calendarId = State(initialValue: event.calendar?.calendarIdentifier ?? "")
        _url = State(initialValue: event.url?.absoluteString ?? "")
        _notes = State(initialValue: event.notes ?? "")
    }

    private var isNew: Bool { occurrence == nil }
    private var editable: Bool { isNew || occurrence?.editable == true }

    private var calendars: [EKCalendar] {
        let writable = calendar.store.calendars(for: .event).filter(\.allowsContentModifications)
        // A read-only event's own calendar, so the picker can show it.
        if let own = event.calendar, !writable.contains(own) { return [own] + writable }
        return writable
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Title", text: $title, prompt: Text("New Event"))
                TextField("Location", text: $location)
                Toggle("All-day", isOn: $allDay)
                DatePicker("Starts", selection: $start,
                           displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $end, in: start...,
                           displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                if event.hasRecurrenceRules {
                    LabeledContent("Repeats", value: "Yes")
                }
                Picker("Calendar", selection: $calendarId) {
                    ForEach(calendars, id: \.calendarIdentifier) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(Color(cgColor: item.cgColor))
                        }
                        .tag(item.calendarIdentifier)
                    }
                }
                TextField("URL", text: $url)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            .formStyle(.grouped)
            .disabled(!editable)
            .onChange(of: start) { old, new in
                // Keep the duration, like Calendar.
                end = end.addingTimeInterval(new.timeIntervalSince(old))
            }

            HStack {
                if let occurrence, occurrence.editable {
                    Button("Delete", role: .destructive) {
                        Task {
                            if await TimeActions.delete(occurrence, calendar: calendar) { close() }
                        }
                    }
                }
                if !isNew {
                    Button("Show in Calendar") { showInCalendar() }
                }
                Spacer()
                if editable {
                    Button("Cancel", role: .cancel, action: close)
                        .keyboardShortcut(.cancelAction)
                    Button(isNew ? "Add" : "Save") { Task { await save() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(saving || calendarId.isEmpty)
                } else {
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 460, height: 560)
    }

    private func save() async {
        let span: Span
        if let occurrence {
            guard let picked = await TimeActions.chooseSpan(occurrence, verb: "Save") else { return }
            span = picked
        } else {
            span = .this
        }
        saving = true
        defer { saving = false }
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLocation != (event.location ?? "") {
            // A typed location has no coordinates; drop the old ones.
            event.structuredLocation = nil
            event.location = trimmedLocation.isEmpty ? nil : trimmedLocation
        }
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = max(end, start)
        if let target = calendars.first(where: { $0.calendarIdentifier == calendarId }) { event.calendar = target }
        event.url = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
        event.notes = notes.isEmpty ? nil : notes
        do {
            try calendar.store.save(event, span: span.ek, commit: true)
            calendar.refresh()
            close()
        } catch {
            event.rollback()
            Presenter.showError("Couldn’t Save Event", error)
        }
    }

    /// Calendar opens events from `ical://` links (undocumented, but long-standing).
    private func showInCalendar() {
        guard let id = event.eventIdentifier?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let link = URL(string: "ical://ekevent/\(id)?method=show&options=more")
        else { return }
        openURL(link) { opened in
            if !opened, let app = URL(string: "ical://") { openURL(app) }
        }
        close()
    }
}
#endif
