#if os(macOS)
import EventKit
import SwiftUI

/// Creates or edits a reminder in the system Reminders app.
struct ReminderEditorView: View {
    /// Changes to an existing reminder, or nil for a new one.
    var reminder: CalendarReminder?
    /// The day a new reminder starts out on.
    var date: Date?

    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var due: Date
    @State private var listId: String?
    @State private var saving = false
    @FocusState private var titleFocused: Bool

    init(reminder: CalendarReminder? = nil, date: Date? = nil) {
        self.reminder = reminder
        self.date = date
        _title = State(initialValue: reminder?.title ?? "")
        _notes = State(initialValue: reminder?.notes ?? "")
        _hasDate = State(initialValue: reminder.map { $0.due != nil } ?? (date != nil))
        _hasTime = State(initialValue: reminder.map { $0.due != nil && !$0.allDay } ?? false)
        _due = State(initialValue: reminder?.due ?? Dates.date(date ?? Date(), atMinute: 9 * 60))
    }

    private var writableLists: [EKCalendar] {
        calendar.reminderLists.filter(\.allowsContentModifications)
    }

    private var list: EKCalendar? {
        writableLists.first { $0.calendarIdentifier == listId } ?? calendar.defaultReminderList()
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (reminder != nil || list != nil) && !saving
    }

    var body: some View {
        Form {
            if calendar.remindersStatus == .denied {
                Section {
                    Text("Reminders access is off")
                } footer: {
                    Text("Allow access to Reminders in Settings to add reminders.")
                }
            }
            Section {
                TextField("Title", text: $title)
                    .focused($titleFocused)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...)
            }
            Section {
                Toggle("Date", isOn: $hasDate.animation())
                if hasDate {
                    DatePicker("Day", selection: $due, displayedComponents: .date)
                    Toggle("Time", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker("At", selection: $due, displayedComponents: .hourAndMinute)
                    }
                }
            }
            if let reminder {
                // EventKit's reminder updates can't move a reminder between lists here.
                Section("List") { Text(reminder.listTitle) }
            } else if writableLists.count > 1 {
                Section("List") {
                    ForEach(writableLists, id: \.calendarIdentifier) { l in
                        Button { listId = l.calendarIdentifier } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Color(cgColor: l.cgColor)).frame(width: 12, height: 12)
                                Text(l.title).foregroundStyle(.primary)
                                Spacer()
                                if l.calendarIdentifier == list?.calendarIdentifier {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(reminder == nil ? "New Reminder" : "Edit Reminder")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(reminder == nil ? "Add" : "Done", role: .confirmIfAvailable, action: save)
                    .disabled(!canSave)
            }
        }
        .task {
            if calendar.remindersStatus == .undetermined { await calendar.requestAccess() }
        }
        .onAppear { if reminder == nil { titleFocused = true } }
    }

    private func dueComponents() -> DateComponents? {
        guard hasDate else { return nil }
        var components = Calendar.current.dateComponents(
            hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: due)
        if hasTime { components.timeZone = .current }
        return components
    }

    private func save() {
        guard canSave else { return }
        saving = true
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: EKReminder
        if let existing = reminder?.ek {
            target = existing
        } else if let list {
            target = EKReminder(eventStore: calendar.store)
            target.calendar = list
        } else {
            return
        }
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        target.dueDateComponents = dueComponents()
        target.startDateComponents = dueComponents()
        // An alarm at the due time is what makes Reminders notify; keep any the user already set.
        if hasDate && hasTime && (target.alarms ?? []).isEmpty {
            target.addAlarm(EKAlarm(relativeOffset: 0))
        }
        do {
            try calendar.store.save(target, commit: true)
            calendar.refresh()
            dismiss()
        } catch {
            saving = false
            calendar.store.reset()
            Presenter.showError("Couldn’t Save Reminder", error)
        }
    }
}
#endif
