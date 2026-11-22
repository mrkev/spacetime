import SwiftUI

/// Open reminders: at a place, scheduled, and with no date.
struct RemindersView: View {
    @Environment(CalendarStore.self) private var calendar
    @Environment(SpaceStore.self) private var space
    @State private var newReminder: NewReminderRequest?
    @State private var openTodo: LocationReminder?
    @State private var openReminder: CalendarReminder?

    var body: some View {
        let located = LocationReminders.all(calendar)
        let locatedIds = Set(located.map(\.id))
        let others = calendar.openReminders.filter { !locatedIds.contains($0.key) }
        let scheduled = others.filter { $0.due != nil }
        let unscheduled = others.filter { $0.due == nil }
        let placeColor = Color(hex: space.reminderColor)

        List {
            if calendar.remindersStatus == .undetermined || calendar.remindersStatus == .denied {
                Section {
                    Button("Allow access to Reminders to see your scheduled reminders here.") {
                        if calendar.remindersStatus == .denied {
                            Presenter.openSettings()
                        } else {
                            Task { await calendar.requestAccess() }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                ForEach(located) { location in
                    PlaceReminderRow(location: location, color: placeColor) { openTodo = location }
                }
            } header: {
                SectionTitle("At a Place")
            } footer: {
                if located.isEmpty { Text("\(mapPressVerb) the map to add a place reminder.") }
            }
            Section {
                ForEach(scheduled) { reminder in
                    DatedReminderRow(reminder: reminder) { openReminder = reminder }
                }
            } header: {
                SectionTitle("Scheduled")
            } footer: {
                if scheduled.isEmpty { Text("No upcoming reminders.") }
            }
            if !unscheduled.isEmpty {
                Section {
                    ForEach(unscheduled) { reminder in
                        DatedReminderRow(reminder: reminder) { openReminder = reminder }
                    }
                } header: {
                    SectionTitle("No Date")
                }
            }
        }
        .navigationTitle("Reminders")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddMenu { newReminder = NewReminderRequest(date: $0) }
            }
        }
        .sizedSheet(item: $newReminder) { request in
            NavigationStack { ReminderEditorView(date: request.date) }
        }
        .sizedSheet(item: $openTodo) { todo in
            NavigationStack { TodoEditorView(existing: todo, place: nil) }
        }
        .sizedSheet(item: $openReminder) { reminder in
            ReminderDetailsView(id: reminder.key)
        }
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

private struct ReminderCheckButton: View {
    let reminder: CalendarReminder
    let color: Color
    @Environment(CalendarStore.self) private var calendar

    var body: some View {
        Button {
            do { try calendar.toggleReminder(reminder) } catch {
                Presenter.showError("Couldn’t Update Reminder", error)
            }
        } label: {
            Image(systemName: reminder.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reminder.title)
        .accessibilityValue(reminder.completed ? "Completed" : "Not completed")
    }
}

private struct PlaceReminderRow: View {
    let location: LocationReminder
    let color: Color
    let onPress: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReminderCheckButton(reminder: location.reminder, color: color)
            Button(action: onPress) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.title)
                            .foregroundStyle(location.completed ? Theme.secondaryText : .primary)
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill").font(.system(size: 11))
                            Text("\(location.placeName) · \(LocationReminders.describeTrigger(location))")
                                .lineLimit(1)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DatedReminderRow: View {
    let reminder: CalendarReminder
    let onPress: () -> Void

    var body: some View {
        let overdue = reminder.due.map { $0 < Date() } ?? false
        HStack(spacing: 12) {
            ReminderCheckButton(reminder: reminder, color: Color(hex: reminder.color))
            Button(action: onPress) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title).lineLimit(2)
                    Text([
                        reminder.due.map { due in
                            Dates.formatRelativeDay(due) + (reminder.allDay ? "" : ", \(Dates.formatTime(due))")
                        },
                        reminder.listTitle,
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(overdue ? Theme.tint : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}
