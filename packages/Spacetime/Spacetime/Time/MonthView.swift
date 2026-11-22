import SwiftUI

// Ten years either way, matching the year view.
private let monthsEachWay = 120
private let titleHeight: CGFloat = 48
private let weekHeight: CGFloat = 64

private func weeksInMonth(_ month: Date) -> Int {
    Int(ceil(Double(Dates.weekday(month) + Dates.daysInMonth(month)) / 7))
}

/// A scrolling list of months, like Calendar's month view.
struct MonthView: View {
    let route: TimeRoute
    let initialMonth: Date

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendar
    @State private var position: Int?
    @State private var newReminder: NewReminderRequest?
    private let thisMonth = Dates.startOfMonth(Date())

    init(route: TimeRoute, initialMonth: Date) {
        self.route = route
        self.initialMonth = initialMonth
        let offset = Dates.differenceInMonths(Dates.startOfMonth(Date()), initialMonth)
        _position = State(initialValue: max(-monthsEachWay, min(monthsEachWay, offset)))
    }

    var body: some View {
        let nav = model.time
        VStack(spacing: 0) {
            WeekdayHeader()
            AccessBanner()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(-monthsEachWay...monthsEachWay, id: \.self) { offset in
                        let month = Dates.addMonths(thisMonth, offset)
                        MonthItem(month: month) { day in nav.path.append(.day(day)) }
                            .frame(height: titleHeight + CGFloat(weeksInMonth(month)) * weekHeight)
                    }
                }
                .scrollTargetLayout()
                .noScrollToTop()
            }
            .scrollPosition(id: $position, anchor: .top)
            .scrollIndicators(.hidden)
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.3) { visible in
                guard let first = visible.first else { return }
                let month = Dates.addMonths(thisMonth, first)
                nav.monthViewYear = Calendar.current.component(.year, from: month)
                calendar.ensureMonths(month, radius: 2)
            }
        }
        .background(Theme.background)
        // Like Calendar, the day view's back button names the month it's in.
        .navigationTitle(Dates.formatMonth(nav.dayViewDate))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            TimeToolbar(onNewReminder: { newReminder = NewReminderRequest(date: $0) })
        }
        .sizedSheet(item: $newReminder) { request in
            NavigationStack { ReminderEditorView(date: request.date) }
        }
        .onAppear {
            calendar.ensureMonths(Dates.addMonths(thisMonth, position ?? 0), radius: 2)
            nav.monthViewYear = Calendar.current.component(.year, from: Dates.addMonths(thisMonth, position ?? 0))
            if nav.isTop(route) { TimeNavigation.remember(.month) }
        }
        .onChange(of: nav.isTop(route)) { _, top in if top { TimeNavigation.remember(.month) } }
        .onChange(of: calendar.status) { calendar.ensureMonths(Dates.addMonths(thisMonth, position ?? 0), radius: 2) }
        .onChange(of: model.todayRequests) {
            guard nav.isTop(route) else { return }
            withAnimation { position = 0 }
        }
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
