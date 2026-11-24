import Foundation
import Testing
@testable import Spacetime

@MainActor
struct HealthTests {
    private let day = Dates.date(year: 2026, month: 11, day: 21)

    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Dates.date(Dates.addDays(day, dayOffset), atMinute: hour * 60 + minute)
    }

    private func interval(_ start: Date, _ end: Date) -> DateInterval {
        DateInterval(start: start, end: end)
    }

    @Test func mergesOverlappingSleepFromSeveralSourcesWithoutCountingItTwice() {
        let sessions = HealthGrouping.sleepSessions([
            interval(at(-1, 23), at(0, 3)),
            interval(at(0, 1), at(0, 6)),
            interval(at(-1, 23, 30), at(0, 2)),
        ])
        #expect(sessions == [SleepSession(start: at(-1, 23), end: at(0, 6), asleep: 7 * 3600)])
    }

    @Test func joinsShortWakingsButNotNaps() {
        let sessions = HealthGrouping.sleepSessions([
            interval(at(-1, 23), at(0, 3)),
            // Awake for 20 minutes.
            interval(at(0, 3, 20), at(0, 7)),
            // A nap in the afternoon.
            interval(at(0, 14), at(0, 14, 30)),
        ])
        #expect(sessions.count == 2)
        #expect(sessions[0] == SleepSession(start: at(-1, 23), end: at(0, 7), asleep: 4 * 3600 + 220 * 60))
        #expect(sessions[1].asleep == 30 * 60)
    }

    @Test func putsANightOnBothDaysItTouches() {
        let night = SleepSession(start: at(-1, 23), end: at(0, 7), asleep: 8 * 3600)
        let days = HealthGrouping.days(month: day, sleep: [night], flows: [], doses: [])
        #expect(days[Dates.dayKey(at(-1, 0))]?.sleep == [night])
        #expect(days[Dates.dayKey(day)]?.sleep == [night])
        #expect(days[Dates.dayKey(at(1, 0))] == nil)
    }

    @Test func keepsTheHeaviestFlowOfADay() {
        let days = HealthGrouping.days(month: day, sleep: [], flows: [
            (at(0, 0), at(1, 0), .light),
            (at(0, 9), at(0, 9), .heavy),
            (at(1, 0), at(2, 0), .medium),
        ], doses: [])
        #expect(days[Dates.dayKey(day)]?.flow == .heavy)
        #expect(days[Dates.dayKey(at(1, 0))]?.flow == .medium)
    }

    @Test func leavesOutWhatsOutsideTheMonth() {
        let dose = MedicationDose(id: "a", name: "Ibuprofen", date: Dates.date(year: 2026, month: 12, day: 1, hour: 8),
                                  taken: true)
        let night = SleepSession(start: Dates.date(year: 2026, month: 11, day: 30, hour: 23),
                                 end: Dates.date(year: 2026, month: 12, day: 1, hour: 7), asleep: 8 * 3600)
        let days = HealthGrouping.days(month: day, sleep: [night], flows: [], doses: [dose])
        #expect(Array(days.keys) == [Dates.dayKey(Dates.date(year: 2026, month: 11, day: 30))])
    }

    @Test func describesDoseAmounts() {
        #expect(HealthGrouping.amount(1, unit: "count") == "1 dose")
        #expect(HealthGrouping.amount(2.5, unit: "mL") == "2.5 mL")
        #expect(HealthGrouping.amount(nil, unit: "mg") == nil)
    }

    @Test func cutsSleepToTheDayAndLaysOutDosesAsMoments() {
        let night = SleepSession(start: at(-1, 23), end: at(0, 7), asleep: 8 * 3600)
        let dose = MedicationDose(id: "a", name: "Ibuprofen", date: at(0, 8), taken: true)
        let health = HealthDay(sleep: [night], flow: .light, doses: [dose])
        let timeline = DayTimeline(day: day, items: nil, alarms: [], health: health, pointMinutes: 30, minMinutes: 20)
        #expect(timeline.sleep.map(\.range) == [MinuteRange(startMinute: 0, endMinute: 7 * 60)])
        #expect(timeline.timed.map(\.key) == ["dose:a"])
        #expect(timeline.timed.first?.range == MinuteRange(startMinute: 480, endMinute: 510))
        #expect(timeline.flow == .light)
    }

    @Test func savesWhatsTurnedOn() async throws {
        let storage = MemoryStorage()
        let store = HealthStore(storage: storage)
        #expect(!store.isEnabled(.sleep))
        // Turning a kind off doesn't ask Health for anything.
        try await store.setEnabled(.sleep, false)
        storage.encode(HealthSettings(enabled: [.sleep, .cycle]), forKey: "spacetime.health")
        let reopened = HealthStore(storage: storage)
        #expect(reopened.isEnabled(.sleep) && reopened.isEnabled(.cycle) && !reopened.isEnabled(.medications))
    }
}
