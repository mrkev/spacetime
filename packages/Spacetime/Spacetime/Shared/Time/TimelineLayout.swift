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
    /// Which of its group's side-by-side columns it's in, and how many there are.
    var column: Int
    var columns: Int
    /// How many items that started well before it it's drawn over at their left edge, each indenting
    /// it a little so their edges stay in sight.
    var depth = 0

    var id: String { key }
}

nonisolated enum TimelineLayout {
    /// Short items still take up this much room by default, so they don't visually collide.
    static let minVisualMinutes: Double = 20

    /// Lays out overlapping items the way Calendar does. Items that overlap and start within
    /// `stackMinutes` of each other are a group, side by side: each takes the first free column, and
    /// they share the width. An item starting later than that, once the earlier one's title is in
    /// sight, is drawn over it instead, as wide as its own group, and indented by its `depth`.
    ///
    /// The result is in order of start, so later items are drawn over earlier ones.
    static func layout<Item>(_ items: [(key: String, range: MinuteRange, item: Item)],
                             minVisualMinutes: Double = minVisualMinutes,
                             stackMinutes: Double = .infinity) -> [PositionedItem<Item>] {
        let sorted = items.sorted {
            $0.range.startMinute != $1.range.startMinute
                ? $0.range.startMinute < $1.range.startMinute
                : $0.range.endMinute > $1.range.endMinute
        }
        let starts = sorted.map(\.range.startMinute)
        let ends = sorted.map { max($0.range.endMinute, $0.range.startMinute + minVisualMinutes) }
        let count = sorted.count

        // The groups, joining each item with the earlier ones it overlaps and starts soon after.
        var parent = Array(0..<count)
        func group(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        for j in 0..<count {
            for i in 0..<j where ends[i] > starts[j] && starts[j] - starts[i] < stackMinutes {
                parent[group(j)] = group(i)
            }
        }

        // Columns within each group, reusing one once what's in it has ended.
        var columnEnds: [Int: [Double]] = [:]
        var column = [Int](repeating: 0, count: count)
        for j in 0..<count {
            var groupEnds = columnEnds[group(j), default: []]
            if let free = groupEnds.firstIndex(where: { $0 <= starts[j] }) {
                column[j] = free
                groupEnds[free] = ends[j]
            } else {
                column[j] = groupEnds.count
                groupEnds.append(ends[j])
            }
            columnEnds[group(j)] = groupEnds
        }
        func left(_ i: Int) -> Double {
            Double(column[i]) / Double(columnEnds[group(i)]!.count)
        }

        // How deep each item is drawn over earlier items, from other groups, whose left edge (and color
        // stripe) it would cover.
        var depth = [Int](repeating: 0, count: count)
        for j in 0..<count {
            for i in 0..<j where group(i) != group(j) && ends[i] > starts[j] && abs(left(i) - left(j)) < 1e-9 {
                depth[j] = max(depth[j], depth[i] + 1)
            }
        }

        return sorted.indices.map { i in
            PositionedItem(item: sorted[i].item, key: sorted[i].key, range: sorted[i].range, column: column[i],
                           columns: columnEnds[group(i)]!.count, depth: depth[i])
        }
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
    case dose(MedicationDose)
}

/// A day's items sorted for a timeline: what goes in the all-day area, and the timed items laid out.
struct DayTimeline {
    var allDayEvents: [CalendarEvent] = []
    var allDayReminders: [CalendarReminder] = []
    var timed: [PositionedItem<TimelineEntry>] = []
    /// Sleep, as the part of each session on this day, drawn behind everything else.
    var sleep: [(range: MinuteRange, session: SleepSession)] = []
    /// The day's period flow, shown with the all-day items.
    var flow: MenstrualFlow?

    /// Events spanning the whole of `day` go in the all-day area with all-day ones; the rest are cut to
    /// the part on this day. Reminders and alarms are moments, laid out as if they took `pointMinutes`
    /// (the room they're drawn in), and short events as if they took `minMinutes`. An item starting
    /// `stackMinutes` after one it overlaps is drawn over it (see `TimelineLayout.layout`). From
    /// `health`, sleep is cut to this day, and medication doses are moments too.
    init(day: Date, items: DayItems?, alarms: [SpacetimeAlarm], health: HealthDay = .empty, pointMinutes: Double,
         minMinutes: Double, stackMinutes: Double = .infinity) {
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
        for dose in health.doses {
            let start = Double(Dates.minutesIntoDay(dose.date))
            timed.append(("dose:\(dose.id)", MinuteRange(startMinute: start, endMinute: start + pointMinutes),
                          .dose(dose)))
        }
        for session in health.sleep where session.end > dayStart && session.start < dayEnd {
            let start = session.start <= dayStart ? 0 : Double(Dates.minutesIntoDay(session.start))
            let end = session.end >= dayEnd ? 24 * 60 : Double(Dates.minutesIntoDay(session.end))
            sleep.append((MinuteRange(startMinute: start, endMinute: end), session))
        }
        flow = health.flow
        self.timed = TimelineLayout.layout(timed, minVisualMinutes: minMinutes, stackMinutes: stackMinutes)
    }
}
