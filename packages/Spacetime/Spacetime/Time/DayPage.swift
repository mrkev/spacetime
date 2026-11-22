import SwiftUI

enum Timeline {
    /// How tall an hour is by default; pinching zooms between the min and max.
    static let defaultHourHeight: CGFloat = 56
    static let minHourHeight: CGFloat = 24
    static let maxHourHeight: CGFloat = 180
    static let gutter: CGFloat = 56
    static let padding: CGFloat = 12
    /// Reminders are points in time, so they stay this tall at any zoom.
    static let reminderHeight: CGFloat = 26
    static let minBlockHeight: CGFloat = 20
    static let handleHit: CGFloat = 44
    static let titleLine: CGFloat = 15
    static let subtitleLine: CGFloat = 14
    static let blockPadding: CGFloat = 2
    static let menuHeight: CGFloat = 44

    /// Where the timeline scrolls to show the current time: an hour above it.
    static func nowOffset(hourHeight: CGFloat) -> CGFloat {
        max(0, (CGFloat(Dates.minutesIntoDay(Date())) / 60 - 1) * hourHeight)
    }

    static func y(minute: Double, hourHeight: CGFloat) -> CGFloat {
        padding + CGFloat(minute) / 60 * hourHeight
    }

    static func blockFrame(_ range: MinuteRange, hourHeight: CGFloat) -> (top: CGFloat, height: CGFloat) {
        (y(minute: range.startMinute, hourHeight: hourHeight),
         max(minBlockHeight, CGFloat(range.endMinute - range.startMinute) / 60 * hourHeight - 2))
    }
}

/// Where a dragged event is drawn until the calendar reloads with its saved times. `basis` is the
/// day's data at drag time; once that's replaced, the draft is stale and the real times show.
private struct Draft {
    var key: String
    /// The event's key once saved (keys include the start time).
    var savedKey: String
    var range: MinuteRange
    var dragging: Bool
    /// Whether the event was already selected (so it moved right away instead of after a hold).
    var fromSelected: Bool
    var basis: DayItems?
}

/// A new event's block, held where it'll go until its editor closes. While `lifted`, it's being
/// dragged into place.
private struct NewEventDraft {
    var range: MinuteRange
    var lifted: Bool
}

/// One day's timeline: an all-day area over hours you can scroll, pinch, and drag events around in.
struct DayPage: View {
    let date: Date
    let isCurrent: Bool
    let scroll: TimelineScroll
    @Binding var hourHeight: CGFloat
    /// Bumped to scroll today's page to the current time (the Today button).
    let scrollToNow: Int
    /// The selected (editable) event's key, if it's on this day.
    let selectedKey: String?
    let onSelect: (String?) -> Void
    /// Lets the pager stop paging while an event is dragged or the day is pinched.
    let onGestureActive: (Bool) -> Void
    let onZoomEnd: () -> Void
    let onPressReminder: (CalendarReminder) -> Void
    let onSetPlace: (CalendarEvent, Span) -> Void

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendar
    @Environment(AlarmStore.self) private var alarms
    @State private var position: ScrollPosition
    @State private var scrollY: CGFloat = 0
    @State private var draft: Draft?
    /// Where the current drag started (the drawn position, which may be an unsaved earlier drag).
    @State private var dragOrigin: MinuteRange?
    @State private var dragStartY: CGFloat = 0
    /// Lifting your finger after a drag also ends the press, which would otherwise open the event.
    @State private var lastDragEnd = Date.distantPast
    /// Long-pressing empty space while an event is copied offers to paste it there.
    @State private var pasteMinute: Double?
    @State private var pinch: (height: CGFloat, minute: Double, focalY: CGFloat)?
    @State private var newEvent: NewEventDraft?
    /// Where the new event's drag started: its range then, and the finger's height in the window.
    @State private var newEventOrigin: (range: MinuteRange, y: CGFloat)?
    @State private var handledScrollToNow = 0
    @State private var lastHourHeight: CGFloat = 0

