import SwiftUI

private let daysEachWay = 730
private let weeksBefore = Int(ceil(Double(daysEachWay) / 7)) + 1
private let weekCount = Int(ceil(Double(daysEachWay * 2) / 7)) + 3

/// Where the day pages' timelines are scrolled, shared so swiping keeps the time of day.
final class TimelineScroll {
    var y: CGFloat
    init(y: CGFloat) { self.y = y }
}

/// The selected (long-pressed) event and the day it's on.
struct TimelineSelection: Equatable {
    var key: String
    var day: String
}

/// An event to pick a place for, and whether later ones in its series move too.
struct EventPlaceRequest: Identifiable {
    let id = UUID()
    var event: CalendarEvent
    var span: Span
}

/// A week strip over a swipeable timeline of days, like Calendar's day view.
struct DayView: View {
    let route: TimeRoute

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendar
    /// Pages are indexed relative to a fixed anchor so indices stay stable while swiping.
    @State private var anchor: Date
    @State private var dayIndex: Int? = daysEachWay
    @State private var weekIndex: Int? = weeksBefore
    @State private var selection: TimelineSelection?
    /// Whether an event is being dragged or the day pinched, so the pager holds still.
    @State private var gestureActive = false
    @State private var hourHeight: CGFloat
    @State private var scroll: TimelineScroll
    @State private var scrollToNow = 0
    @State private var newReminder: NewReminderRequest?
    @State private var openReminder: CalendarReminder?
    @State private var eventPlace: EventPlaceRequest?
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// A phone on its side, which shows the days as one continuous timeline.
    private var sideways: Bool { verticalSizeClass == .compact }
    #else
    private let sideways = false
    #endif

    init(route: TimeRoute, initialDay: Date, hourHeight height: CGFloat) {
        self.route = route
        let anchor = Dates.startOfDay(initialDay)
        _anchor = State(initialValue: anchor)
        _hourHeight = State(initialValue: height)
        // Start the timeline around the current hour (or 7 AM on other days).
        _scroll = State(initialValue: TimelineScroll(
            y: Dates.isToday(anchor) ? Timeline.nowOffset(hourHeight: height) : 7 * height))
    }

    private var selected: Date { dayFor(dayIndex ?? daysEachWay) }
    private var anchorWeek: Date { Dates.startOfWeek(anchor) }
    private func dayFor(_ index: Int) -> Date { Dates.addDays(anchor, index - daysEachWay) }
    private func indexFor(_ day: Date) -> Int { Dates.differenceInDays(anchor, day) + daysEachWay }
    private func weekFor(_ index: Int) -> Date { Dates.addDays(anchorWeek, (index - weeksBefore) * 7) }
    private func weekIndexFor(_ day: Date) -> Int {
        Int((Double(Dates.differenceInDays(anchorWeek, Dates.startOfWeek(day))) / 7).rounded()) + weeksBefore
    }

    private func select(_ day: Date) {
        let index = indexFor(day)
        guard index >= 0 && index <= daysEachWay * 2 else { return }
        dayIndex = index
    }

