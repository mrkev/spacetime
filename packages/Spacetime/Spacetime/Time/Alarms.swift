import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
import AppIntents
#endif

/// An alarm set with AlarmKit, which rings like Clock's: full screen, through Silent and Focus. AlarmKit
/// only keeps an alarm's schedule (and only on the iPhone; the Mac has no alarms), so the app keeps the
/// rest: its label and whether it snoozes.
nonisolated struct SpacetimeAlarm: Codable, Identifiable, Hashable {
    var id: UUID
    var hour: Int
    var minute: Int
    /// The days of the week it rings on, 1 for Sunday through 7 for Saturday like `Calendar`'s weekdays.
    /// Empty for an alarm that rings once.
    var weekdays: [Int]
    /// When an alarm that rings once rings.
    var date: Date?
    var label: String
    var snooze: Bool

    var repeats: Bool { !weekdays.isEmpty }
    var minuteOfDay: Int { hour * 60 + minute }
    var title: String { label.trimmingCharacters(in: .whitespaces).isEmpty ? "Alarm" : label }

    /// Whether it rings on `day`.
    func rings(on day: Date, calendar: Calendar = .current) -> Bool {
        if repeats { return weekdays.contains(calendar.component(.weekday, from: day)) }
        guard let date else { return false }
        return calendar.isDate(date, inSameDayAs: day)
    }

    /// When it rings, for lists: the days it repeats on, or the day it rings.
    func describeWhen(calendar: Calendar = .current, now: Date = Date()) -> String {
        if repeats { return Self.describe(weekdays: weekdays, calendar: calendar) }
        return date.map { Dates.formatRelativeDay($0, now: now) } ?? ""
    }

    /// Like Clock: "Every day", "Weekdays", "Weekends", or the days' short names in week order.
    static func describe(weekdays: [Int], calendar: Calendar = .current) -> String {
        let days = Set(weekdays)
        if days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        return orderedWeekdays(calendar).filter(days.contains)
            .map { calendar.shortWeekdaySymbols[$0 - 1] }
            .joined(separator: ", ")
    }

    /// The weekdays in the order the week is shown, starting on the calendar's first day.
    static func orderedWeekdays(_ calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

enum AlarmError: LocalizedError {
    case notAllowed
    case inThePast

    var errorDescription: String? {
        switch self {
        case .notAllowed: "Spacetime isn’t allowed to set alarms. You can allow it in Settings."
        case .inThePast: "That time has already passed. Choose a later time or another day."
        }
    }
}

/// The alarms the app has set.
@Observable
final class AlarmStore {
    static let shared = AlarmStore()
    private static let storageKey = "spacetime.alarms"
    /// How long Snooze puts an alarm off, like Clock.
    static let snoozeMinutes = 9

    /// Whether this device can set alarms (the iPhone can; the Mac can't).
    static var isSupported: Bool {
        #if canImport(AlarmKit)
        true
        #else
        false
        #endif
    }

    private(set) var alarms: [SpacetimeAlarm]
    private let storage: KeyValueStorage

    init(storage: KeyValueStorage = FileStorage.shared) {
        self.storage = storage
        alarms = storage.decode([SpacetimeAlarm].self, forKey: Self.storageKey) ?? []
        #if canImport(AlarmKit)
        // Alarms that rang once are gone from AlarmKit once they're stopped; drop them here too.
        Task { [weak self] in
            for await scheduled in AlarmManager.shared.alarmUpdates { self?.reconcile(scheduled) }
        }
        #endif
    }

    /// Alarms that ring on `day`, by time.
    func alarms(on day: Date) -> [SpacetimeAlarm] {
        alarms.filter { $0.rings(on: day) }.sorted { $0.minuteOfDay < $1.minuteOfDay }
    }

    /// Sets an alarm, or changes one that's set. Throws if it can't be set.
    func save(_ alarm: SpacetimeAlarm) async throws {
        #if canImport(AlarmKit)
        if !alarm.repeats, let date = alarm.date, date <= Date() { throw AlarmError.inThePast }
        let manager = AlarmManager.shared
        if manager.authorizationState != .authorized {
            guard (try? await manager.requestAuthorization()) == .authorized else { throw AlarmError.notAllowed }
        }
        // AlarmKit has no way to change an alarm, so replace it, keeping its ID.
        try? manager.cancel(id: alarm.id)
        _ = try await manager.schedule(id: alarm.id, configuration: Self.configuration(for: alarm))
        store(alarm)
        #endif
    }

    func delete(_ alarm: SpacetimeAlarm) {
        #if canImport(AlarmKit)
        try? AlarmManager.shared.cancel(id: alarm.id)
        #endif
        alarms.removeAll { $0.id == alarm.id }
        persist()
    }

    /// Stops a ringing alarm and sets one that rings again in a few minutes, with the same label.
    func snooze(_ id: UUID) async {
        #if canImport(AlarmKit)
        try? AlarmManager.shared.stop(id: id)
        let original = alarms.first { $0.id == id }
        let date = Date().addingTimeInterval(TimeInterval(Self.snoozeMinutes * 60))
        let calendar = Calendar.current
        let again = SpacetimeAlarm(id: UUID(), hour: calendar.component(.hour, from: date),
                                   minute: calendar.component(.minute, from: date), weekdays: [], date: date,
                                   label: original?.label ?? "", snooze: true)
        try? await save(again)
        #endif
    }

    private func store(_ alarm: SpacetimeAlarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        persist()
    }

    private func persist() {
        storage.encode(alarms, forKey: Self.storageKey)
    }

    #if canImport(AlarmKit)
    /// Keeps only the alarms AlarmKit still has, and lets go of ones that rang once and are past.
    private func reconcile(_ scheduled: [Alarm]) {
        let ringing = Dictionary(scheduled.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
        let stale = Date().addingTimeInterval(-60)
        let kept = alarms.filter { alarm in
            guard let state = ringing[alarm.id] else { return false }
            if !alarm.repeats, let date = alarm.date, date < stale, state != .alerting {
                try? AlarmManager.shared.cancel(id: alarm.id)
                return false
            }
            return true
        }
        guard kept != alarms else { return }
        alarms = kept
        persist()
    }

    private static func configuration(for alarm: SpacetimeAlarm) -> AlarmManager.AlarmConfiguration<AlarmInfo> {
        let schedule: Alarm.Schedule
        if alarm.repeats {
            let days = alarm.weekdays.sorted().compactMap(localeWeekday)
            schedule = .relative(.init(time: .init(hour: alarm.hour, minute: alarm.minute), repeats: .weekly(days)))
        } else {
            schedule = .fixed(alarm.date ?? Date())
        }
        let snooze = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: alarm.title),
                                            secondaryButton: alarm.snooze ? snooze : nil,
                                            secondaryButtonBehavior: alarm.snooze ? .custom : nil)
        let attributes = AlarmAttributes<AlarmInfo>(presentation: AlarmPresentation(alert: alert),
                                                    tintColor: Theme.alarm)
        return .alarm(schedule: schedule, attributes: attributes,
                      secondaryIntent: alarm.snooze ? SnoozeAlarmIntent(alarmID: alarm.id) : nil)
    }

    nonisolated private static func localeWeekday(_ weekday: Int) -> Locale.Weekday? {
        switch weekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
    #endif
}

#if canImport(AlarmKit)
/// What AlarmKit keeps with an alarm for its presentation; the app keeps its details itself.
nonisolated struct AlarmInfo: AlarmMetadata {}

/// The Snooze button on a ringing alarm. Snoozing with AlarmKit's own countdown would need a Live
/// Activity (a widget extension) to show it, so this sets a new alarm instead.
struct SnoozeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze Alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { await AlarmStore.shared.snooze(id) }
        return .result()
    }
}
#endif

/// The alarm editor to show: a new alarm (on `day`, if given) or an existing one.
struct AlarmEditRequest: Identifiable {
    let id = UUID()
    var alarm: SpacetimeAlarm?
    var day: Date?
}
