#if os(iOS)
import SwiftUI

// Ten years either way, matching the year view.
private let monthsEachWay = 120
private let titleHeight: CGFloat = 48
private let weekHeight: CGFloat = 64

private func weeksInMonth(_ month: Date) -> Int {
    Int(ceil(Double(Dates.weekday(month) + Dates.daysInMonth(month)) / 7))
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
    let route: TimeRoute

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendar
    @State private var position: ScrollPosition
    @State private var visible: VisibleMonths
    @State private var newReminder: NewReminderRequest?
    private let thisMonth: Date
    private let column: MonthColumn

    init(route: TimeRoute, initialMonth: Date) {
        self.route = route
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
        VStack(spacing: 0) {
            WeekdayHeader()
            AccessBanner()
            ScrollView {
                ZStack(alignment: .top) {
                    Color.clear.frame(height: column.height)
                    ForEach(Array(visible.drawn), id: \.self) { offset in
                        MonthItem(month: month(offset)) { day in nav.path.append(.day(day)) }
                            .frame(height: column.height(offset))
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
        // Like Calendar, the day view's back button names the month it's in.
        .navigationTitle(Dates.formatMonth(nav.dayViewDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            TimeToolbar(onNewReminder: { newReminder = NewReminderRequest(date: $0) })
        }
        .sheet(item: $newReminder) { request in
            NavigationStack { ReminderEditorView(date: request.date) }
        }
        .onAppear {
            showing(visible.top)
            if nav.isTop(route) { nav.remember(.month) }
        }
        .onChange(of: visible.top) { _, top in showing(top) }
        .onChange(of: nav.isTop(route)) { _, top in if top { nav.remember(.month) } }
        .onChange(of: calendar.status) { calendar.ensureMonths(month(visible.top), radius: 2) }
        .onChange(of: model.todayRequests) {
            guard nav.isTop(route) else { return }
            withAnimation { position.scrollTo(y: column.top(0)) }
        }
    }

    /// Loads the months around the one at the top, and shows its year on the year view's back button.
    private func showing(_ offset: Int) {
        model.time.monthViewYear = Calendar.current.component(.year, from: month(offset))
        calendar.ensureMonths(month(offset), radius: 2)
    }
}

struct WeekdayHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Dates.weekdayLabels().enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct MonthItem: View {
    let month: Date
    let onPressDay: (Date) -> Void
    @Environment(CalendarStore.self) private var calendar

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
                    .offset(x: CGFloat(leading) * cellWidth)
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