    init(date: Date, isCurrent: Bool, scroll: TimelineScroll, hourHeight: Binding<CGFloat>, scrollToNow: Int,
         selectedKey: String?, onSelect: @escaping (String?) -> Void, onGestureActive: @escaping (Bool) -> Void,
         onZoomEnd: @escaping () -> Void, onPressReminder: @escaping (CalendarReminder) -> Void,
         onSetPlace: @escaping (CalendarEvent, Span) -> Void) {
        self.date = date
        self.isCurrent = isCurrent
        self.scroll = scroll
        _hourHeight = hourHeight
        self.scrollToNow = scrollToNow
        self.selectedKey = selectedKey
        self.onSelect = onSelect
        self.onGestureActive = onGestureActive
        self.onZoomEnd = onZoomEnd
        self.onPressReminder = onPressReminder
        self.onSetPlace = onSetPlace
        // Where the timeline starts scrolled to; shared across pages so swiping keeps the time of day.
        _position = State(initialValue: ScrollPosition(y: scroll.y))
        _handledScrollToNow = State(initialValue: scrollToNow)
    }

    var body: some View {
        let items = calendar.day(date)
        let split = dayTimeline(items)
        VStack(spacing: 0) {
            if !split.allDayEvents.isEmpty || !split.allDayReminders.isEmpty {
                allDayArea(split.allDayEvents, split.allDayReminders)
            }
            GeometryReader { geometry in
                ScrollView {
                    timeline(split.timed, items: items, width: geometry.size.width)
                }
                .scrollPosition($position)
                .scrollIndicators(.hidden)
                .scrollDisabled(draft?.dragging == true || newEvent?.lifted == true || pinch != nil)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
                    scrollY = y
                    if isCurrent && pinch == nil { scroll.y = y }
                }
                #if os(iOS)
                .gesture(PinchRecognizer(action: handlePinch))
                #else
                .onMagnifyPhases(handlePinch)
                #endif
            }
        }
        .onAppear {
            calendar.ensureMonths(date, radius: 0)
            lastHourHeight = hourHeight
        }
        .onChange(of: isCurrent) { _, current in
            // Pages next to the one showing were laid out before it scrolled; catch up.
            if current, abs(scrollY - scroll.y) > 1 { position.scrollTo(y: scroll.y) }
            if !current { pasteMinute = nil }
        }
        .onChange(of: scrollToNow) { _, value in
            guard value != handledScrollToNow else { return }
            handledScrollToNow = value
            if Dates.isToday(date) {
                withAnimation { position.scrollTo(y: Timeline.nowOffset(hourHeight: hourHeight)) }
            }
        }
        .onChange(of: hourHeight) { _, height in
            // Other days (and this one, outside a pinch) keep the same time at the top.
            let previous = lastHourHeight
            lastHourHeight = height
            guard pinch == nil, previous > 0 else { return }
            let y = max(0, Timeline.padding + (scrollY - Timeline.padding) * height / previous)
            position.scrollTo(y: y)
        }
    }

    // MARK: Layout

    private func dayTimeline(_ items: DayItems?) -> DayTimeline {
        // Reminders and alarms are drawn at a fixed height, and short events at a minimum one, so
        // they're laid out with the minutes that height covers at this zoom.
        DayTimeline(day: date, items: items, alarms: alarms.alarms(on: date),
                    pointMinutes: Double((Timeline.reminderHeight + 2) / hourHeight * 60),
                    minMinutes: Double((Timeline.minBlockHeight + 2) / hourHeight * 60))
    }

    private func activeDraft(_ items: DayItems?) -> Draft? {
        guard let draft, draft.basis == items else { return nil }
        return draft
    }

    private func isSelected(_ key: String, _ items: DayItems?) -> Bool {
        if key == selectedKey { return true }
        guard let active = activeDraft(items) else { return false }
        return active.key == key && active.savedKey == selectedKey
    }

    private func minute(atY y: CGFloat) -> Double {
        // Snap to the quarter hour like Calendar does.
        let raw = Double((y - Timeline.padding) / hourHeight) * 4
        return max(0, min(23 * 60 + 45, raw.rounded() * 15))
    }

    // MARK: Views

    private func allDayArea(_ events: [CalendarEvent], _ reminders: [CalendarReminder]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("all-day")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: Timeline.gutter - 8, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(events) { event in
                    Button { TimeActions.openEvent(event, calendar: calendar) } label: {
                        Text(event.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(hex: event.color).opacity(0.22), in: .rect(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(reminders) { reminder in
                    ReminderChip(reminder: reminder, onPress: onPressReminder)
                }
            }
            .padding(.trailing, 8)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func timeline(_ timed: [PositionedItem<TimelineEntry>], items: DayItems?, width: CGFloat) -> some View {
        let columnWidth = width - Timeline.gutter - 8
        let active = activeDraft(items)
        let dragging = active?.dragging == true
        return ZStack(alignment: .topLeading) {
            // Touch and hold (on the Mac, double-click) empty space to create an event (or paste one); tap
            // it to deselect.
            Color.clear
                .contentShape(.rect)
                #if os(iOS)
                .onTapGesture {
                    onSelect(nil)
                    pasteMinute = nil
                }
                .gesture(LongPressRecognizer(action: holdEmpty))
                #else
                .onTapGesture(count: 2) { location in pressedEmpty(atY: location.y) }
                .onTapGesture {
                    onSelect(nil)
                    pasteMinute = nil
                }
                #endif
                .accessibilityHidden(true)

            HourGrid(hourHeight: hourHeight)
                .allowsHitTesting(false)

            ForEach(timed) { entry in
                switch entry.item {
                case .event(let event):
                    eventBlock(event, entry: entry, active: active, items: items, columnWidth: columnWidth)
                case .reminder(let reminder):
                    let w = columnWidth / CGFloat(entry.columns)
                    ReminderBlock(reminder: reminder, onPress: onPressReminder)
                        .frame(width: w - 2, height: Timeline.reminderHeight)
                        .offset(x: Timeline.gutter + CGFloat(entry.column) * w,
                                y: Timeline.y(minute: entry.range.startMinute, hourHeight: hourHeight))
                case .alarm(let alarm):
                    let w = columnWidth / CGFloat(entry.columns)
                    AlarmBlock(alarm: alarm) { model.time.alarmEditor = AlarmEditRequest(alarm: alarm) }
                        .frame(width: w - 2, height: Timeline.reminderHeight)
                        .offset(x: Timeline.gutter + CGFloat(entry.column) * w,
                                y: Timeline.y(minute: entry.range.startMinute, hourHeight: hourHeight))
                }
            }

            if Dates.isToday(date) {
                NowIndicator(hourHeight: hourHeight).allowsHitTesting(false)
            }
            if let newEvent {
                let frame = Timeline.blockFrame(newEvent.range, hourHeight: hourHeight)
                NewEventBlock(color: calendar.defaultEventColor, lifted: newEvent.lifted)
                    .frame(width: columnWidth - 2, height: frame.height)
                    .offset(x: Timeline.gutter, y: frame.top)
                    .allowsHitTesting(false)
                    .zIndex(6)
            }
            if let menu = menu(timed, active: active, items: items) {
                EditMenu(items: menu.items)
                    .frame(width: width)
                    .offset(y: menu.top)
            }
        }
        .frame(width: width, height: 24 * hourHeight + Timeline.padding * 2, alignment: .topLeading)
    }

    @ViewBuilder
    private func eventBlock(_ event: CalendarEvent, entry: PositionedItem<TimelineEntry>, active: Draft?, items: DayItems?,
                            columnWidth: CGFloat) -> some View {
        let range = active?.key == entry.key ? active!.range : entry.range
        let frame = Timeline.blockFrame(range, hourHeight: hourHeight)
        let w = columnWidth / CGFloat(entry.columns)
        let selected = isSelected(entry.key, items)
        let lifted = active?.key == entry.key && active?.dragging == true
        let draggable = event.canDrag(on: Dates.startOfDay(date))
        // Unselected events lift after a hold, like Calendar; selected ones move right away.
        let holdToDrag = lifted ? !(active?.fromSelected ?? false) : !selected
        // While dragging (or saving), show the time it's moving to.
        let start = event.start.addingTimeInterval((range.startMinute - entry.range.startMinute) * 60)
        EventBlock(event: event, height: frame.height, selected: selected, lifted: lifted,
                   editing: selected && draggable)
            .frame(width: w - 2, height: frame.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(event.title), \(Dates.formatTime(start))")
            #if os(iOS)
            .accessibilityHint(draggable ? "Touch and hold to move" : "")
            #endif
            .accessibilityAddTraits(.isButton)
            #if os(iOS)
            .onTapGesture {
                guard active?.dragging != true, Date().timeIntervalSince(lastDragEnd) > 0.5 else { return }
                onSelect(nil)
                TimeActions.openEvent(event, calendar: calendar)
            }
            // Read-only events can still be long-pressed to select them for Copy and Duplicate.
            .gesture(LongPressRecognizer(isEnabled: holdToDrag) { phase in
                drag(event, entry: entry, mode: .move, phase: phase, items: items)
            })
            .gesture(PanRecognizer(isEnabled: !holdToDrag && draggable) { phase in
                drag(event, entry: entry, mode: .move, phase: phase, items: items)
            })
            #else
            // Like Calendar on the Mac: click to select, double-click to open, drag to move.
            .onTapGesture(count: 2) {
                onSelect(nil)
                TimeActions.openEvent(event, calendar: calendar)
            }
            .onTapGesture {
                pasteMinute = nil
                onSelect(entry.key)
            }
            .onDragPhases(isEnabled: draggable) { phase in
                drag(event, entry: entry, mode: .move, phase: phase, items: items)
            }
            #endif
            .overlay(alignment: .topTrailing) {
                if selected && draggable {
                    // Like Calendar: the start handle sits on the top edge at the right, the end handle
                    // on the bottom edge at the left.
                    Handle(color: event.color)
                        #if os(iOS)
                        .gesture(PanRecognizer { drag(event, entry: entry, mode: .start, phase: $0, items: items) })
                        #else
                        .onDragPhases { drag(event, entry: entry, mode: .start, phase: $0, items: items) }
                        #endif
                        .accessibilityLabel("Change start time")
                        .offset(x: Timeline.handleHit / 2 - 12, y: -Timeline.handleHit / 2)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if selected && draggable {
                    Handle(color: event.color)
                        #if os(iOS)
                        .gesture(PanRecognizer { drag(event, entry: entry, mode: .end, phase: $0, items: items) })
                        #else
                        .onDragPhases { drag(event, entry: entry, mode: .end, phase: $0, items: items) }
                        #endif
                        .accessibilityLabel("Change end time")
                        .offset(x: 24 - Timeline.handleHit / 2, y: Timeline.handleHit / 2)
                }
            }
            .offset(x: Timeline.gutter + CGFloat(entry.column) * w, y: frame.top)
            .zIndex(lifted ? 5 : selected ? 1 : 0)
    }

    private func menu(_ timed: [PositionedItem<TimelineEntry>], active: Draft?, items: DayItems?)
        -> (top: CGFloat, items: [EditMenu.Item])? {
        if active?.dragging != true,
           let entry = timed.first(where: { if case .event = $0.item { isSelected($0.key, items) } else { false } }),
           case .event(let event) = entry.item {
            let range = active?.key == entry.key ? active!.range : entry.range
            let frame = Timeline.blockFrame(range, hourHeight: hourHeight)
            func done(_ action: @escaping (CalendarEvent) -> Void) -> () -> Void {
                { onSelect(nil); action(event) }
            }
            let copy = EditMenu.Item(label: "Copy", action: done { TimeActions.copy($0) })
            let duplicate = EditMenu.Item(label: "Duplicate", action: done { TimeActions.duplicate($0, calendar: calendar) })
            let menuItems = event.editable
                ? [
                    EditMenu.Item(label: "Cut", action: done { e in Task { await TimeActions.cut(e, calendar: calendar) } }),
                    copy,
                    EditMenu.Item(label: "Delete", destructive: true,
                                  action: done { e in Task { await TimeActions.delete(e, calendar: calendar) } }),
                    duplicate,
                    EditMenu.Item(label: "Place…", action: done { e in
                        Task {
                            if let span = await TimeActions.chooseSpan(e, verb: "Save") { onSetPlace(e, span) }
                        }
                    }),
                ]
                : [copy, duplicate]
            let above = frame.top - Timeline.menuHeight - 10
            return (above >= 0 ? above : frame.top + frame.height + 10, menuItems)
        }
        if let pasteMinute {
            let top = Timeline.y(minute: pasteMinute, hourHeight: hourHeight) - Timeline.menuHeight - 10
            let at = Dates.date(date, atMinute: Int(pasteMinute))
            return (max(0, top), [
                EditMenu.Item(label: "Paste") {
                    self.pasteMinute = nil
                    TimeActions.paste(at: at, calendar: calendar)
                },
                EditMenu.Item(label: "New Event") {
                    self.pasteMinute = nil
                    createEvent(MinuteRange(startMinute: pasteMinute, endMinute: pasteMinute + 60))
                },
            ])
        }
        return nil
    }

    // MARK: Gestures

    private func pressedEmpty(atY y: CGFloat) {
        let minute = minute(atY: y)
        onSelect(nil)
        if TimeActions.clipboard != nil {
            pasteMinute = minute
        } else {
            createEvent(MinuteRange(startMinute: minute, endMinute: min(24 * 60, minute + 60)))
        }
    }

    /// Shows a new event's block and opens its editor; the block goes once the editor closes, and the
    /// event, if it was saved, takes its place.
    private func createEvent(_ range: MinuteRange) {
        newEvent = NewEventDraft(range: range, lifted: false)
        let start = Dates.date(date, atMinute: Int(range.startMinute))
        Task { await TimeActions.createEvent(start: start, calendar: calendar) { newEvent = nil } }
    }

    /// Like Calendar: touch and hold empty space and an hour-long event appears under your finger;
    /// drag it into place, and let go to open its editor.
    private func holdEmpty(_ phase: GesturePhase) {
        switch phase.state {
        case .began:
            // With an event copied, holding offers to paste it instead.
            guard TimeActions.clipboard == nil, newEvent == nil else {
                pressedEmpty(atY: phase.localLocation.y)
                return
            }
            onSelect(nil)
            pasteMinute = nil
            let finger = Double((phase.localLocation.y - Timeline.padding) / hourHeight * 60)
            let start = max(0, min(23 * 60, Editing.snap(finger - 30)))
            let range = MinuteRange(startMinute: start, endMinute: start + 60)
            newEventOrigin = (range, phase.location.y)
            newEvent = NewEventDraft(range: range, lifted: true)
            onGestureActive(true)
            Haptics.impact()
        case .changed:
            guard let origin = newEventOrigin, var current = newEvent else { return }
            let delta = Double((phase.location.y - origin.y) / hourHeight * 60)
            let range = Editing.drag(origin.range, mode: .move, deltaMinutes: delta)
            guard range != current.range else { return }
            current.range = range
            newEvent = current
            Haptics.selection()
        case .ended:
            guard newEventOrigin != nil, let current = newEvent else { return }
            newEventOrigin = nil
            onGestureActive(false)
            withAnimation(.snappy(duration: 0.2)) { newEvent?.lifted = false }
            let start = Dates.date(date, atMinute: Int(current.range.startMinute))
            Task { await TimeActions.createEvent(start: start, calendar: calendar) { newEvent = nil } }
        case .cancelled:
            guard newEventOrigin != nil else { return }
            newEventOrigin = nil
            newEvent = nil
            onGestureActive(false)
        }
    }

    private func drag(_ event: CalendarEvent, entry: PositionedItem<TimelineEntry>, mode: DragMode, phase: GesturePhase,
                      items: DayItems?) {
        switch phase.state {
        case .began:
            let active = activeDraft(items)
            let pending = active?.key == entry.key ? active : nil
            let origin = pending?.range ?? entry.range
            let wasSelected = isSelected(entry.key, items)
            dragOrigin = origin
            dragStartY = phase.location.y
            draft = Draft(key: entry.key, savedKey: pending?.savedKey ?? entry.key, range: origin, dragging: true,
                          fromSelected: wasSelected, basis: items)
            pasteMinute = nil
            if !wasSelected { onSelect(entry.key) }
            onGestureActive(true)
            Haptics.impact()
        case .changed:
            guard event.canDrag(on: Dates.startOfDay(date)), let origin = dragOrigin else { return }
            let delta = Double((phase.location.y - dragStartY) / hourHeight * 60)
            let range = Editing.drag(origin, mode: mode, deltaMinutes: delta)
            guard var current = draft, current.key == entry.key, current.range != range else { return }
            current.range = range
            draft = current
            Haptics.selection()
        case .ended, .cancelled:
            onGestureActive(false)
            lastDragEnd = Date()
            dragOrigin = nil
            guard var current = draft, current.key == entry.key else { return }
            let range = current.range
            let moved = range != entry.range
            if phase.state == .cancelled || !moved {
                draft = nil
                return
            }
            let times = Editing.apply(start: event.start, end: event.end, from: entry.range, to: range)
            let savedKey = CalendarEvent.key(eventId: event.eventId, start: times.start)
            current.savedKey = savedKey
            current.dragging = false
            draft = current
            onSelect(savedKey)
            Task {
                let saved = await TimeActions.reschedule(event, start: times.start, end: times.end, calendar: calendar)
                if !saved {
                    draft = nil
                    onSelect(entry.key)
                }
            }
        }
    }

    /// Pinch to zoom. The minute under your fingers stays put.
    private func handlePinch(_ phase: GesturePhase) {
        switch phase.state {
        case .began:
            let focalY = phase.localLocation.y
            pinch = (hourHeight, Double((scrollY + focalY - Timeline.padding) / hourHeight * 60), focalY)
            onGestureActive(true)
        case .changed:
            guard let start = pinch else { return }
            let next = (min(Timeline.maxHourHeight, max(Timeline.minHourHeight, start.height * phase.scale))).rounded()
            guard next != hourHeight else { return }
            let y = max(0, Timeline.padding + CGFloat(start.minute) / 60 * next - start.focalY)
            hourHeight = next
            lastHourHeight = next
            position.scrollTo(y: y)
            scroll.y = y
        case .ended, .cancelled:
            guard pinch != nil else { return }
            pinch = nil
            onGestureActive(false)
            onZoomEnd()
        }
    }
}

private struct HourGrid: View {
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...24, id: \.self) { hour in
                HStack(spacing: 0) {
                    Text(hour == 0 || hour == 24 ? "12 AM" : Dates.formatHour(Dates.date(year: 2026, month: 1, day: 1, hour: hour)))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: Timeline.gutter - 8, alignment: .trailing)
                        .padding(.trailing, 8)
                    Rectangle().fill(Theme.hourLine).frame(height: 1 / 3)
                }
                .frame(height: 16)
                .offset(y: Timeline.padding + CGFloat(hour) * hourHeight - 8)
            }
        }
    }
}

private struct EventBlock: View {
    let event: CalendarEvent
    let height: CGFloat
    let selected: Bool
    let lifted: Bool
    let editing: Bool

    var body: some View {
        let color = Color(hex: event.color)
        let textColor = selected ? Color.white : Color.primary
        // The block's position already says when it is, so it shows the title, plus the location when
        // there's a spare line for it.
        let inner = height - Timeline.blockPadding * 2
        let showLocation = event.location != nil && inner >= Timeline.titleLine + Timeline.subtitleLine
        let titleLines = max(1, Int(((showLocation ? inner - Timeline.subtitleLine : inner) / Timeline.titleLine)))
        VStack(alignment: .leading, spacing: 0) {
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(titleLines)
            if showLocation, let location = event.location {
                Text(location.replacingOccurrences(of: "\n", with: ", "))
                    .font(.system(size: 11))
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 5)
        .padding(.vertical, Timeline.blockPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(selected ? color : color.opacity(0.22))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 4))
        .background {
            if lifted {
                RoundedRectangle(cornerRadius: 4).fill(color).shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            } else if !selected {
                RoundedRectangle(cornerRadius: 4).fill(Theme.background)
            }
        }
    }
}

/// A new event's block, in the calendar it'll be saved to. It pops in, like Calendar's, and has
/// handles once it's set down (only to show it can be resized; the editor sets its times).
private struct NewEventBlock: View {
    let color: String
    let lifted: Bool
    @State private var popped = false

    var body: some View {
        Text("New Event")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, Timeline.blockPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hex: color), in: .rect(cornerRadius: 4))
            .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: 8, y: 4)
            .overlay(alignment: .topTrailing) {
                if !lifted {
                    Handle(color: color).offset(x: Timeline.handleHit / 2 - 12, y: -Timeline.handleHit / 2)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !lifted {
                    Handle(color: color).offset(x: 24 - Timeline.handleHit / 2, y: Timeline.handleHit / 2)
                }
            }
            .scaleEffect(popped ? 1 : 1.08)
            .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.45)) { popped = true } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("New Event")
    }
}

