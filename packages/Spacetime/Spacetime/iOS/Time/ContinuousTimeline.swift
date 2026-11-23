#if os(iOS)
import SwiftUI

/// The day view on its side: one timeline running left to right through the days, with midnight
/// just another line, so what's late tonight sits next to what's early tomorrow. (Experimental.)
struct ContinuousTimeline: View {
    static let defaultHourWidth: CGFloat = 120
    /// Pinching zooms between these: from about a day on screen to a few hours.
    static let minHourWidth: CGFloat = 32
    static let maxHourWidth: CGFloat = 480
    static let headerHeight: CGFloat = 28
    static let allDayHeight: CGFloat = 24
    private static let daysEachWay = 180

    let onPressReminder: (CalendarReminder) -> Void
    /// Where the left edge is as it scrolls: the day and the minute into it.
    let onScroll: (_ day: Date, _ minute: Double) -> Void
    /// The hour width a pinch ended at, to start at next time.
    let onZoomEnded: (CGFloat) -> Void

    /// The day the timeline started on. It's state: as it scrolls, the day view passes a new `day`.
    @State private var anchor: Date
    @State private var position: ScrollPosition
    @State private var offsetX: CGFloat = 0
    @State private var labelWidth: CGFloat = 0
    @State private var hourWidth: CGFloat
    @State private var pinch: SidewaysPinch?

    private var dayWidth: CGFloat { 24 * hourWidth }

    /// Starts with `minute` into `day` at the left edge, with hours `hourWidth` wide.
    init(day: Date, minute: Double, hourWidth: CGFloat, onPressReminder: @escaping (CalendarReminder) -> Void,
         onScroll: @escaping (Date, Double) -> Void, onZoomEnded: @escaping (CGFloat) -> Void) {
        _anchor = State(initialValue: Dates.startOfDay(day))
        self.onPressReminder = onPressReminder
        self.onScroll = onScroll
        self.onZoomEnded = onZoomEnded
        _hourWidth = State(initialValue: hourWidth)
        let x = (CGFloat(Self.daysEachWay) * 24 + CGFloat(minute) / 60) * hourWidth
        _position = State(initialValue: ScrollPosition(x: x))
        _offsetX = State(initialValue: x)
    }

    private func day(_ index: Int) -> Date { Dates.addDays(anchor, index - Self.daysEachWay) }

    /// Tells the day view the day and minute at the left edge, at `x`.
    private func reportScroll(_ x: CGFloat) {
        let index = Int(floor(x / dayWidth))
        onScroll(day(index), Double((x - CGFloat(index) * dayWidth) / hourWidth * 60))
    }

