import Foundation

/// A span of a day, in minutes from midnight.
nonisolated struct MinuteRange: Hashable, Sendable {
    var startMinute: Double
    var endMinute: Double
}

nonisolated struct PositionedItem<Item>: Identifiable {
    var item: Item
    var key: String
    var range: MinuteRange
    var column: Int
    var columns: Int

    var id: String { key }
}

nonisolated enum TimelineLayout {
    /// Short items still take up this much room by default, so they don't visually collide.
    static let minVisualMinutes: Double = 20

    /// Lays out overlapping items side by side, the way Calendar does: items that overlap form a
    /// cluster, each item takes the first free column, and every item in a cluster shares its width.
    static func layout<Item>(_ items: [(key: String, range: MinuteRange, item: Item)],
                             minVisualMinutes: Double = minVisualMinutes) -> [PositionedItem<Item>] {
        let sorted = items.sorted {
            $0.range.startMinute != $1.range.startMinute
                ? $0.range.startMinute < $1.range.startMinute
                : $0.range.endMinute > $1.range.endMinute
        }
        var result: [PositionedItem<Item>] = []
        var cluster: [PositionedItem<Item>] = []
        var columnEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func flush() {
            for i in cluster.indices { cluster[i].columns = columnEnds.count }
            result.append(contentsOf: cluster)
            cluster = []
            columnEnds = []
        }

        for entry in sorted {
            let visualEnd = max(entry.range.endMinute, entry.range.startMinute + minVisualMinutes)
            if entry.range.startMinute >= clusterEnd { flush() }
            var column = columnEnds.firstIndex { $0 <= entry.range.startMinute } ?? -1
            if column == -1 {
                column = columnEnds.count
                columnEnds.append(visualEnd)
            } else {
                columnEnds[column] = visualEnd
            }
            cluster.append(PositionedItem(item: entry.item, key: entry.key, range: entry.range, column: column,
                                          columns: 1))
            clusterEnd = max(clusterEnd, visualEnd)
        }
        flush()
        return result
    }
}

nonisolated enum DragMode: Hashable, Sendable {
    case move, start, end
}

nonisolated enum Editing {
    /// Drags snap to the quarter hour, like Calendar.
    static let snapMinutes: Double = 15
    private static let dayMinutes: Double = 24 * 60

    static func snap(_ minutes: Double) -> Double {
        (minutes / snapMinutes).rounded() * snapMinutes
    }

    /// Applies a drag of `deltaMinutes` to a range. Moving keeps the duration; resizing keeps at least
    /// one snap interval. Everything stays within the day.
    static func drag(_ range: MinuteRange, mode: DragMode, deltaMinutes: Double) -> MinuteRange {
        let delta = snap(deltaMinutes)
        // Holding still leaves an off-grid event where it is instead of nudging it onto the grid.
        if delta == 0 { return range }
        switch mode {
        case .move:
            let duration = range.endMinute - range.startMinute
            let start = clamp(snap(range.startMinute + delta), 0, dayMinutes - duration)
            return MinuteRange(startMinute: start, endMinute: start + duration)
        case .start:
            return MinuteRange(startMinute: clamp(snap(range.startMinute + delta), 0, range.endMinute - snapMinutes),
                               endMinute: range.endMinute)
        case .end:
            return MinuteRange(startMinute: range.startMinute,
                               endMinute: clamp(snap(range.endMinute + delta), range.startMinute + snapMinutes,
                                                dayMinutes))
        }
    }

    /// Only timed events that fit within one day can be dragged around the timeline.
    static func canDrag(editable: Bool, allDay: Bool, start: Date, end: Date, dayStart: Date) -> Bool {
        guard editable, !allDay else { return false }
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        return start >= dayStart && end <= dayEnd
    }

    /// Shifts an event's dates by how far its range moved on the timeline.
    static func apply(start: Date, end: Date, from: MinuteRange, to: MinuteRange) -> (start: Date, end: Date) {
        (start.addingTimeInterval((to.startMinute - from.startMinute) * 60),
         end.addingTimeInterval((to.endMinute - from.endMinute) * 60))
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, value))
    }
}

extension CalendarEvent {
    func canDrag(on dayStart: Date) -> Bool {
        Editing.canDrag(editable: editable, allDay: allDay, start: start, end: end, dayStart: dayStart)
    }
}

/// Something with a time on a day's timeline.
enum TimelineEntry {
    case event(CalendarEvent)
    case reminder(CalendarReminder)
    case alarm(SpacetimeAlarm)
}

/// A day's items sorted for a timeline: what goes in the all-day area, and the timed items laid out.
struct DayTimeline {
    var allDayEvents: [CalendarEvent] = []
    var allDayReminders: [CalendarReminder] = []
    var timed: [PositionedItem<TimelineEntry>] = []

    /// Events spanning the whole of `day` go in the all-day area with all-day ones; the rest are cut to
    /// the part on this day. Reminders and alarms are moments, laid out as if they took `pointMinutes`
    /// (the room they're drawn in), and short events as if they took `minMinutes`.
    init(day: Date, items: DayItems?, alarms: [SpacetimeAlarm], pointMinutes: Double, minMinutes: Double) {
        let dayStart = Dates.startOfDay(day)
        let dayEnd = Dates.addDays(dayStart, 1)
        var timed: [(key: String, range: MinuteRange, item: TimelineEntry)] = []
        for event in items?.events ?? [] {
            if event.allDay || (event.start <= dayStart && event.end >= dayEnd) {
                allDayEvents.append(event)
                continue
            }
            let start = event.start < dayStart ? 0 : Double(Dates.minutesIntoDay(event.start))
            let end = event.end >= dayEnd ? 24 * 60 : Double(Dates.minutesIntoDay(event.end))
            timed.append((event.key, MinuteRange(startMinute: start, endMinute: end), .event(event)))
        }
        for reminder in items?.reminders ?? [] {
            guard let due = reminder.due, !reminder.allDay else {
                allDayReminders.append(reminder)
                continue
            }
            let start = Double(Dates.minutesIntoDay(due))
            timed.append((reminder.key, MinuteRange(startMinute: start, endMinute: start + pointMinutes),
                          .reminder(reminder)))
        }
        for alarm in alarms {
            let start = Double(alarm.minuteOfDay)
            timed.append(("alarm:\(alarm.id)", MinuteRange(startMinute: start, endMinute: start + pointMinutes),
                          .alarm(alarm)))
        }
        self.timed = TimelineLayout.layout(timed, minVisualMinutes: minMinutes)
    }
}
