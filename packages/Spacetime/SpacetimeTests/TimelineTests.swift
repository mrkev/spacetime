import Foundation
import Testing
@testable import Spacetime

@MainActor
struct LayoutTests {
    private func item(_ key: String, _ start: Double, _ end: Double) -> (key: String, range: MinuteRange, item: String) {
        (key, MinuteRange(startMinute: start, endMinute: end), key)
    }

    private func byKey(_ items: [PositionedItem<String>]) -> [String: PositionedItem<String>] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
    }

    @Test func givesNonOverlappingItemsTheFullWidth() {
        let result = byKey(TimelineLayout.layout([item("a", 540, 600), item("b", 600, 660)]))
        #expect(result["a"]!.column == 0 && result["a"]!.columns == 1)
        #expect(result["b"]!.column == 0 && result["b"]!.columns == 1)
    }

    @Test func placesOverlappingItemsSideBySide() {
        let result = byKey(TimelineLayout.layout([item("a", 540, 660), item("b", 570, 630)]))
        #expect(result["a"]!.column == 0 && result["a"]!.columns == 2)
        #expect(result["b"]!.column == 1 && result["b"]!.columns == 2)
    }

    @Test func reusesAFreedColumnWithinTheSameCluster() {
        // a spans the whole cluster; b ends before c starts, so c can take b's column.
        let result = byKey(TimelineLayout.layout([item("a", 540, 720), item("b", 540, 600), item("c", 610, 700)]))
        #expect(result["a"]!.columns == 2)
        #expect(result["b"]!.column == 1)
        #expect(result["c"]!.column == 1)
    }

    @Test func keepsSeparateClustersIndependent() {
        let result = byKey(TimelineLayout.layout([item("a", 540, 600), item("b", 550, 600), item("c", 800, 860)]))
        #expect(result["a"]!.columns == 2)
        #expect(result["c"]!.column == 0 && result["c"]!.columns == 1)
    }

    @Test func treatsVeryShortItemsAsIfTheyHadAMinimumHeight() {
        // A 5-minute item would visually overlap one starting 10 minutes later.
        let result = byKey(TimelineLayout.layout([item("a", 540, 545), item("b", 550, 600)]))
        #expect(result["a"]!.columns == 2)
    }

    @Test func putsLongerItemsFirstWhenTheyStartTogether() {
        let result = byKey(TimelineLayout.layout([item("short", 540, 570), item("long", 540, 660)]))
        #expect(result["long"]!.column == 0)
        #expect(result["short"]!.column == 1)
    }

    @Test func givesShortItemsRoomForTheirDrawnHeightWhenZoomedOut() {
        // Five-minute items ten minutes apart only collide once their minimum height covers the gap.
        let items = [item("a", 540, 545), item("b", 550, 555)]
        let narrow = byKey(TimelineLayout.layout(items, minVisualMinutes: 5))
        #expect(narrow["b"]!.column == 0 && narrow["b"]!.columns == 1)
        let wide = byKey(TimelineLayout.layout(items, minVisualMinutes: 30))
        #expect(wide["b"]!.column == 1 && wide["b"]!.columns == 2)
    }
}

@MainActor
struct EditingTests {
    private let nineToTen = MinuteRange(startMinute: 9 * 60, endMinute: 10 * 60)

    private func range(_ start: Double, _ end: Double) -> MinuteRange {
        MinuteRange(startMinute: start, endMinute: end)
    }

    @Test func roundsToTheNearestQuarterHour() {
        #expect(Editing.snap(7) == 0)
        #expect(Editing.snap(8) == 15)
        #expect(Editing.snap(-8) == -15)
        #expect(Editing.snap(52) == 45)
    }

    @Test func movesAnEventAndKeepsItsDuration() {
        #expect(Editing.drag(nineToTen, mode: .move, deltaMinutes: 50) == range(9 * 60 + 45, 10 * 60 + 45))
    }