private struct Handle: View {
    let color: String

    var body: some View {
        Circle()
            .fill(.white)
            .stroke(Color(hex: color), lineWidth: 2)
            .frame(width: 11, height: 11)
            .frame(width: Timeline.handleHit, height: Timeline.handleHit)
            .contentShape(.rect)
    }
}

private struct ReminderCheck: View {
    let reminder: CalendarReminder
    var size: CGFloat = 16
    @Environment(CalendarStore.self) private var calendar

    var body: some View {
        Button {
            do { try calendar.toggleReminder(reminder) } catch {
                Presenter.showError("Couldn’t Update Reminder", error)
            }
        } label: {
            Image(systemName: reminder.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size))
                .foregroundStyle(Color(hex: reminder.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reminder.title)
        .accessibilityValue(reminder.completed ? "Completed" : "Not completed")
    }
}

private struct ReminderBlock: View {
    let reminder: CalendarReminder
    let onPress: (CalendarReminder) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ReminderCheck(reminder: reminder)
            Text(reminder.title)
                .font(.system(size: 12, weight: .semibold))
                .strikethrough(reminder.completed)
                .opacity(reminder.completed ? 0.5 : 1)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .background(Theme.background, in: .rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color(hex: reminder.color), lineWidth: 1) }
        .contentShape(.rect)
        .onTapGesture { onPress(reminder) }
        .accessibilityElement(children: .combine)
    }
}

