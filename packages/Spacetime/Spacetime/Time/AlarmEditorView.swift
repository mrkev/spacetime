import SwiftUI

/// Sets or changes an alarm: its time, the days it repeats on (or the day it rings once), its label, and
/// whether it snoozes.
struct AlarmEditorView: View {
    /// The alarm to change, or nil for a new one.
    var alarm: SpacetimeAlarm?

    @Environment(AlarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var day: Date
    /// A new alarm without a given day rings at the next time it comes round, until a day is picked.
    @State private var dayChosen: Bool
    @State private var weekdays: Set<Int>
    @State private var label: String
    @State private var snooze: Bool
    @State private var saving = false

    init(alarm: SpacetimeAlarm? = nil, day: Date? = nil) {
        self.alarm = alarm
        let start = alarm.map { Dates.date(Date(), atMinute: $0.minuteOfDay) }
            ?? TimeActions.defaultStart(on: day)
        _time = State(initialValue: start)
        _day = State(initialValue: Dates.startOfDay(alarm?.date ?? day ?? start))
        _dayChosen = State(initialValue: alarm != nil || day != nil)
        _weekdays = State(initialValue: Set(alarm?.weekdays ?? []))
        _label = State(initialValue: alarm?.label ?? "")
        _snooze = State(initialValue: alarm?.snooze ?? true)
    }

    private var minuteOfDay: Int { Dates.minutesIntoDay(time) }

    /// When an alarm that rings once would ring.
    private var ringsAt: Date { Dates.date(day, atMinute: minuteOfDay) }

    var body: some View {
        Form {
            Section {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    #if os(iOS)
                    .datePickerStyle(.wheel)
                    #endif
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
            Section {
                WeekdayPicker(selection: $weekdays.animation())
                if weekdays.isEmpty {
                    DatePicker("Day", selection: dayBinding, displayedComponents: .date)
                }
            } header: {
                Text("Repeat")
            } footer: {
                Text(weekdays.isEmpty
                     ? "Rings once, \(Dates.formatRelativeDay(ringsAt).lowercased()) at \(Dates.formatTime(ringsAt))."
                     : "Rings \(SpacetimeAlarm.describe(weekdays: Array(weekdays)).lowercased()).")
            }
            Section {
                TextField("Label", text: $label)
                Toggle("Snooze", isOn: $snooze)
            } footer: {
                if snooze { Text("Snooze rings again in \(AlarmStore.snoozeMinutes) minutes.") }
            }
            if let alarm {
                Section {
                    Button("Delete Alarm", role: .destructive) {
                        store.delete(alarm)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(alarm == nil ? "New Alarm" : "Edit Alarm")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(alarm == nil ? "Add" : "Done", role: .confirmIfAvailable, action: save)
                    .disabled(saving)
            }
        }
        .onChange(of: time) {
            // Until a day is picked, a new alarm rings the next time its time comes round.
            guard !dayChosen else { return }
            let today = Dates.startOfDay(Date())
            day = Dates.date(today, atMinute: minuteOfDay) > Date() ? today : Dates.addDays(today, 1)
        }
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { day }, set: { day = Dates.startOfDay($0); dayChosen = true })
    }

    private func save() {
        let calendar = Calendar.current
        let saved = SpacetimeAlarm(
            id: alarm?.id ?? UUID(),
            hour: calendar.component(.hour, from: time),
            minute: calendar.component(.minute, from: time),
            weekdays: weekdays.sorted(),
            date: weekdays.isEmpty ? ringsAt : nil,
            label: label.trimmingCharacters(in: .whitespaces),
            snooze: snooze)
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.save(saved)
                dismiss()
            } catch AlarmError.notAllowed {
                Presenter.alert(title: "Alarms Are Off", message: AlarmError.notAllowed.errorDescription)
            } catch {
                Presenter.showError("Couldn’t Set Alarm", error)
            }
        }
    }
}

/// The days of the week, as a row of circles to turn on and off, like Clock's repeat days.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        HStack(spacing: 6) {
            ForEach(SpacetimeAlarm.orderedWeekdays(calendar), id: \.self) { weekday in
                let on = selection.contains(weekday)
                Button {
                    if on { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(on ? Color.white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(on ? Theme.alarm : Theme.fill, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
