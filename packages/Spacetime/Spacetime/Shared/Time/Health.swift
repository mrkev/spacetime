import Foundation
import OSLog
#if os(iOS)
import HealthKit
#endif

/// What the calendar can show from Health, each turned on in Settings.
nonisolated enum HealthKind: String, CaseIterable, Codable, Sendable {
    case sleep, cycle, medications

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .cycle: "Cycle Tracking"
        case .medications: "Medications"
        }
    }
}

/// A night's (or a nap's) sleep: from falling asleep to waking, and how much of that was asleep.
nonisolated struct SleepSession: Hashable, Sendable {
    var start: Date
    var end: Date
    var asleep: TimeInterval
}

/// How heavy a period day's flow was, as logged in Cycle Tracking.
nonisolated enum MenstrualFlow: Int, Comparable, Sendable {
    case unspecified = 1, light, medium, heavy

    var title: String {
        switch self {
        case .unspecified: "Period"
        case .light: "Period · Light"
        case .medium: "Period · Medium"
        case .heavy: "Period · Heavy"
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// A medication dose logged in Health, taken or skipped.
nonisolated struct MedicationDose: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var date: Date
    var taken: Bool
    /// How much was taken, like "2 tablets", if Health knows.
    var amount: String?
}

/// What Health has for a day.
nonisolated struct HealthDay: Equatable, Sendable {
    /// Sleep that overlaps the day, whole (a night's sleep is on both days it touches).
    var sleep: [SleepSession] = []
    var flow: MenstrualFlow?
    var doses: [MedicationDose] = []

    static let empty = HealthDay()
}

/// Which kinds are turned on, saved as JSON.
nonisolated struct HealthSettings: Codable, Equatable, Sendable {
    var enabled: Set<HealthKind> = []
}

nonisolated enum HealthGrouping {
    /// Sleep sessions from samples of time asleep, which may overlap (several sources, like the Watch
    /// and the phone, record the same night) and are split by stage and short wakings. Samples that
    /// overlap are one stretch; stretches less than `maxGap` apart are one session.
    static func sleepSessions(_ intervals: [DateInterval], maxGap: TimeInterval = 60 * 60) -> [SleepSession] {
        var sessions: [SleepSession] = []
        var stretch: DateInterval?
        func close() {
            guard let stretch else { return }
            if var last = sessions.last, stretch.start.timeIntervalSince(last.end) < maxGap {
                last.end = max(last.end, stretch.end)
                last.asleep += stretch.duration
                sessions[sessions.count - 1] = last
            } else {
                sessions.append(SleepSession(start: stretch.start, end: stretch.end, asleep: stretch.duration))
            }
        }
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let current = stretch, interval.start <= current.end {
                stretch = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                close()
                stretch = interval
            }
        }
        close()
        return sessions
    }

    /// The day keys from `start`'s day through the day before `end` (or `start`'s day, for a moment),
    /// within `range`.
    static func dayKeys(from start: Date, to end: Date, within range: DateInterval) -> [String] {
        let lastMoment = max(start, end.addingTimeInterval(-0.001))
        var keys: [String] = []
        var day = Dates.startOfDay(start)
        while day <= lastMoment && day < range.end {
            if day >= Dates.startOfDay(range.start) { keys.append(Dates.dayKey(day)) }
            day = Dates.addDays(day, 1)
        }
        return keys
    }

    /// A month's days, from what was read for it.
    static func days(month: Date, sleep: [SleepSession], flows: [(start: Date, end: Date, flow: MenstrualFlow)],
                     doses: [MedicationDose]) -> [String: HealthDay] {
        let range = DateInterval(start: Dates.startOfMonth(month), end: Dates.addMonths(month, 1))
        var days: [String: HealthDay] = [:]
        for session in sleep {
            for key in dayKeys(from: session.start, to: session.end, within: range) {
                days[key, default: .empty].sleep.append(session)
            }
        }
        for sample in flows {
            for key in dayKeys(from: sample.start, to: sample.end, within: range) {
                days[key, default: .empty].flow = max(days[key]?.flow ?? sample.flow, sample.flow)
            }
        }
        for dose in doses where range.contains(dose.date) {
            days[Dates.dayKey(dose.date), default: .empty].doses.append(dose)
        }
        for key in days.keys { days[key]!.doses.sort { $0.date < $1.date } }
        return days
    }

    /// A dose's amount, like "1 tablet" or "2.5 mL".
    static func amount(_ quantity: Double?, unit: String) -> String? {
        guard let quantity, quantity > 0 else { return nil }
        let number = quantity.formatted(.number.precision(.fractionLength(0...2)))
        let unit = unit == "count" || unit.isEmpty ? (quantity == 1 ? "dose" : "doses") : unit
        return "\(number) \(unit)"
    }
}

/// Sleep, periods, and medication doses from Health, for the calendar. Each kind is read only once it's
/// turned on in Settings. Health doesn't say whether reading was allowed, so a kind that's on but
/// denied just has nothing to show.
@Observable
final class HealthStore {
    private static let settingsKey = "spacetime.health"

    static var isAvailable: Bool {
        #if os(iOS)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    private(set) var settings: HealthSettings
    /// Loaded months' days, by month key and then day key.
    private var months: [String: [String: HealthDay]] = [:]

    @ObservationIgnored private let storage: KeyValueStorage
    @ObservationIgnored private var requested = RecentKeys(limit: 24)
    @ObservationIgnored private var loading = Set<String>()
    @ObservationIgnored private var generation = 0
    #if os(iOS)
    @ObservationIgnored private let store = HKHealthStore()
    #endif

    init(storage: KeyValueStorage) {
        self.storage = storage
        settings = storage.decode(HealthSettings.self, forKey: Self.settingsKey) ?? HealthSettings()
    }

    func isEnabled(_ kind: HealthKind) -> Bool {
        settings.enabled.contains(kind)
    }

    /// Turns a kind on or off. Turning it on asks to read it from Health first, if it hasn't been asked.
    func setEnabled(_ kind: HealthKind, _ on: Bool) async throws {
        if on { try await requestAccess(kind) }
        if on { settings.enabled.insert(kind) } else { settings.enabled.remove(kind) }
        storage.encode(settings, forKey: Self.settingsKey)
        refresh()
    }

    /// Health's own sheet for picking which medications Spacetime can read. It shows every time, so
    /// medications can be added or removed later.
    func chooseMedications() async throws {
        #if os(iOS)
        try await store.requestPerObjectReadAuthorization(for: .userAnnotatedMedicationType(), predicate: nil)
        refresh()
        #endif
    }

    /// What Health has for `date`, or nothing until its month has loaded.
    func day(_ date: Date) -> HealthDay {
        months[Dates.monthKey(date)]?[Dates.dayKey(date)] ?? .empty
    }

    /// Starts reading the months around `date`, unless they're read or being read. They're noted
    /// even with nothing turned on, to read once something is.
    func ensureMonths(_ date: Date, radius: Int = 1) {
        var needed: [Date] = []
        for offset in -radius...radius {
            let month = Dates.addMonths(date, offset)
            let key = Dates.monthKey(month)
            for dropped in requested.use(key) { months[dropped] = nil }
            if months[key] == nil && !settings.enabled.isEmpty && loading.insert(key).inserted { needed.append(month) }
        }
        load(needed)
    }

    /// Reads the loaded months again, as when coming back to the app or changing what's on. What's
    /// showing stays until they're read.
    func refresh() {
        generation += 1
        loading = []
        guard !settings.enabled.isEmpty else {
            months = [:]
            return
        }
        let monthsToRead = requested.keys.compactMap(Dates.parseMonthKey)
        months = months.filter { requested.keys.contains($0.key) }
        load(monthsToRead)
    }

    private func load(_ monthsToRead: [Date]) {
        guard !monthsToRead.isEmpty else { return }
        let generation = generation
        let kinds = settings.enabled
        Task {
            var read: [String: [String: HealthDay]] = [:]
            for month in monthsToRead { read[Dates.monthKey(month)] = await self.read(month: month, kinds: kinds) }
            // A refresh since this began reads these months again.
            guard generation == self.generation else { return }
            loading.subtract(read.keys)
            for (key, days) in read where requested.keys.contains(key) { months[key] = days }
        }
    }

    // MARK: Reading

    #if os(iOS)
    private func requestAccess(_ kind: HealthKind) async throws {
        switch kind {
        case .sleep:
            try await store.requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
        case .cycle:
            try await store.requestAuthorization(toShare: [], read: [HKCategoryType(.menstrualFlow)])
        case .medications:
            try await store.requestPerObjectReadAuthorization(for: .userAnnotatedMedicationType(), predicate: nil)
        }
    }

    private func read(month: Date, kinds: Set<HealthKind>) async -> [String: HealthDay] {
        // A day early and late, for the sleep and periods that cross into the month.
        let start = Dates.addDays(Dates.startOfMonth(month), -1)
        let end = Dates.addDays(Dates.addMonths(month, 1), 1)
        let sleep = kinds.contains(.sleep) ? await readSleep(start, end) : []
        let flows = kinds.contains(.cycle) ? await readFlows(start, end) : []
        let doses = kinds.contains(.medications) ? await readDoses(start, end) : []
        return HealthGrouping.days(month: month, sleep: sleep, flows: flows, doses: doses)
    }

    private func samples(_ type: HKCategoryType, _ start: Date, _ end: Date) async -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(predicates: [.categorySample(type: type, predicate: predicate)],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            return try await query.result(for: store)
        } catch {
            Log.health.error("Couldn’t read \(type.identifier, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func readSleep(_ start: Date, _ end: Date) async -> [SleepSession] {
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let intervals = await samples(HKCategoryType(.sleepAnalysis), start, end)
            .filter { asleep.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
        return HealthGrouping.sleepSessions(intervals)
    }

    private func readFlows(_ start: Date, _ end: Date) async -> [(start: Date, end: Date, flow: MenstrualFlow)] {
        // "None" (5) is logged to say there was no flow that day.
        await samples(HKCategoryType(.menstrualFlow), start, end).compactMap { sample in
            MenstrualFlow(rawValue: sample.value).map { (sample.startDate, sample.endDate, $0) }
        }
    }

    private func readDoses(_ start: Date, _ end: Date) async -> [MedicationDose] {
        var names: [HKHealthConceptIdentifier: String] = [:]
        do {
            for medication in try await HKUserAnnotatedMedicationQueryDescriptor().result(for: store) {
                names[medication.medication.identifier] = medication.nickname ?? medication.medication.displayText
            }
        } catch {
            Log.health.error("Couldn’t read medications: \(String(describing: error), privacy: .public)")
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKObjectType.medicationDoseEventType(), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples: [HKSample]
        do {
            samples = try await query.result(for: store)
        } catch {
            Log.health.error("Couldn’t read doses: \(String(describing: error), privacy: .public)")
            return []
        }
        return samples.compactMap { sample in
            guard let dose = sample as? HKMedicationDoseEvent,
                  dose.logStatus == .taken || dose.logStatus == .skipped else { return nil }
            return MedicationDose(
                id: dose.uuid.uuidString,
                name: names[dose.medicationConceptIdentifier] ?? "Medication",
                date: dose.startDate, taken: dose.logStatus == .taken,
                amount: HealthGrouping.amount(dose.doseQuantity ?? dose.scheduledDoseQuantity,
                                              unit: dose.unit.unitString))
        }
    }
    #else
    private func requestAccess(_ kind: HealthKind) async throws {}

    private func read(month: Date, kinds: Set<HealthKind>) async -> [String: HealthDay] { [:] }
    #endif
}
