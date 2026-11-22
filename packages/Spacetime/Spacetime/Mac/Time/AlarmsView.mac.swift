#if os(macOS)
import SwiftUI

/// The alarms the app has set, by time, like Clock's list. AlarmKit's alarms aren't in Clock, so this
/// is where they're changed and deleted.
struct AlarmsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AlarmStore.self) private var store

    var body: some View {
        let nav = model.time
        let alarms = store.alarms.sorted { ($0.minuteOfDay, $0.date ?? .distantPast) < ($1.minuteOfDay, $1.date ?? .distantPast) }
        List {
            ForEach(alarms) { alarm in
                Button { model.time.alarmEditor = AlarmEditRequest(alarm: alarm) } label: {
                    AlarmRow(alarm: alarm)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets { store.delete(alarms[index]) }
            }
        }
        .overlay {
            if alarms.isEmpty {
                ContentUnavailableView {
                    Label("No Alarms", systemImage: "alarm")
                } description: {
                    Text("Alarms you set ring like Clock’s, even on Silent.")
                } actions: {
                    Button("New Alarm") { model.time.alarmEditor = AlarmEditRequest() }
                }
            }
        }
        .navigationTitle("Alarms")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Alarm", systemImage: "plus") { nav.alarmEditor = AlarmEditRequest() }
            }
        }
    }
}

private struct AlarmRow: View {
    let alarm: SpacetimeAlarm

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Dates.formatTime(Dates.date(Date(), atMinute: alarm.minuteOfDay)))
                .font(.system(size: 40, weight: .light))
                .monospacedDigit()
            Text([alarm.label.isEmpty ? nil : alarm.label, alarm.describeWhen()].compactMap { $0 }
                .joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
#endif