    @Test func keepsMovedEventsWithinTheDay() {
        #expect(Editing.drag(nineToTen, mode: .move, deltaMinutes: -24 * 60) == range(0, 60))
        #expect(Editing.drag(nineToTen, mode: .move, deltaMinutes: 24 * 60) == range(23 * 60, 24 * 60))
    }

    @Test func resizesEitherEdgeWithoutInvertingTheEvent() {
        #expect(Editing.drag(nineToTen, mode: .start, deltaMinutes: -30) == range(8 * 60 + 30, 10 * 60))
        #expect(Editing.drag(nineToTen, mode: .start, deltaMinutes: 120) == range(9 * 60 + 45, 10 * 60))
        #expect(Editing.drag(nineToTen, mode: .end, deltaMinutes: 15) == range(9 * 60, 10 * 60 + 15))
        #expect(Editing.drag(nineToTen, mode: .end, deltaMinutes: -120) == range(9 * 60, 9 * 60 + 15))
    }

    @Test func snapsOffGridEventsOntoTheGridOnceTheyMove() {
        let offGrid = range(9 * 60 + 10, 9 * 60 + 40)
        #expect(Editing.drag(offGrid, mode: .move, deltaMinutes: 4) == offGrid)
        #expect(Editing.drag(offGrid, mode: .move, deltaMinutes: 15) == range(9 * 60 + 30, 10 * 60))
    }

    @Test func allowsOnlyTimedEditableEventsWithinTheDay() {
        let day = Dates.date(year: 2026, month: 10, day: 28)
        func at(_ hour: Int, _ dayOfMonth: Int = 28) -> Date { Dates.date(year: 2026, month: 10, day: dayOfMonth, hour: hour) }
        func can(_ start: Date, _ end: Date, editable: Bool = true, allDay: Bool = false) -> Bool {
            Editing.canDrag(editable: editable, allDay: allDay, start: start, end: end, dayStart: day)
        }
        #expect(can(at(9), at(10)))
        #expect(can(at(23), at(0, 29)))
        #expect(!can(at(9), at(10), editable: false))
        #expect(!can(at(0), at(0, 29), allDay: true))
        #expect(!can(at(22, 27), at(1)))
    }

    @Test func shiftsTheDatesByHowFarEachEdgeMoved() {
        let start = Dates.date(year: 2026, month: 10, day: 28, hour: 9)
        let end = Dates.date(year: 2026, month: 10, day: 28, hour: 10)
        let moved = Editing.apply(start: start, end: end, from: nineToTen, to: range(9 * 60 + 30, 11 * 60))
        #expect(moved.start == Dates.date(year: 2026, month: 10, day: 28, hour: 9, minute: 30))
        #expect(moved.end == Dates.date(year: 2026, month: 10, day: 28, hour: 11))
    }
}

