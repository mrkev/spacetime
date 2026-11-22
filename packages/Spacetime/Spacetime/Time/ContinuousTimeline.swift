import SwiftUI

/// The day view on its side: one timeline running left to right through the days, with midnight
/// just another line, so what's late tonight sits next to what's early tomorrow. (Experimental.)
struct ContinuousTimeline: View {
    static let hourWidth: CGFloat = 120
    static let dayWidth = 24 * hourWidth
    static let headerHeight: CGFloat = 28
    static let allDayHeight: CGFloat = 24
    private static let daysEachWay = 180

    let onPressReminder: (CalendarReminder) -> Void
    /// Where the left edge is as it scrolls: the day and the minute into it.
    let onScroll: (_ day: Date, _ minute: Double) -> Void

    /// The day the timeline started on. It's state: as it scrolls, the day view passes a new `day`.
    @State private var anchor: Date
    @State private var position: ScrollPosition
    @State private var offsetX: CGFloat = 0
    @State private var labelWidth: CGFloat = 0

    /// Starts with `minute` into `day` at the left edge.
    init(day: Date, minute: Double, onPressReminder: @escaping (CalendarReminder) -> Void,
         onScroll: @escaping (Date, Double) -> Void) {
        _anchor = State(initialValue: Dates.startOfDay(day))
        self.onPressReminder = onPressReminder
        self.onScroll = onScroll
        let x = CGFloat(Self.daysEachWay) * Self.dayWidth + CGFloat(minute) / 60 * Self.hourWidth
        _position = State(initialValue: ScrollPosition(x: x))
        _offsetX = State(initialValue: x)
    }

    private func day(_ index: Int) -> Date { Dates.addDays(anchor, index - Self.daysEachWay) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0...(Self.daysEachWay * 2), id: \.self) { index in
                        DayStrip(date: day(index), onPressReminder: onPressReminder)
                            .frame(width: Self.dayWidth, height: geometry.size.height)
                    }
                }
            }
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x + $0.contentInsets.leading }) { _, x in
                // The first report can come before the starting position is applied.
                guard x > 0 else { return }
                offsetX = x
                let index = Int(floor(x / Self.dayWidth))
                onScroll(day(index), Double((x - CGFloat(index) * Self.dayWidth) / Self.hourWidth * 60))
            }
            .overlay(alignment: .topLeading) { pinnedDayLabel }
        }
        .background(Theme.background)
    }

    /// The day at the left edge, pinned there until the next day's label pushes it off.
    private var pinnedDayLabel: some View {
        let index = Int(floor(offsetX / Self.dayWidth))
        let nextDay = CGFloat(index + 1) * Self.dayWidth - offsetX
        return DayLabel(date: day(index))
            // Fades out the hour labels it slides over.
            .padding(.trailing, 16)
            .background(LinearGradient(stops: [.init(color: Theme.background, location: 0.8),
                                               .init(color: Theme.background.opacity(0), location: 1)],
                                       startPoint: .leading, endPoint: .trailing))
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { labelWidth = $0 }
            .offset(x: min(0, nextDay - labelWidth))
            .allowsHitTesting(false)
    }
}

private struct DayLabel: View {
    let date: Date

    var body: some View {
        Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Dates.isToday(date) ? Theme.tint : .primary)
            .padding(.horizontal, 8)
            .frame(height: ContinuousTimeline.headerHeight)
            .background(Theme.background)
    }
}

/// One day of the continuous timeline: hour labels, an all-day row, and the day's events laid out in
/// rows where they overlap.
private struct DayStrip: View {
    let date: Date
    let onPressReminder: (CalendarReminder) -> Void

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendar
    @Environment(AlarmStore.self) private var alarms

    private static let hourWidth = ContinuousTimeline.hourWidth
    /// Reminders and alarms are points in time, drawn this wide at any time span.
    private static let pointWidth: CGFloat = 140
    /// Short events are drawn at least this wide.
    private static let minEventWidth: CGFloat = 24

    private func x(_ minute: Double) -> CGFloat { CGFloat(minute) / 60 * Self.hourWidth }