    /// Pinch to zoom. The minute under your fingers stays put.
    private func handlePinch(_ phase: GesturePhase) {
        switch phase.state {
        case .began:
            pinch = SidewaysPinch(hourWidth: hourWidth, offsetX: offsetX, focalX: phase.localLocation.x)
        case .changed:
            guard let pinch else { return }
            let next = pinch.hourWidth(scale: phase.scale)
            guard next != hourWidth else { return }
            let x = pinch.offsetX(hourWidth: next)
            hourWidth = next
            offsetX = x
            position.scrollTo(x: x)
        case .ended, .cancelled:
            guard pinch != nil else { return }
            pinch = nil
            reportScroll(offsetX)
            onZoomEnded(hourWidth)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0...(Self.daysEachWay * 2), id: \.self) { index in
                        DayStrip(date: day(index), hourWidth: hourWidth, onPressReminder: onPressReminder)
                            .frame(width: dayWidth, height: geometry.size.height)
                    }
                }
            }
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            .scrollDisabled(pinch != nil)
            .gesture(PinchRecognizer(action: handlePinch))
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x + $0.contentInsets.leading }) { _, x in
                // The first report can come before the starting position is applied.
                guard x > 0, pinch == nil else { return }
                offsetX = x
                reportScroll(x)
            }
            .overlay(alignment: .topLeading) { pinnedDayLabel }
        }
        .background(Theme.background)
    }

    /// The day at the left edge, pinned there until the next day's label pushes it off.
    private var pinnedDayLabel: some View {
        let index = Int(floor(offsetX / dayWidth))
        let nextDay = CGFloat(index + 1) * dayWidth - offsetX
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

/// A pinch in progress: the minute under the fingers when it began, from the start of the first day,
/// and how far across the screen the fingers are.
struct SidewaysPinch {
    var startWidth: CGFloat
    var minute: Double
    var focalX: CGFloat

    init(hourWidth: CGFloat, offsetX: CGFloat, focalX: CGFloat) {
        startWidth = hourWidth
        minute = Double((offsetX + focalX) / hourWidth * 60)
        self.focalX = focalX
    }

    /// The hour width with the fingers spread by `scale`, within the zoom's limits.
    func hourWidth(scale: CGFloat) -> CGFloat {
        min(ContinuousTimeline.maxHourWidth, max(ContinuousTimeline.minHourWidth, startWidth * scale)).rounded()
    }

    /// Where to scroll at `hourWidth` so the minute stays under the fingers.
    func offsetX(hourWidth: CGFloat) -> CGFloat {
        max(0, CGFloat(minute) / 60 * hourWidth - focalX)
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
    let hourWidth: CGFloat
    let onPressReminder: (CalendarReminder) -> Void

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendar
    @Environment(AlarmStore.self) private var alarms

    /// Reminders and alarms are points in time, drawn this wide at any time span.
    private static let pointWidth: CGFloat = 140
    /// Short events are drawn at least this wide.
    private static let minEventWidth: CGFloat = 24
    /// How tall a row of events is, with room for each one's title, times, and location. Rows are
    /// only shorter when a day has more overlapping events than fit.
    private static let rowHeight: CGFloat = 54

    private func x(_ minute: Double) -> CGFloat { CGFloat(minute) / 60 * hourWidth }

    /// Every how many hours to label, so the labels don't run together when zoomed out.
    private var labelStep: Int {
        [1, 2, 3, 4, 6, 12].first { CGFloat($0) * hourWidth >= 56 } ?? 12
    }

    var body: some View {
        let day = DayTimeline(day: date, items: calendar.day(date), alarms: alarms.alarms(on: date),
                              pointMinutes: Double(Self.pointWidth / hourWidth * 60),
                              minMinutes: Double(Self.minEventWidth / hourWidth * 60))
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
            ForEach(Array(stride(from: labelStep, to: 24, by: labelStep)), id: \.self) { hour in
                Text(Dates.formatHour(Dates.date(date, atMinute: hour * 60)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .offset(x: CGFloat(hour) * hourWidth + 4)
            }
            DayLabel(date: date)
        }
        .frame(height: ContinuousTimeline.headerHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hourLines: some View {
        let hourWidth = hourWidth
        return Canvas { context, size in
            for hour in 0..<24 {
                let x = CGFloat(hour) * hourWidth
                let line = Path(CGRect(x: x, y: 0, width: hour == 0 ? 1 : 0.5, height: size.height))
                context.fill(line, with: .color(hour == 0 ? Theme.separator : Theme.hourLine))
            }
        }
    }

    private func allDayRow(_ events: [CalendarEvent], _ reminders: [CalendarReminder]) -> some View {
        HStack(spacing: 2) {
            ForEach(events) { event in
                Button { TimeActions.openEvent(event, calendar: calendar) } label: {
                    StickyLabel {
                        Text(event.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                    }
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
        // One height for all the day's rows, so every event shows the same lines.
        let row = min(Self.rowHeight, height / CGFloat(timed.map(\.columns).max() ?? 1))
        let lines = row >= Self.rowHeight ? 3 : row >= 40 ? 2 : 1
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(timed) { entry in
                let left = x(entry.range.startMinute)
                let top = CGFloat(entry.column) * row
                switch entry.item {
                case .event(let event):
                    Button { TimeActions.openEvent(event, calendar: calendar) } label: {
                        EventBar(event: event, lines: lines)
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
    /// How many lines to show: the title, then the times, then the location.
    let lines: Int

    /// The times, with the day it ends on if that's another day.
    private var times: String {
        let end = Dates.isSameDay(event.start, event.end)
            ? Dates.formatTime(event.end)
            : "\(event.end.formatted(.dateTime.weekday(.abbreviated))) \(Dates.formatTime(event.end))"
        return "\(Dates.formatTime(event.start)) – \(end)"
    }

    var body: some View {
        let color = Color(hex: event.color)
        StickyLabel {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                if lines >= 2 {
                    Text(times)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if lines >= 3, let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .padding(.leading, 7)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.22))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 4))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A bar's text, which stays at the left edge of the screen while the bar starts off it, until the
/// bar's end pushes it off too.
private struct StickyLabel<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        let width = width
        // Truncated in a short bar, which it fills, so it only moves in a bar longer than it is.
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { self.width = $0 }
            // In a frame as wide as the bar, so the effect knows where the bar is.
            .frame(maxWidth: .infinity, alignment: .leading)
            .visualEffect { content, proxy in
                let bar = proxy.frame(in: .scrollView(axis: .horizontal))
                return content.offset(x: max(0, min(-bar.minX, bar.width - width)))
            }
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
#endif
