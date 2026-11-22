import CoreGraphics
import Foundation
import Testing
@testable import Spacetime

@MainActor
struct DatesTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Dates.date(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    @Test func roundTripsDayKeysInLocalTime() {
        let day = date(2026, 10, 26)
        #expect(Dates.dayKey(day) == "2026-10-26")
        #expect(Dates.parseDayKey("2026-10-26") == day)
        #expect(Dates.parseDayKey("not a date") == nil)
        #expect(Dates.parseDayKey(nil) == nil)
    }

    @Test func roundTripsMonthKeysToTheFirstOfTheMonth() {
        #expect(Dates.monthKey(date(2027, 3, 15)) == "2027-03")
        #expect(Dates.parseMonthKey("2027-03") == date(2027, 3, 1))
        #expect(Dates.parseMonthKey("2027-03-15") == nil)
        #expect(Dates.parseMonthKey(nil) == nil)
    }

    @Test func addsDaysAcrossMonthAndYearBoundaries() {
        #expect(Dates.dayKey(Dates.addDays(date(2026, 12, 31), 1)) == "2027-01-01")
        #expect(Dates.dayKey(Dates.addDays(date(2026, 3, 1), -1)) == "2026-02-28")
    }

    @Test func keepsTheTimeOfDayWhenAddingDays() {
        let next = Dates.addDays(date(2026, 3, 7, 9, 30), 1)
        #expect(Calendar.current.component(.hour, from: next) == 9)
        #expect(Calendar.current.component(.minute, from: next) == 30)
    }

    @Test func findsTheStartOfTheWeek() {
        // Oct 28 2026 is a Wednesday.
        #expect(Dates.dayKey(Dates.startOfWeek(date(2026, 10, 28))) == "2026-10-25")
        #expect(Dates.dayKey(Dates.startOfWeek(date(2026, 10, 28), weekStartsOn: 1)) == "2026-10-26")
        #expect(Dates.dayKey(Dates.startOfWeek(date(2026, 10, 25))) == "2026-10-25")
    }

    @Test func countsCalendarDaysAndMonthsBetweenDates() {
        #expect(Dates.differenceInDays(date(2026, 1, 1, 23), date(2026, 1, 2, 1)) == 1)
        #expect(Dates.differenceInDays(date(2026, 1, 10), date(2026, 1, 1)) == -9)
        #expect(Dates.differenceInMonths(date(2026, 11, 30), date(2027, 2, 1)) == 3)
    }

    @Test func knowsMonthLengths() {
        #expect(Dates.daysInMonth(date(2028, 2, 1)) == 29)
        #expect(Dates.daysInMonth(date(2026, 2, 1)) == 28)
        #expect(Dates.daysInMonth(date(2026, 10, 1)) == 31)
    }

    @Test func comparesDaysIgnoringTime() {
        #expect(Dates.isSameDay(date(2026, 10, 26, 1), date(2026, 10, 26, 23)))
        #expect(!Dates.isSameDay(date(2026, 10, 26), date(2026, 10, 27)))
    }

    @Test func measuresMinutesIntoTheDay() {
        #expect(Dates.minutesIntoDay(date(2026, 1, 1, 13, 45)) == 825)
    }

    @Test func producesSevenWeekdayLabels() {
        #expect(Dates.weekdayLabels().count == 7)
    }

    @Test func describesNearbyDaysRelatively() {
        let now = date(2026, 10, 26, 12)
        #expect(Dates.formatRelativeDay(date(2026, 10, 26, 20), now: now) == "Today")
        #expect(Dates.formatRelativeDay(date(2026, 10, 27, 8), now: now) == "Tomorrow")
        #expect(Dates.formatRelativeDay(date(2026, 10, 25, 8), now: now) == "Yesterday")
    }
}

@MainActor
struct GeoTests {
    @Test func isZeroForTheSamePoint() {
        let point = Coordinate(latitude: 19.4326, longitude: -99.1332)
        #expect(Geo.distanceMeters(point, point) == 0)
    }

    @Test func matchesAKnownDistance() {
        // San Francisco to Los Angeles is about 559 km.
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let la = Coordinate(latitude: 34.0522, longitude: -118.2437)
        #expect(abs(Geo.distanceMeters(sf, la) / 1000 - 559) < 5)
    }

    @Test func formatsDistances() {
        #expect(Geo.formatDistance(250.4) == "250 m")
        #expect(Geo.formatDistance(1500) == "1.5 km")
        #expect(Geo.formatDistance(12_345) == "12 km")
    }

    @Test func readsHexColors() {
        let c = Hex.components("#FF9500")!
        #expect(c.r == 1 && abs(c.g - 149.0 / 255) < 0.001 && c.b == 0)
        #expect(Hex.components("#fff")!.g == 1)
        #expect(Hex.components("nope") == nil)
        #expect(Hex.string(from: CGColor(srgbRed: 1, green: 149.0 / 255, blue: 0, alpha: 1)) == "#FF9500")
    }
}
