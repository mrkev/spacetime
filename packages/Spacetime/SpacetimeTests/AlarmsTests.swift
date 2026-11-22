import Foundation
import Testing
@testable import Spacetime

@MainActor
struct AlarmsTests {
    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }

    private func alarm(weekdays: [Int] = [], date: Date? = nil) -> SpacetimeAlarm {
        SpacetimeAlarm(id: UUID(), hour: 7, minute: 30, weekdays: weekdays, date: date, label: "", snooze: true)
    }

    @Test func repeatingAlarmsRingOnTheirWeekdays() {
        // 2026-11-23 is a Monday, 2026-11-22 a Sunday.
        let monday = Dates.date(year: 2026, month: 11, day: 23)
        let sunday = Dates.date(year: 2026, month: 11, day: 22)
        let weekdays = alarm(weekdays: [2, 3, 4, 5, 6])
        #expect(weekdays.rings(on: monday))
        #expect(!weekdays.rings(on: sunday))
    }

    @Test func oneTimeAlarmsRingOnlyOnTheirDay() {
        let date = Dates.date(year: 2026, month: 11, day: 23, hour: 7, minute: 30)
        let once = alarm(date: date)
        #expect(once.rings(on: Dates.date(year: 2026, month: 11, day: 23)))
        #expect(!once.rings(on: Dates.date(year: 2026, month: 11, day: 30)))
        #expect(!alarm().rings(on: date))
    }

    @Test func describesRepeatDaysLikeClock() {
        #expect(SpacetimeAlarm.describe(weekdays: [1, 2, 3, 4, 5, 6, 7], calendar: gregorian) == "Every day")
        #expect(SpacetimeAlarm.describe(weekdays: [6, 2, 4, 3, 5], calendar: gregorian) == "Weekdays")
        #expect(SpacetimeAlarm.describe(weekdays: [7, 1], calendar: gregorian) == "Weekends")
        #expect(SpacetimeAlarm.describe(weekdays: [4, 2], calendar: gregorian) == "Mon, Wed")
    }

    @Test func ordersWeekdaysFromTheCalendarsFirstDay() {
        var monday = gregorian
        monday.firstWeekday = 2
        #expect(SpacetimeAlarm.orderedWeekdays(gregorian) == [1, 2, 3, 4, 5, 6, 7])
        #expect(SpacetimeAlarm.orderedWeekdays(monday) == [2, 3, 4, 5, 6, 7, 1])
        #expect(SpacetimeAlarm.describe(weekdays: [1, 2], calendar: monday) == "Mon, Sun")
    }

    @Test func labelsDefaultToAlarm() {
        var labeled = alarm()
        #expect(labeled.title == "Alarm")
        labeled.label = "Gym"
        #expect(labeled.title == "Gym")
    }
}
