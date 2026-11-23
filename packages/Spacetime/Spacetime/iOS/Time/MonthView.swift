#if os(iOS)
import SwiftUI

// Ten years either way, matching the year view.
private let monthsEachWay = 120
private let titleHeight: CGFloat = 48
private let weekHeight: CGFloat = 64

private func weeksInMonth(_ month: Date) -> Int {
    Int(ceil(Double(Dates.weekday(month) + Dates.daysInMonth(month)) / 7))
}

/// Which row of `month` `day` is in.
private func weekIndex(of day: Date, in month: Date) -> Int {
    (Dates.weekday(month) + Calendar.current.component(.day, from: day) - 1) / 7
}

/// Where each month is in the list. Months are four to six weeks tall, so they're placed by hand: a
/// lazy stack guesses the heights of months it hasn't drawn, so starting one on this month, 120 months
/// in, landed several months off.
private struct MonthColumn {
    /// Where each month starts, from `-monthsEachWay`, and then where the last one ends.
    let tops: [CGFloat]

    init(thisMonth: Date) {
        var tops: [CGFloat] = [0]
        for offset in -monthsEachWay...monthsEachWay {
            let month = Dates.addMonths(thisMonth, offset)
            tops.append(tops.last! + titleHeight + CGFloat(weeksInMonth(month)) * weekHeight)
        }
        self.tops = tops
    }

    var height: CGFloat { tops.last! }
    func top(_ offset: Int) -> CGFloat { tops[offset + monthsEachWay] }
    func height(_ offset: Int) -> CGFloat { tops[offset + monthsEachWay + 1] - tops[offset + monthsEachWay] }

    /// The month at `y`.
    func offset(at y: CGFloat) -> Int {
        let index = (tops.lastIndex { $0 <= y } ?? 0) - monthsEachWay
        return min(monthsEachWay, max(-monthsEachWay, index))
    }
}

/// The months on screen, and the one at the top, which names the year.
private struct VisibleMonths: Equatable {
    var top: Int
    var drawn: ClosedRange<Int>
}

/// A scrolling list of months, like Calendar's month view.
struct MonthView: View {
    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendar
    @State private var position: ScrollPosition
    @State private var visible: VisibleMonths
    private let thisMonth: Date
    private let column: MonthColumn

    init(initialMonth: Date) {
        let thisMonth = Dates.startOfMonth(Date())
        self.thisMonth = thisMonth
        let column = MonthColumn(thisMonth: thisMonth)
        self.column = column
        let offset = max(-monthsEachWay, min(monthsEachWay, Dates.differenceInMonths(thisMonth, initialMonth)))
        _position = State(initialValue: ScrollPosition(y: column.top(offset)))
        _visible = State(initialValue: VisibleMonths(
            top: offset, drawn: max(-monthsEachWay, offset - 1)...min(monthsEachWay, offset + 3)))
    }

    private func month(_ offset: Int) -> Date { Dates.addMonths(thisMonth, offset) }

    var body: some View {
        let nav = model.time
        let transition = nav.transition
        // The month a transition zooms or splits.
        let anchorMonth = transition.map { $0.isZoom ? $0.month : Dates.startOfMonth($0.day) }
        let split = nav.monthSplit
        VStack(spacing: 0) {
            WeekdayHeader()
            AccessBanner()
            ScrollView {
                ZStack(alignment: .top) {
                    Color.clear.frame(height: column.height)
                    ForEach(Array(visible.drawn), id: \.self) { offset in
                        let month = month(offset)
                        MonthItem(month: month, split: split) { day in nav.show(.day, day: day) }
                            .frame(height: column.height(offset))
                            .reportsFrame(for: anchorMonth == month ? transition?.id : nil) { report($0, month) }
                            .alignmentGuide(.top) { _ in -column.top(offset) }
                    }
                }
                .noScrollToTop()
            }
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: VisibleMonths.self, of: { geometry in
                let y = geometry.contentOffset.y + geometry.contentInsets.top
                let height = geometry.containerSize.height
                // A month counts as showing once it's well onto the screen.
                return VisibleMonths(top: column.offset(at: y + height * 0.2),
                                     drawn: max(-monthsEachWay, column.offset(at: y) - 1)...min(
                                        monthsEachWay, column.offset(at: y + height) + 1))
            }) { _, next in
                visible = next
            }
        }
        .background(Theme.background)
        .onAppear { showing(visible.top) }
        .onChange(of: visible.top) { _, top in showing(top) }
        .onChange(of: calendar.status) { calendar.ensureMonths(month(visible.top), radius: 2) }
        .onChange(of: model.todayRequests) {
            guard nav.isShowing(.month) else { return }
            withAnimation { position.scrollTo(y: column.top(0)) }
        }
    }

    /// Reports where the transition's anchor is, from the frame of its month: the month's grid of
    /// days, for a zoom, or the week that becomes the day view's strip.
    private func report(_ frame: CGRect, _ month: Date) {
        guard let transition = model.time.transition else { return }
        let grid = frame.minY + titleHeight
        let anchor = transition.isZoom
            ? CGRect(x: frame.minX, y: grid, width: frame.width, height: CGFloat(weeksInMonth(month)) * weekHeight)
            : CGRect(x: frame.minX, y: grid + CGFloat(weekIndex(of: transition.day, in: month)) * weekHeight,
                     width: frame.width, height: weekHeight)
        model.time.report(.month, anchor, transition: transition.id)
    }

    /// Loads the months around the one at the top, which the back button shows the year of.
    private func showing(_ offset: Int) {
        if model.time.transition == nil { model.time.month = month(offset) }
        calendar.ensureMonths(month(offset), radius: 2)
    }
}