    var body: some View {
        let day = DayTimeline(day: date, items: calendar.day(date), alarms: alarms.alarms(on: date),
                              pointMinutes: Double(Self.pointWidth / Self.hourWidth * 60),
                              minMinutes: Double(Self.minEventWidth / Self.hourWidth * 60))
        VStack(alignment: .leading, spacing: 0) {
            header
            allDayRow(day.allDayEvents, day.allDayReminders)
            GeometryReader { geometry in
                timedArea(day.timed, height: geometry.size.height)
            }
        }
        .background { hourLines }
        .onAppear { calendar.ensureMonths(date, radius: 0) }
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            ForEach(1..<24, id: \.self) { hour in
                Text(Dates.formatHour(Dates.date(date, atMinute: hour * 60)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .offset(x: CGFloat(hour) * Self.hourWidth + 4)
            }
            DayLabel(date: date)
        }
        .frame(height: ContinuousTimeline.headerHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hourLines: some View {
        Canvas { context, size in
            for hour in 0..<24 {
                let x = CGFloat(hour) * Self.hourWidth
                let line = Path(CGRect(x: x, y: 0, width: hour == 0 ? 1 : 0.5, height: size.height))
                context.fill(line, with: .color(hour == 0 ? Theme.separator : Theme.hourLine))
            }
        }
    }

    private func allDayRow(_ events: [CalendarEvent], _ reminders: [CalendarReminder]) -> some View {
        HStack(spacing: 2) {
            ForEach(events) { event in
                Button { TimeActions.openEvent(event, calendar: calendar) } label: {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(Color(hex: event.color).opacity(0.22), in: .rect(cornerRadius: 4))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            ForEach(reminders) { reminder in
                Button { onPressReminder(reminder) } label: {
                    PointLabel(icon: reminder.completed ? "checkmark.circle.fill" : "circle",
                               title: reminder.title, color: Color(hex: reminder.color))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .frame(height: ContinuousTimeline.allDayHeight)
    }

    private func timedArea(_ timed: [PositionedItem<TimelineEntry>], height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(timed) { entry in
                let row = height / CGFloat(entry.columns)
                let left = x(entry.range.startMinute)
                let top = CGFloat(entry.column) * row
                switch entry.item {
                case .event(let event):
                    Button { TimeActions.openEvent(event, calendar: calendar) } label: {
                        EventBar(event: event)
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(Self.minEventWidth, x(entry.range.endMinute) - left - 2), height: max(20, row - 2))
                    .offset(x: left + 1, y: top)
                case .reminder(let reminder):
                    Button { onPressReminder(reminder) } label: {
                        PointLabel(icon: reminder.completed ? "checkmark.circle.fill" : "circle",
                                   title: reminder.title, color: Color(hex: reminder.color))
                    }
                    .buttonStyle(.plain)
                    .frame(width: Self.pointWidth - 4, height: min(26, row - 2))
                    .offset(x: left, y: top)
                case .alarm(let alarm):
                    Button { model.time.alarmEditor = AlarmEditRequest(alarm: alarm) } label: {
                        PointLabel(icon: "alarm", title: alarm.title, color: Theme.alarm)
                    }
                    .buttonStyle(.plain)
                    .frame(width: Self.pointWidth - 4, height: min(26, row - 2))
                    .offset(x: left, y: top)
                }
            }
            if Dates.isToday(date) {
                TimelineView(.everyMinute) { context in
                    Rectangle()
                        .fill(Theme.tint)
                        .frame(width: 2)
                        .offset(x: x(Double(Dates.minutesIntoDay(context.date))) - 1)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct EventBar: View {
    let event: CalendarEvent

    var body: some View {
        let color = Color(hex: event.color)
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.system(size: 13, weight: .semibold))
            Text("\(Dates.formatTime(event.start)) – \(Dates.formatTime(event.end))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let location = event.location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.22))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 4))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A reminder or alarm: a moment, not a span.
private struct PointLabel: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.background, in: .capsule)
        .overlay { Capsule().stroke(color, lineWidth: 1) }
        .contentShape(.capsule)
    }
}