@MainActor
struct DayTimelineTests {
    private let day = Dates.date(year: 2026, month: 11, day: 21)

    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Dates.date(Dates.addDays(day, dayOffset), atMinute: hour * 60 + minute)
    }

    private func event(_ key: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(key: key, title: key, start: start, end: end, allDay: allDay, color: "#FF3B30",
                      calendarTitle: "Home", editable: true, recurring: false, eventId: key, calendarId: "home")
    }

    private func reminder(_ key: String, due: Date, allDay: Bool = false) -> CalendarReminder {
        CalendarReminder(key: key, title: key, due: due, allDay: allDay, completed: false, color: "#FF9500",
                         listTitle: "Reminders")
    }

    private func split(_ events: [CalendarEvent], _ reminders: [CalendarReminder] = [],
                       alarms: [SpacetimeAlarm] = []) -> DayTimeline {
        DayTimeline(day: day, items: DayItems(events: events, reminders: reminders), alarms: alarms,
                    pointMinutes: 30, minMinutes: 20)
    }

    private func range(_ timeline: DayTimeline, _ key: String) -> MinuteRange? {
        timeline.timed.first { $0.key == key }?.range
    }

    @Test func putsAllDayEventsAndEventsSpanningTheDayInTheAllDayArea() {
        let timeline = split([event("flagged", day, at(1, 0), allDay: true),
                              event("trip", at(-1, 9), at(2, 9)),
                              event("lunch", at(0, 12), at(0, 13))])
        #expect(timeline.allDayEvents.map(\.key) == ["flagged", "trip"])
        #expect(timeline.timed.map(\.key) == ["lunch"])
    }

    @Test func cutsEventsToThePartOnThisDay() {
        let timeline = split([event("late", at(-1, 22), at(0, 2)), event("party", at(0, 21), at(1, 3))])
        #expect(range(timeline, "late") == MinuteRange(startMinute: 0, endMinute: 120))
        #expect(range(timeline, "party") == MinuteRange(startMinute: 21 * 60, endMinute: 24 * 60))
    }

    @Test func givesRemindersAndAlarmsTheRoomTheyreDrawnIn() {
        let alarm = SpacetimeAlarm(id: UUID(), hour: 7, minute: 30, weekdays: [], date: day, label: "",
                                   snooze: true)
        let timeline = split([], [reminder("call", due: at(0, 9)), reminder("someday", due: day, allDay: true)],
                             alarms: [alarm])
        #expect(range(timeline, "call") == MinuteRange(startMinute: 540, endMinute: 570))
        #expect(range(timeline, "alarm:\(alarm.id)") == MinuteRange(startMinute: 450, endMinute: 480))
        #expect(timeline.allDayReminders.map(\.key) == ["someday"])
    }

    @Test func treatsAMissingDayAsEmpty() {
        let timeline = DayTimeline(day: day, items: nil, alarms: [], pointMinutes: 30, minMinutes: 20)
        #expect(timeline.allDayEvents.isEmpty && timeline.allDayReminders.isEmpty && timeline.timed.isEmpty)
    }
}

@MainActor
struct TimelineGestureTests {
    @Test func dragsABlockByWholeQuarterHoursOfFingerTravel() {
        let drag = BlockDrag(mode: .move, origin: MinuteRange(startMinute: 540, endMinute: 600), startY: 300)
        // 60 points an hour: 32 points is 32 minutes, which snaps to 30.
        #expect(drag.range(atY: 332, hourHeight: 60) == MinuteRange(startMinute: 570, endMinute: 630))
        #expect(drag.range(atY: 305, hourHeight: 60) == MinuteRange(startMinute: 540, endMinute: 600))
        let end = BlockDrag(mode: .end, origin: MinuteRange(startMinute: 540, endMinute: 600), startY: 300)
        #expect(end.range(atY: 330, hourHeight: 60) == MinuteRange(startMinute: 540, endMinute: 630))
    }

    @Test func keepsTheMinuteUnderTheFingersWhilePinching() {
        let pinch = TimelinePinch(hourHeight: 60, scrollY: 400, focalY: 200)
        let height = pinch.hourHeight(scale: 2)
        #expect(height == 120)
        let minuteUnderFingers = (pinch.scrollY(hourHeight: height) + 200 - Timeline.padding) / height * 60
        #expect(abs(Double(minuteUnderFingers) - pinch.minute) < 0.001)
    }

    @Test func zoomsOnlyWithinTheLimits() {
        let pinch = TimelinePinch(hourHeight: 60, scrollY: 0, focalY: 0)
        #expect(pinch.hourHeight(scale: 10) == Timeline.maxHourHeight)
        #expect(pinch.hourHeight(scale: 0.1) == Timeline.minHourHeight)
    }

    @Test func keepsTheTimeAtTheTopWhenTheHoursChangeHeight() {
        // 9 AM at the top at 60 points an hour is still at the top at 30.
        let y = Timeline.padding + 9 * 60
        #expect(Timeline.scrollY(y, rescaledFrom: 60, to: 30) == Timeline.padding + 9 * 30)
    }
}
