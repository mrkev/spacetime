#if os(iOS)
import SwiftUI

/// A reminder's details, like the card Calendar shows for one.
struct ReminderDetailsView: View {
    let id: String

    @Environment(CalendarStore.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    /// Undated reminders drop out of the loaded data once completed, so keep showing the last copy.
    @State private var last: CalendarReminder?
    /// Checked state flips right away; the calendar catches up when it reloads.
    @State private var completed: Bool?
    @State private var editing = false

    var body: some View {
        let reminder = calendar.reminder(id) ?? last
        NavigationStack {
            Group {
                if let reminder {
                    details(reminder)
                } else {
                    ContentUnavailableView("This reminder is no longer available.", systemImage: "checklist")
                }
            }
            .background(Theme.groupedBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
                if reminder != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { editing = true }
                    }
                }
            }
        }
        .onChange(of: reminder, initial: true) { _, found in if let found { last = found } }
        .onChange(of: reminder?.due) { _, due in if let due { calendar.ensureMonths(due, radius: 0) } }
        .onAppear { if let due = reminder?.due { calendar.ensureMonths(due, radius: 0) } }
        .sheet(isPresented: $editing) {
            if let reminder {
                // Location reminders are edited like places, with their map and radius.
                if let location = LocationReminders.from(reminder, meta: calendar.meta) {
                    NavigationStack { TodoEditorView(existing: location, place: nil) }
                } else {
                    NavigationStack { ReminderEditorView(reminder: reminder) }
                }
            }
        }
    }

    private func details(_ reminder: CalendarReminder) -> some View {
        let isCompleted = completed ?? reminder.completed
        let location = LocationReminders.from(reminder, meta: calendar.meta)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Button {
                        completed = !isCompleted
                        var current = reminder
                        current.completed = isCompleted
                        do { try calendar.toggleReminder(current) } catch {
                            completed = nil
                            Presenter.showError("Couldn’t Update Reminder", error)
                        }
                    } label: {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 34))
                            .foregroundStyle(Color(hex: reminder.color))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reminder.title)
                    .accessibilityValue(isCompleted ? "Completed" : "Not completed")
                    Text(reminder.title)
                        .font(.system(size: 28, weight: .bold))
                        .opacity(isCompleted ? 0.5 : 1)
                        .accessibilityAddTraits(.isHeader)
                }

                if let due = reminder.due {
                    VStack(alignment: .leading) {
                        Text(Dates.formatFullDate(due))
                        if !reminder.allDay { Text(Dates.formatTime(due)) }
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                }

                if let location {
                    Detail(label: "Location",
                           value: "\(location.placeName)\n\(LocationReminders.describeTrigger(location))")
                }
                Detail(label: "List", value: reminder.listTitle)
                if let notes = reminder.notes { Detail(label: "Notes", value: notes) }

                if let due = reminder.due, !reminder.allDay {
                    MiniTimeline(at: due, day: calendar.day(due), highlightKey: reminder.key)
                }

                VStack(spacing: 20) {
                    WideButton(label: "Show in Reminders") { TimeActions.showInReminders(reminder.key) }
                    WideButton(label: "Delete Reminder", destructive: true) {
                        Task { await delete(reminder) }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private func delete(_ reminder: CalendarReminder) async {
        let choice = await Presenter.actionSheet(
            title: "Are you sure you want to delete this reminder?",
            options: [.init(label: "Delete Reminder", destructive: true)])
        guard choice == 0 else { return }
        do {
            try calendar.deleteReminder(reminder)
            dismiss()
        } catch {
            Presenter.showError("Couldn’t Delete Reminder", error)
        }
    }
}

private struct Detail: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

private struct WideButton: View {
    let label: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .foregroundStyle(destructive ? Theme.tint : .primary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Theme.card, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// A few hours of the day around `at`, like the preview in Calendar's details: what else is going
/// on then, with the item `highlightKey` picked out.
struct MiniTimeline: View {
    let at: Date
    let day: DayItems?
    let highlightKey: String

    private let hour: CGFloat = 44
    private let hours = 3
    private let gutter: CGFloat = 52
    private let padding: CGFloat = 14

    private enum Kind { case event, reminder }

    var body: some View {
        let firstHour = max(0, min(24 - hours, Calendar.current.component(.hour, from: at) - 1))
        let from = Double(firstHour * 60)
        let to = from + Double(hours * 60)
        let dayStart = Dates.startOfDay(at)
        let dayEnd = Dates.addDays(dayStart, 1)
        var items: [(key: String, range: MinuteRange, item: (title: String, color: String, kind: Kind))] = []
        for event in day?.events ?? [] where !(event.allDay || (event.start <= dayStart && event.end >= dayEnd)) {
            let start = event.start < dayStart ? 0 : Double(Dates.minutesIntoDay(event.start))
            let end = event.end >= dayEnd ? 24 * 60 : Double(Dates.minutesIntoDay(event.end))
            if end <= from || start >= to { continue }
            items.append((event.key, MinuteRange(startMinute: start, endMinute: end), (event.title, event.color, .event)))
        }
        for reminder in day?.reminders ?? [] {
            guard let due = reminder.due, !reminder.allDay else { continue }
            let start = Double(Dates.minutesIntoDay(due))
            if start + 30 <= from || start >= to { continue }
            items.append((reminder.key, MinuteRange(startMinute: start, endMinute: start + 30),
                          (reminder.title, reminder.color, .reminder)))
        }
        let laidOut = TimelineLayout.layout(items)
        func y(_ minute: Double) -> CGFloat { padding + CGFloat(minute - from) / 60 * hour }

        return GeometryReader { geometry in
            let columnsWidth = geometry.size.width - gutter - 14
            ZStack(alignment: .topLeading) {
                ForEach(0...hours, id: \.self) { i in
                    HStack(spacing: 0) {
                        Text(Dates.formatHour(hour: firstHour + i))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: gutter - 8, alignment: .trailing)
                            .padding(.trailing, 8)
                        Rectangle().fill(Theme.hourLine).frame(height: 1 / 3)
                    }
                    .frame(width: geometry.size.width - 14, height: 16)
                    .offset(y: y(from + Double(i * 60)) - 8)
                }
                ForEach(laidOut) { entry in
                    let top = max(y(entry.range.startMinute), padding / 2)
                    let bottom = min(y(entry.range.endMinute), CGFloat(hours) * hour + padding * 1.5)
                    let width = columnsWidth / CGFloat(entry.columns)
                    let highlighted = entry.key == highlightKey
                    let color = Color(hex: entry.item.color)
                    HStack(alignment: entry.item.kind == .event ? .top : .center, spacing: 5) {
                        if entry.item.kind == .reminder {
                            Image(systemName: "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(highlighted ? Color.primary : color)
                        }
                        Text(entry.item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .frame(width: width - 2, height: max(22, bottom - top - 2), alignment: .topLeading)
                    .background {
                        if entry.item.kind == .event {
                            ZStack(alignment: .leading) {
                                color.opacity(0.22)
                                Rectangle().fill(color).frame(width: 3)
                            }
                            .clipShape(.rect(cornerRadius: 5))
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(highlighted ? Theme.fill : .clear)
                                .stroke(highlighted ? Theme.fill : color, lineWidth: 1)
                        }
                    }
                    .offset(x: gutter + CGFloat(entry.column) * width, y: top)
                }
            }
        }
        .frame(height: CGFloat(hours) * hour + padding * 2)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .clipShape(.rect(cornerRadius: 22))
    }
}
#endif
