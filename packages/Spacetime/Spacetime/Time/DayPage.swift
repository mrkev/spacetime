import SwiftUI

/// Where a dragged event is drawn until the calendar reloads with its saved times. `basis` is the
/// day's data at drag time; once that's replaced, the draft is stale and the real times show.
private struct Draft {
    var key: String
    /// The event's key once saved (keys include the start time).
    var savedKey: String
    var range: MinuteRange
    /// The finger moving it, until it's let go.
    var drag: BlockDrag?
    /// Whether the event was already selected (so it moved right away instead of after a hold).
    var fromSelected: Bool
    var basis: DayItems?

    var dragging: Bool { drag != nil }
}

/// A new event's block, held where it'll go until its editor closes.
private struct NewEventDraft {
    var range: MinuteRange
    /// The finger dragging it into place, until it's let go.
    var drag: BlockDrag?

    var lifted: Bool { drag != nil }
}

/// What a day page asks of the day view it's in.
struct DayPageActions {
    /// Selects an event on this day by key, or deselects.
    var select: (String?) -> Void
    /// Stops the pager paging while an event is dragged or the day is pinched.
    var gestureActive: (Bool) -> Void
    var zoomEnded: () -> Void
    var pressReminder: (CalendarReminder) -> Void
    var setPlace: (CalendarEvent, Span) -> Void
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
    let actions: DayPageActions

    @Environment(AppModel.self) private var model
    @Environment(CalendarStore.self) private var calendar
    @Environment(AlarmStore.self) private var alarms
    @State private var position: ScrollPosition
    @State private var scrollY: CGFloat = 0
    @State private var draft: Draft?
    /// Lifting your finger after a drag also ends the press, which would otherwise open the event.
    @State private var lastDragEnd = Date.distantPast
    /// Long-pressing empty space while an event is copied offers to paste it there.
    @State private var pasteMinute: Double?
    @State private var pinch: TimelinePinch?
    @State private var newEvent: NewEventDraft?
    @State private var handledScrollToNow = 0
    @State private var lastHourHeight: CGFloat = 0

    init(date: Date, isCurrent: Bool, scroll: TimelineScroll, hourHeight: Binding<CGFloat>, scrollToNow: Int,
         selectedKey: String?, actions: DayPageActions) {
        self.date = date
        self.isCurrent = isCurrent
        self.scroll = scroll
        _hourHeight = hourHeight
        self.scrollToNow = scrollToNow
        self.selectedKey = selectedKey
        self.actions = actions
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
            position.scrollTo(y: Timeline.scrollY(scrollY, rescaledFrom: previous, to: height))
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
                    ReminderChip(reminder: reminder, onPress: actions.pressReminder)
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
                    actions.select(nil)
                    pasteMinute = nil
                }
                .gesture(LongPressRecognizer(action: holdEmpty))
                #else
                .onTapGesture(count: 2) { location in pressedEmpty(atY: location.y) }
                .onTapGesture {
                    actions.select(nil)
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
                    ReminderBlock(reminder: reminder, onPress: actions.pressReminder)
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
                actions.select(nil)
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
                actions.select(nil)
                TimeActions.openEvent(event, calendar: calendar)
            }
            .onTapGesture {
                pasteMinute = nil
                actions.select(entry.key)
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
                { actions.select(nil); action(event) }
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
                            if let span = await TimeActions.chooseSpan(e, verb: "Save") { actions.setPlace(e, span) }
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
        actions.select(nil)
        if TimeActions.clipboard != nil {
            pasteMinute = minute
        } else {
            createEvent(MinuteRange(startMinute: minute, endMinute: min(24 * 60, minute + 60)))
        }
    }

    /// Shows a new event's block and opens its editor; the block goes once the editor closes, and the
    /// event, if it was saved, takes its place.
    private func createEvent(_ range: MinuteRange) {
        newEvent = NewEventDraft(range: range)
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
            actions.select(nil)
            pasteMinute = nil
            let finger = Double((phase.localLocation.y - Timeline.padding) / hourHeight * 60)
            let start = max(0, min(23 * 60, Editing.snap(finger - 30)))
            let range = MinuteRange(startMinute: start, endMinute: start + 60)
            newEvent = NewEventDraft(range: range, drag: BlockDrag(mode: .move, origin: range, startY: phase.location.y))
            actions.gestureActive(true)
            Haptics.impact()
        case .changed:
            guard let current = newEvent, let drag = current.drag else { return }
            let range = drag.range(atY: phase.location.y, hourHeight: hourHeight)
            guard range != current.range else { return }
            newEvent?.range = range
            Haptics.selection()
        case .ended:
            guard let current = newEvent, current.lifted else { return }
            actions.gestureActive(false)
            withAnimation(.snappy(duration: 0.2)) { newEvent?.drag = nil }
            let start = Dates.date(date, atMinute: Int(current.range.startMinute))
            Task { await TimeActions.createEvent(start: start, calendar: calendar) { newEvent = nil } }
        case .cancelled:
            guard newEvent?.lifted == true else { return }
            newEvent = nil
            actions.gestureActive(false)
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
            draft = Draft(key: entry.key, savedKey: pending?.savedKey ?? entry.key, range: origin,
                          drag: BlockDrag(mode: mode, origin: origin, startY: phase.location.y),
                          fromSelected: wasSelected, basis: items)
            pasteMinute = nil
            if !wasSelected { actions.select(entry.key) }
            actions.gestureActive(true)
            Haptics.impact()
        case .changed:
            guard event.canDrag(on: Dates.startOfDay(date)), let current = draft, current.key == entry.key,
                  let drag = current.drag else { return }
            let range = drag.range(atY: phase.location.y, hourHeight: hourHeight)
            guard range != current.range else { return }
            draft?.range = range
            Haptics.selection()
        case .ended, .cancelled:
            actions.gestureActive(false)
            lastDragEnd = Date()
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
            current.drag = nil
            draft = current
            actions.select(savedKey)
            Task {
                let saved = await TimeActions.reschedule(event, start: times.start, end: times.end, calendar: calendar)
                if !saved {
                    draft = nil
                    actions.select(entry.key)
                }
            }
        }
    }

    /// Pinch to zoom. The minute under your fingers stays put.
    private func handlePinch(_ phase: GesturePhase) {
        switch phase.state {
        case .began:
            pinch = TimelinePinch(hourHeight: hourHeight, scrollY: scrollY, focalY: phase.localLocation.y)
            actions.gestureActive(true)
        case .changed:
            guard let pinch else { return }
            let next = pinch.hourHeight(scale: phase.scale)
            guard next != hourHeight else { return }
            let y = pinch.scrollY(hourHeight: next)
            hourHeight = next
            lastHourHeight = next
            position.scrollTo(y: y)
            scroll.y = y
        case .ended, .cancelled:
            guard pinch != nil else { return }
            pinch = nil
            actions.gestureActive(false)
            actions.zoomEnded()
        }
    }
}