/// The month view's weekday letters, over a line.
struct WeekdayHeader: View {
    var body: some View {
        WeekdayLetters()
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Divider() }
    }
}

/// The weekday letters over the month and day views, which stay put between them.
struct WeekdayLetters: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Dates.weekdayLabels().enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 6)
        .background(Theme.background)
    }
}

private struct MonthItem: View {
    let month: Date
    let split: MonthSplit?
    let onPressDay: (Date) -> Void
    @Environment(CalendarStore.self) private var calendar

    /// How far a row moves, and how faded it is, as the month view splits at a week: the title is row
    /// -1.
    private func moved(_ row: Int) -> (y: CGFloat, opacity: Double) {
        guard let split else { return (0, 1) }
        let months = Dates.differenceInMonths(month, Dates.startOfMonth(split.day))
        let splitRow = months == 0 ? weekIndex(of: split.day, in: month) : months > 0 ? Int.max : Int.min
        if row == splitRow { return (split.up, 1) }
        return (row < splitRow ? split.up : split.down, split.opacity)
    }

    var body: some View {
        let leading = Dates.weekday(month)
        let total = Dates.daysInMonth(month)
        let weeks = weeksInMonth(month)
        let isCurrentMonth = Dates.monthKey(month) == Dates.monthKey(Date())
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / 7
            VStack(spacing: 0) {
                Text(Dates.formatShortMonth(month))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isCurrentMonth ? Theme.tint : .primary)
                    .frame(width: cellWidth)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, maxHeight: titleHeight, alignment: .bottomLeading)
                    .offset(x: CGFloat(leading) * cellWidth, y: moved(-1).y)
                    .opacity(moved(-1).opacity)
                ForEach(0..<weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let number = week * 7 + weekday - leading + 1
                            if number >= 1 && number <= total {
                                let date = Dates.addDays(month, number - 1)
                                let items = calendar.day(date)
                                DayCell(date: date, hasItems: items.map { !$0.events.isEmpty || !$0.reminders.isEmpty } ?? false,
                                        onPress: onPressDay)
                                    .frame(width: cellWidth)
                            } else {
                                Color.clear.frame(width: cellWidth)
                            }
                        }
                    }
                    .frame(height: weekHeight)
                    .offset(y: moved(week).y)
                    .opacity(moved(week).opacity)
                }
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let hasItems: Bool
    let onPress: (Date) -> Void

    var body: some View {
        let isToday = Dates.isToday(date)
        let weekday = Dates.weekday(date)
        let weekend = weekday == 0 || weekday == 6
        Button { onPress(date) } label: {
            VStack(spacing: 4) {
                Text(String(Calendar.current.component(.day, from: date)))
                    .font(.system(size: 18, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? Color.white : weekend ? Theme.secondaryText : .primary)
                    .frame(width: 32, height: 32)
                    .background { if isToday { Circle().fill(Theme.tint) } }
                Circle()
                    .fill(hasItems ? Theme.secondaryText : .clear)
                    .frame(width: 6, height: 6)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1 / 3) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Dates.formatFullDate(date))
    }
}
#endif