/// An alarm at its time on the timeline; tap it to change or delete it.
private struct AlarmBlock: View {
    let alarm: SpacetimeAlarm
    let onPress: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: alarm.repeats ? "alarm.waves.left.and.right.fill" : "alarm.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.alarm)
            Text(alarm.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .background(Theme.background, in: .rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(Theme.alarm, lineWidth: 1) }
        .contentShape(.rect)
        .onTapGesture(perform: onPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alarm, \(alarm.title), \(Dates.formatTime(Dates.date(Date(), atMinute: alarm.minuteOfDay)))")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ReminderChip: View {
    let reminder: CalendarReminder
    let onPress: (CalendarReminder) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ReminderCheck(reminder: reminder)
            Text(reminder.title)
                .font(.system(size: 13, weight: .semibold))
                .strikethrough(reminder.completed)
                .opacity(reminder.completed ? 0.5 : 1)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color(hex: reminder.color), lineWidth: 1) }
        .contentShape(.rect)
        .onTapGesture { onPress(reminder) }
    }
}

private struct NowIndicator: View {
    let hourHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            HStack(spacing: 0) {
                Text(Dates.formatTime(now))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tint)
                    .frame(width: Timeline.gutter - 4, alignment: .trailing)
                    .padding(.trailing, 4)
                    .background(Theme.background)
                Rectangle().fill(Theme.tint).frame(height: 2)
            }
            .frame(height: 16)
            .offset(y: Timeline.y(minute: Double(Dates.minutesIntoDay(now)), hourHeight: hourHeight) - 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current time, \(Dates.formatTime(now))")
        }
    }
}

/// A horizontal action bar like iOS's edit menu (Cut · Copy · Delete · Duplicate).
struct EditMenu: View {
    struct Item {
        var label: String
        var destructive = false
        var action: () -> Void
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider().frame(height: 18) }
                Button(action: item.action) {
                    Text(item.label)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.destructive ? Theme.tint : .primary)
                        .padding(.horizontal, 14)
                        .frame(height: Timeline.menuHeight - 8)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: Timeline.menuHeight)
        .glass(in: .capsule, interactive: true)
    }
}