    var body: some View {
        let nav = model.time
        Group {
            if sideways {
                // Over where the hidden bars were; the sides stay clear of the camera.
                continuousTimeline.ignoresSafeArea(edges: .vertical)
            } else {
                pager
            }
        }
        .barsHidden(sideways)
        .allowsLandscape(nav.isTop(route) && model.tab == .time)
        .background(Theme.background)
        .navigationTitle("")
        .inlineNavigationTitle()
        .toolbar {
            #if os(macOS)
            // Without a trackpad there's no swiping between days.
            ToolbarItemGroup(placement: .navigation) {
                Button("Previous Day", systemImage: "chevron.left") { withAnimation { select(Dates.addDays(selected, -1)) } }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Next Day", systemImage: "chevron.right") { withAnimation { select(Dates.addDays(selected, 1)) } }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                AddMenu(day: selected) { newReminder = NewReminderRequest(date: $0) } onNewAlarm: {
                    model.time.alarmEditor = AlarmEditRequest(day: $0)
                }
            }
        }
        .sizedSheet(item: $newReminder) { request in
            NavigationStack { ReminderEditorView(date: request.date) }
        }
        .sizedSheet(item: $openReminder) { reminder in
            ReminderDetailsView(id: reminder.key)
        }
        .sizedSheet(item: $eventPlace) { request in
            NavigationStack { EventPlaceView(event: request.event, span: request.span) }
        }
        .onAppear {
            nav.dayViewDate = selected
            if nav.isTop(route) { nav.remember(.day) }
        }
        .onChange(of: nav.isTop(route)) { _, top in if top { nav.remember(.day) } }
        .onChange(of: dayIndex) {
            selection = nil
            nav.dayViewDate = selected
            let week = weekIndexFor(selected)
            if weekIndex != week { withAnimation { weekIndex = week } }
        }
        .onChange(of: weekIndex) { _, index in
            guard let index, index != weekIndexFor(selected) else { return }
            // Keep the same weekday selected when swiping between weeks, like Calendar.
            select(Dates.addDays(weekFor(index), Dates.weekday(selected)))
        }
        .onChange(of: model.todayRequests) {
            guard nav.isTop(route) else { return }
            // Go to today's page and bring the current-time indicator into view.
            scroll.y = Timeline.nowOffset(hourHeight: hourHeight)
            select(Date())
            scrollToNow += 1
        }
    }

    /// The week strip over a page per day.
    private var pager: some View {
        VStack(spacing: 0) {
            weekHeader
            AccessBanner()
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0...(daysEachWay * 2), id: \.self) { index in
                        let date = dayFor(index)
                        let key = Dates.dayKey(date)
                        DayPage(
                            date: date,
                            isCurrent: index == dayIndex,
                            scroll: scroll,
                            hourHeight: $hourHeight,
                            scrollToNow: scrollToNow,
                            selectedKey: selection?.day == key ? selection?.key : nil,
                            actions: pageActions(dayKey: key))
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $dayIndex)
            .scrollIndicators(.hidden)
            .scrollDisabled(gestureActive)
        }
    }

    private func pageActions(dayKey: String) -> DayPageActions {
        DayPageActions(
            select: { selection = $0.map { TimelineSelection(key: $0, day: dayKey) } },
            gestureActive: { gestureActive = $0 },
            zoomEnded: { model.time.saveHourHeight(hourHeight) },
            pressReminder: { openReminder = $0 },
            setPlace: { event, span in eventPlace = EventPlaceRequest(event: event, span: span) })
    }

    /// The days as one timeline, starting where the day page was scrolled to and keeping the day
    /// page in step, so turning back shows the same day and time.
    private var continuousTimeline: some View {
        let topMinute = max(0, Double((scroll.y - Timeline.padding) / hourHeight * 60))
        return ContinuousTimeline(day: selected, minute: topMinute, onPressReminder: { openReminder = $0 }) { day, minute in
            if !Dates.isSameDay(day, selected) { select(day) }
            scroll.y = Timeline.padding + CGFloat(minute) / 60 * hourHeight
        }
    }

    private var weekHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(Dates.weekdayLabels().enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<weekCount, id: \.self) { index in
                        WeekRow(start: weekFor(index), selected: selected) { select($0) }
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $weekIndex)
            .scrollIndicators(.hidden)
            .frame(height: 42)
            Text(Dates.formatFullDate(selected))
                .font(.system(size: 15, weight: .medium))
                .padding(.top, 4)
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct WeekRow: View {
    let start: Date
    let selected: Date
    let onSelect: (Date) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let day = Dates.addDays(start, i)
                let isSelected = Dates.isSameDay(day, selected)
                let isToday = Dates.isToday(day)
                Button { onSelect(day) } label: {
                    Text(String(Calendar.current.component(.day, from: day)))
                        .font(.system(size: 18, weight: isSelected || isToday ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.background : isToday ? Theme.tint : .primary)
                        .frame(width: 34, height: 34)
                        .background {
                            if isSelected { Circle().fill(isToday ? Theme.tint : Color.primary) }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Dates.formatFullDate(day))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
