import Foundation

/// Date helpers in the user's calendar and time zone. Weeks start on Sunday, like the rest of the app.
nonisolated enum Dates {
    static var calendar: Calendar { Calendar.current }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Adds calendar days, keeping the time of day across DST changes.
    static func addDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// The first of the month `months` from `date`'s month.
    static func addMonths(_ date: Date, _ months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: startOfMonth(date)) ?? date
    }

    /// Sunday is 0, like JavaScript's `getDay`.
    static func weekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    static func startOfWeek(_ date: Date, weekStartsOn: Int = 0) -> Date {
        let day = startOfDay(date)
        let diff = (weekday(day) - weekStartsOn + 7) % 7
        return addDays(day, -diff)
    }

    static func daysInMonth(_ date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    static func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    /// Whole calendar days between two dates (b - a), ignoring time of day.
    static func differenceInDays(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day ?? 0
    }

    static func differenceInMonths(_ a: Date, _ b: Date) -> Int {
        let ca = calendar.dateComponents([.year, .month], from: a)
        let cb = calendar.dateComponents([.year, .month], from: b)
        return (cb.year! - ca.year!) * 12 + (cb.month! - ca.month!)
    }

    static func minutesIntoDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The day's start plus `minutes`.
    static func date(_ day: Date, atMinute minutes: Int) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: startOfDay(day)) ?? day
    }

    /// The next half hour after now, on `day` (today if nil): where a new event or alarm starts.
    static func nextHalfHour(on day: Date? = nil, now: Date = Date()) -> Date {
        let minutes = minutesIntoDay(now)
        let rounded = (minutes / 60) * 60 + (minutes % 60 < 30 ? 30 : 60)
        return date(day ?? now, atMinute: rounded)
    }

    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Keys

    /// Local-time key like `2026-10-26`.
    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func parseDayKey(_ key: String?) -> Date? {
        guard let parts = key?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Local-time key like `2026-10`.
    static func monthKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }

    static func parseMonthKey(_ key: String?) -> Date? {
        guard let parts = key?.split(separator: "-").compactMap({ Int($0) }), parts.count == 2 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    }

    // MARK: Formatting

    static func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func formatHour(_ date: Date) -> String {
        date.formatted(.dateTime.hour())
    }

    /// An hour of any day, like "3 PM", or "15" where the clock is 24-hour. 24 is midnight.
    static func formatHour(hour: Int) -> String {
        formatHour(date(year: 2000, month: 1, day: 1, hour: hour % 24))
    }

    static func formatMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
    }

    static func formatShortMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    static func formatMonthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func formatFullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    static func formatMediumDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Narrow weekday labels (S M T W T F S) starting from `weekStartsOn`.
    static func weekdayLabels(weekStartsOn: Int = 0) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + weekStartsOn) % 7] }
    }

    /// "Today", "Tomorrow", "Yesterday", or a medium date.
    static func formatRelativeDay(_ date: Date, now: Date = Date()) -> String {
        switch differenceInDays(now, date) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: formatMediumDate(date)
        }
    }
}
