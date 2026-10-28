import * as Haptics from 'expo-haptics';
import {
  createContext,
  memo,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  type GestureResponderEvent,
  type ScrollViewInstance,
} from 'react-native';
import {
  GestureDetector,
  usePanGesture,
  usePinchGesture,
  type PanGestureConfig,
  type PinchGesture,
  type PinchGestureConfig,
} from 'react-native-gesture-handler';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon, icons } from '../components/Icon';
import { addDays, formatHour, formatTime, isToday, minutesIntoDay, startOfDay } from '../lib/dates';
import { useTheme, withAlpha, type Theme } from '../lib/theme';
import {
  eventKey,
  useCalendar,
  type CalendarEvent,
  type CalendarReminder,
  type DayItems,
} from './CalendarProvider';
import { EDIT_MENU_HEIGHT, EditMenu, type EditMenuItem } from './EditMenu';
import { useTimeActions } from './actions';
import {
  applyRange,
  canDrag,
  dragRange,
  getCopiedEvent,
  type DragMode,
  type MinuteRange,
} from './editing';
import { layoutDay, type PositionedItem, type TimedItem } from './layout';

/** How tall an hour is by default; pinching zooms between the min and max. */
export const HOUR_HEIGHT = 56;
export const MIN_HOUR_HEIGHT = 24;
export const MAX_HOUR_HEIGHT = 180;
const GUTTER = 56;
export const TIMELINE_PADDING = 12;
/** Reminders are points in time, so they stay this tall at any zoom. */
const REMINDER_HEIGHT = 26;
const MIN_BLOCK_HEIGHT = 20;
/** How long to hold an event before it lifts for dragging. */
const LONG_PRESS_MS = 350;
const HANDLE_HIT = 44;
// Event text uses fixed line heights so blocks can work out how many lines fit.
const TITLE_LINE = 15;
const SUBTITLE_LINE = 14;
const BLOCK_PADDING = 2;

type Props = {
  date: Date;
  width: number;
  /** Where the timeline starts scrolled to; shared across pages so swiping keeps the time of day. */
  initialScrollY: number;
  onScrollY: (y: number) => void;
  onPressEvent: (event: CalendarEvent) => void;
  onToggleReminder: (reminder: CalendarReminder) => void;
  onPressReminder: (reminder: CalendarReminder) => void;
  onCreateAt: (start: Date) => void;
  /** The selected (editable) event's key, if it's on this day. */
  selectedKey: string | null;
  onSelect: (key: string | null) => void;
  /** Lets the pager stop paging while an event is dragged or the day is pinched. */
  onGestureActive: (active: boolean) => void;
  /** Points per hour; pinching changes it for every day. */
  hourHeight: number;
  onZoom: (hourHeight: number) => void;
  onZoomEnd: () => void;
  /** Bumped to scroll today's page to the current time (the Today button). */
  scrollToNow: number;
};

/** Where the timeline scrolls to show the current time: an hour above it. */
export function nowOffset(hourHeight: number) {
  return Math.max(0, (minutesIntoDay(new Date()) / 60 - 1) * hourHeight);
}

/**
 * Where a dragged event is drawn until the calendar reloads with its saved times. `basis` is the
 * day's data at drag time; once that's replaced, the draft is stale and the real times show.
 */
type Draft = {
  key: string;
  /** The event's key once saved (keys include the start time). */
  savedKey: string;
  range: MinuteRange;
  dragging: boolean;
  /** Whether the event was already selected (so it moved right away instead of after a hold). */
  fromSelected: boolean;
  basis: DayItems | undefined;
};

/**
 * The day's pinch-to-zoom gesture. Event drags run alongside it, so a pinch that starts on an
 * event still zooms instead of waiting on the event's long press.
 */
const PinchContext = createContext<PinchGesture | undefined>(undefined);

type TimelineEntry =
  | (TimedItem & { kind: 'event'; event: CalendarEvent })
  | (TimedItem & { kind: 'reminder'; reminder: CalendarReminder });

/** Sorts a day's items into the all-day area and the laid-out timeline. */
function splitDay(items: DayItems | undefined, date: Date, hourHeight: number) {
  const dayStart = startOfDay(date);
  const dayEnd = addDays(dayStart, 1);
  const allDayEvents: CalendarEvent[] = [];
  const allDayReminders: CalendarReminder[] = [];
  const timed: TimelineEntry[] = [];

  for (const event of items?.events ?? []) {
    // Events spanning the whole day (or flagged all-day) go in the all-day area.
    if (event.allDay || (event.start <= dayStart && event.end >= dayEnd)) {
      allDayEvents.push(event);
      continue;
    }
    const startMinute = event.start < dayStart ? 0 : minutesIntoDay(event.start);
    const endMinute = event.end >= dayEnd ? 24 * 60 : minutesIntoDay(event.end);
    timed.push({ kind: 'event', key: event.key, event, startMinute, endMinute });
  }
  for (const reminder of items?.reminders ?? []) {
    if (reminder.allDay || !reminder.due) {
      allDayReminders.push(reminder);
      continue;
    }
    // The time the block covers at this zoom, so overlaps are laid out side by side.
    const startMinute = minutesIntoDay(reminder.due);
    timed.push({
      kind: 'reminder',
      key: reminder.key,
      reminder,
      startMinute,
      endMinute: startMinute + ((REMINDER_HEIGHT + 2) / hourHeight) * 60,
    });
  }
  // Short blocks are drawn at a minimum height in points, so lay them out with the same room.
  const minMinutes = ((MIN_BLOCK_HEIGHT + 2) / hourHeight) * 60;
  return { allDayEvents, allDayReminders, timed: layoutDay(timed, minMinutes) };
}

export const DayPage = memo(function DayPage({
  date,
  width,
  initialScrollY,
  onScrollY,
  onPressEvent,
  onToggleReminder,
  onPressReminder,
  onCreateAt,
  selectedKey,
  onSelect,
  onGestureActive,
  hourHeight,
  onZoom,
  onZoomEnd,
  scrollToNow,
}: Props) {
  const theme = useTheme();
  const { rescheduleEvent, deleteEvent, duplicateEvent, cutEvent, copyEvent, pasteEvent } =
    useTimeActions();
  // The tab bar floats over content, so leave room to scroll the last hours above it.
  const { bottom } = useSafeAreaInsets();
  const { getDay, ensureMonths } = useCalendar();
  const items = getDay(date);

  useEffect(() => {
    ensureMonths(date, 0);
  }, [date, ensureMonths]);

  // React Compiler would memoize this anyway, but without the explicit memo its lint mistakes the
  // drag handlers passed into `timed.map` for code that runs during render.
  const { allDayEvents, allDayReminders, timed } = useMemo(
    () => splitDay(items, date, hourHeight),
    [items, date, hourHeight],
  );

  const today = isToday(date);
  // Captured once so re-renders don't fight the user's scrolling.
  const [initialOffset] = useState(() => ({ x: 0, y: initialScrollY }));
  const scrollRef = useRef<ScrollViewInstance>(null);
  const scrollY = useRef(initialScrollY);

  // Pinch to zoom. The minute under your fingers stays put: each update works out the offset that
  // keeps it there, and the layout effect below applies it once the taller (or shorter) day renders.
  const [pinching, setPinching] = useState(false);
  const pinchStart = useRef<{ height: number; minute: number; focalY: number } | null>(null);
  const zoomOffset = useRef<number | null>(null);
  const zoom = useRef({ hourHeight, onZoom, onZoomEnd, onGestureActive });
  useEffect(() => {
    zoom.current = { hourHeight, onZoom, onZoomEnd, onGestureActive };
  });
  const pinch = usePinchGesture(
    useMemo<PinchGestureConfig>(
      () => ({
        runOnJS: true,
        onActivate: (e) => {
          const height = zoom.current.hourHeight;
          const minute = ((scrollY.current + e.focalY - TIMELINE_PADDING) / height) * 60;
          pinchStart.current = { height, minute, focalY: e.focalY };
          setPinching(true);
          zoom.current.onGestureActive(true);
        },
        onUpdate: (e) => {
          const start = pinchStart.current;
          if (!start) return;
          const next = Math.round(
            Math.min(MAX_HOUR_HEIGHT, Math.max(MIN_HOUR_HEIGHT, start.height * e.scale)),
          );
          if (next === zoom.current.hourHeight) return;
          zoomOffset.current = TIMELINE_PADDING + (start.minute / 60) * next - start.focalY;
          zoom.current.onZoom(next);
        },
        onDeactivate: () => {
          pinchStart.current = null;
          setPinching(false);
          zoom.current.onGestureActive(false);
          zoom.current.onZoomEnd();
        },
      }),
      [],
    ),
  );

  // Other days (and this one, outside a pinch) keep the same time at the top when the zoom changes.
  // Only presses of Today after this page mounted; a page mounting on the way is already there.
  const handledScrollToNow = useRef(scrollToNow);
  useEffect(() => {
    if (scrollToNow === handledScrollToNow.current) return;
    handledScrollToNow.current = scrollToNow;
    if (isToday(date)) scrollRef.current?.scrollTo({ y: nowOffset(hourHeight), animated: true });
  }, [scrollToNow, date, hourHeight]);

  const lastHourHeight = useRef(hourHeight);
  useLayoutEffect(() => {
    const previous = lastHourHeight.current;
    if (previous === hourHeight) return;
    lastHourHeight.current = hourHeight;
    const y = Math.max(
      0,
      zoomOffset.current ??
        TIMELINE_PADDING + ((scrollY.current - TIMELINE_PADDING) * hourHeight) / previous,
    );
    zoomOffset.current = null;
    scrollY.current = y;
    scrollRef.current?.scrollTo({ y, animated: false });
  }, [hourHeight]);

  const [draft, setDraft] = useState<Draft | null>(null);
  const activeDraft = draft && draft.basis === items ? draft : null;
  const dragging = !!activeDraft?.dragging;
  // Where the current drag started (the drawn position, which may be an unsaved earlier drag)
  // and where it is now.
  const dragOrigin = useRef<MinuteRange | null>(null);
  const lastRange = useRef<MinuteRange | null>(null);
  // Lifting your finger after a drag also ends the press, which would otherwise open the event.
  const lastDragEnd = useRef(0);
  // Long-pressing empty space while an event is copied offers to paste it there.
  const [pasteMinute, setPasteMinute] = useState<number | null>(null);

  const dateAtMinute = (minute: number) => {
    const at = startOfDay(date);
    at.setMinutes(minute);
    return at;
  };

  const minuteAt = (e: GestureResponderEvent) => {
    const y = e.nativeEvent.locationY - TIMELINE_PADDING;
    // Snap to the quarter hour like Calendar does.
    return Math.max(0, Math.min(23 * 60 + 45, Math.round((y / hourHeight) * 4) * 15));
  };

  const onLongPress = (e: GestureResponderEvent) => {
    const minute = minuteAt(e);
    onSelect(null);
    if (getCopiedEvent()) {
      setPasteMinute(minute);
    } else {
      onCreateAt(dateAtMinute(minute));
    }
  };

  const onPressEmpty = () => {
    onSelect(null);
    setPasteMinute(null);
  };

  const isSelected = (key: string) =>
    key === selectedKey || (activeDraft?.key === key && activeDraft.savedKey === selectedKey);

  const startDrag = (entry: EventEntry) => {
    const pending = activeDraft?.key === entry.key ? activeDraft : null;
    const origin = pending?.range ?? entry;
    dragOrigin.current = origin;
    lastRange.current = { startMinute: origin.startMinute, endMinute: origin.endMinute };
    setDraft({
      key: entry.key,
      savedKey: pending?.savedKey ?? entry.key,
      range: lastRange.current,
      dragging: true,
      fromSelected: isSelected(entry.key),
      basis: items,
    });
    setPasteMinute(null);
    if (!isSelected(entry.key)) onSelect(entry.key);
    onGestureActive(true);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
  };

  const updateDrag = (entry: EventEntry, mode: DragMode, deltaMinutes: number) => {
    if (!canDrag(entry.event, startOfDay(date))) return;
    const range = dragRange(dragOrigin.current ?? entry, mode, deltaMinutes);
    const last = lastRange.current;
    if (last && last.startMinute === range.startMinute && last.endMinute === range.endMinute)
      return;
    lastRange.current = range;
    setDraft((d) => (d && d.key === entry.key ? { ...d, range } : d));
    Haptics.selectionAsync();
  };

  const endDrag = (entry: EventEntry, canceled: boolean) => {
    onGestureActive(false);
    lastDragEnd.current = Date.now();
    const range = lastRange.current;
    lastRange.current = null;
    dragOrigin.current = null;
    const moved =
      range && (range.startMinute !== entry.startMinute || range.endMinute !== entry.endMinute);
    if (canceled || !range || !moved) {
      setDraft(null);
      return;
    }
    const { start, end } = applyRange(entry.event, entry, range);
    const savedKey = eventKey(entry.event.source.id, start);
    setDraft((d) => (d && d.key === entry.key ? { ...d, range, savedKey, dragging: false } : d));
    onSelect(savedKey);
    rescheduleEvent(entry.event, start, end).then((saved) => {
      if (saved) return;
      setDraft(null);
      onSelect(entry.key);
    });
  };

  const columnWidth = width - GUTTER - 8;
  const rangeOf = (entry: PositionedItem<TimelineEntry>): MinuteRange =>
    activeDraft?.key === entry.key ? activeDraft.range : entry;

  // The edit menu sits above the selected event, or below it near the top of the day.
  const selectedEntry = timed.find(
    (entry): entry is PositionedItem<EventEntry> => entry.kind === 'event' && isSelected(entry.key),
  );
  let menu: { top: number; items: EditMenuItem[] } | null = null;
  if (selectedEntry && !dragging) {
    const { event } = selectedEntry;
    const { top, height } = blockFrame(rangeOf(selectedEntry), hourHeight);
    const done = (action: (event: CalendarEvent) => unknown) => () => {
      onSelect(null);
      action(event);
    };
    const items: EditMenuItem[] = event.editable
      ? [
          { label: 'Cut', onPress: done(cutEvent) },
          { label: 'Copy', onPress: done(copyEvent) },
          { label: 'Delete', destructive: true, onPress: done(deleteEvent) },
          { label: 'Duplicate', onPress: done(duplicateEvent) },
        ]
      : [
          { label: 'Copy', onPress: done(copyEvent) },
          { label: 'Duplicate', onPress: done(duplicateEvent) },
        ];
    const above = top - EDIT_MENU_HEIGHT - 10;
    menu = { top: above >= 0 ? above : top + height + 10, items };
  } else if (pasteMinute != null) {
    const top = TIMELINE_PADDING + (pasteMinute / 60) * hourHeight - EDIT_MENU_HEIGHT - 10;
    const at = dateAtMinute(pasteMinute);
    const close = (action: () => unknown) => () => {
      setPasteMinute(null);
      action();
    };
    menu = {
      top: Math.max(0, top),
      items: [
        { label: 'Paste', onPress: close(() => pasteEvent(at)) },
        { label: 'New Event', onPress: close(() => onCreateAt(at)) },
      ],
    };
  }

  return (
    <View style={{ width, flex: 1 }}>
      {allDayEvents.length + allDayReminders.length > 0 ? (
        <View style={[styles.allDay, { borderBottomColor: theme.separator }]}>
          <Text style={[styles.allDayLabel, { color: theme.secondaryText }]}>all-day</Text>
          <View style={styles.allDayItems}>
            {allDayEvents.map((event) => (
              <Pressable
                key={event.key}
                onPress={() => onPressEvent(event)}
                style={[styles.allDayEvent, { backgroundColor: withAlpha(event.color, 0.22) }]}
              >
                <Text style={[styles.allDayTitle, { color: theme.text }]} numberOfLines={1}>
                  {event.title}
                </Text>
              </Pressable>
            ))}
            {allDayReminders.map((reminder) => (
              <ReminderChip
                key={reminder.key}
                reminder={reminder}
                onToggle={onToggleReminder}
                onPress={onPressReminder}
                theme={theme}
              />
            ))}
          </View>
        </View>
      ) : null}

      {/* The pinch is detected on this wrapper so its focal point is relative to what's visible. */}
      <GestureDetector gesture={pinch}>
        <PinchContext.Provider value={pinch}>
          <View collapsable={false} style={styles.viewport}>
            <ScrollView
              ref={scrollRef}
              contentOffset={initialOffset}
              onScroll={(e) => {
                scrollY.current = e.nativeEvent.contentOffset.y;
                onScrollY(e.nativeEvent.contentOffset.y);
              }}
              scrollEventThrottle={32}
              scrollEnabled={!dragging && !pinching}
              showsVerticalScrollIndicator={false}
              contentContainerStyle={{ paddingBottom: bottom }}
            >
              <View style={{ height: 24 * hourHeight + TIMELINE_PADDING * 2 }}>
                {/* Long-press empty space to create an event. It's a layer behind the timeline rather
              than a wrapper, so it doesn't fold the events into one accessibility element, and
              locationY is always relative to the timeline itself. */}
                <Pressable
                  accessible={false}
                  style={StyleSheet.absoluteFill}
                  onPress={onPressEmpty}
                  onLongPress={onLongPress}
                  delayLongPress={LONG_PRESS_MS}
                />
                <HourGrid theme={theme} hourHeight={hourHeight} />
                <View
                  pointerEvents="box-none"
                  style={[styles.events, { left: GUTTER, width: columnWidth }]}
                >
                  {timed.map((entry) =>
                    entry.kind === 'event' ? (
                      <EventBlock
                        key={entry.key}
                        entry={entry}
                        range={rangeOf(entry)}
                        selected={isSelected(entry.key)}
                        lifted={activeDraft?.key === entry.key && dragging}
                        holdToDrag={
                          activeDraft?.key === entry.key && dragging
                            ? !activeDraft.fromSelected
                            : !isSelected(entry.key)
                        }
                        draggable={canDrag(entry.event, startOfDay(date))}
                        width={columnWidth}
                        hourHeight={hourHeight}
                        theme={theme}
                        onPress={() => {
                          if (dragging || Date.now() - lastDragEnd.current < 500) return;
                          onSelect(null);
                          onPressEvent(entry.event);
                        }}
                        onDragStart={startDrag}
                        onDrag={updateDrag}
                        onDragEnd={endDrag}
                      />
                    ) : (
                      <ReminderBlock
                        key={entry.key}
                        entry={entry}
                        width={columnWidth}
                        hourHeight={hourHeight}
                        theme={theme}
                        onToggle={onToggleReminder}
                        onPress={onPressReminder}
                      />
                    ),
                  )}
                </View>
                {today ? <NowIndicator theme={theme} hourHeight={hourHeight} /> : null}
                {activeDraft && dragging ? (
                  <DragTimes
                    range={activeDraft.range}
                    date={date}
                    theme={theme}
                    hourHeight={hourHeight}
                  />
                ) : null}
                {menu ? <EditMenu top={menu.top} items={menu.items} /> : null}
              </View>
            </ScrollView>
          </View>
        </PinchContext.Provider>
      </GestureDetector>
    </View>
  );
});

type EventEntry = Extract<TimelineEntry, { kind: 'event' }>;

function blockFrame(range: MinuteRange, hourHeight: number) {
  return {
    top: TIMELINE_PADDING + (range.startMinute / 60) * hourHeight,
    height: Math.max(
      MIN_BLOCK_HEIGHT,
      ((range.endMinute - range.startMinute) / 60) * hourHeight - 2,
    ),
  };
}

function HourGrid({ theme, hourHeight }: { theme: Theme; hourHeight: number }) {
  return (
    <>
      {Array.from({ length: 25 }, (_, hour) => {
        const label = hour === 0 || hour === 24 ? '12 AM' : formatHour(new Date(2026, 0, 1, hour));
        return (
          <View
            key={hour}
            pointerEvents="none"
            style={[styles.hourRow, { top: TIMELINE_PADDING + hour * hourHeight }]}
          >
            <Text style={[styles.hourLabel, { color: theme.secondaryText }]}>{label}</Text>
            <View style={[styles.hourLine, { backgroundColor: theme.hourLine }]} />
          </View>
        );
      })}
    </>
  );
}

function ReminderBlock({
  entry,
  width,
  hourHeight,
  theme,
  onToggle,
  onPress,
}: {
  entry: PositionedItem<Extract<TimelineEntry, { kind: 'reminder' }>>;
  width: number;
  hourHeight: number;
  theme: Theme;
  onToggle: (reminder: CalendarReminder) => void;
  onPress: (reminder: CalendarReminder) => void;
}) {
  const { reminder } = entry;
  const columnWidth = width / entry.columns;
  const frame = {
    top: blockFrame(entry, hourHeight).top,
    height: REMINDER_HEIGHT,
    left: entry.column * columnWidth,
    width: columnWidth - 2,
  };
  return (
    <Pressable
      onPress={() => onPress(reminder)}
      accessibilityRole="button"
      accessibilityLabel={reminder.title}
      style={[styles.block, frame, styles.reminderBlock, { borderColor: reminder.color }]}
    >
      <ReminderCheck reminder={reminder} onToggle={onToggle} />
      <Text
        style={[styles.blockTitle, { color: theme.text }, reminder.completed && styles.completed]}
        numberOfLines={1}
      >
        {reminder.title}
      </Text>
    </Pressable>
  );
}

type DragHandlers = {
  onDragStart: (entry: EventEntry) => void;
  onDrag: (entry: EventEntry, mode: DragMode, deltaMinutes: number) => void;
  onDragEnd: (entry: EventEntry, canceled: boolean) => void;
};

/** Pan that drags an event (or one of its edges) along the timeline. */
function useDragGesture(
  entry: EventEntry,
  mode: DragMode,
  { enabled, longPress, hourHeight }: { enabled: boolean; longPress: boolean; hourHeight: number },
  handlers: DragHandlers,
) {
  // Every new config is re-sent to the native recognizer, which resets it and cancels a drag in
  // progress. So the config only changes with `enabled`/`longPress` (which callers keep steady
  // mid-drag), and the callbacks read the latest props from a ref.
  const latest = useRef({ entry, handlers, hourHeight });
  useEffect(() => {
    latest.current = { entry, handlers, hourHeight };
  });
  const minutes = (translationY: number) => (translationY / latest.current.hourHeight) * 60;
  const pinch = useContext(PinchContext);
  const config = useMemo<PanGestureConfig>(
    () => ({
      enabled,
      runOnJS: true,
      // Unselected events lift after a hold, like Calendar; selected ones move right away.
      activateAfterLongPress: longPress ? LONG_PRESS_MS : undefined,
      minDistance: longPress ? undefined : 2,
      simultaneousWith: pinch,
      onActivate: () => latest.current.handlers.onDragStart(latest.current.entry),
      onUpdate: (e) =>
        latest.current.handlers.onDrag(latest.current.entry, mode, minutes(e.translationY)),
      onDeactivate: (e) => {
        const { entry, handlers } = latest.current;
        // The lift can carry movement that never got its own update.
        if (!e.canceled) handlers.onDrag(entry, mode, minutes(e.translationY));
        handlers.onDragEnd(entry, e.canceled);
      },
    }),
    [enabled, longPress, mode, pinch],
  );
  return usePanGesture(config);
}

function EventBlock({
  entry,
  range,
  selected,
  lifted,
  holdToDrag,
  draggable,
  width,
  hourHeight,
  theme,
  onPress,
  ...handlers
}: {
  entry: PositionedItem<EventEntry>;
  range: MinuteRange;
  selected: boolean;
  lifted: boolean;
  holdToDrag: boolean;
  draggable: boolean;
  width: number;
  hourHeight: number;
  theme: Theme;
  onPress: () => void;
} & DragHandlers) {
  const { event } = entry;
  const { top, height } = blockFrame(range, hourHeight);
  const columnWidth = width / entry.columns;
  const frame = { top, height, left: entry.column * columnWidth, width: columnWidth - 2 };
  const editing = selected && draggable;
  // The block's position already says when it is, so it shows the title, plus the location when
  // there's a spare line for it.
  const lines = Math.floor((height - BLOCK_PADDING * 2) / TITLE_LINE);
  const showLocation = !!event.location && height - BLOCK_PADDING * 2 >= TITLE_LINE + SUBTITLE_LINE;
  const titleLines = Math.max(
    1,
    showLocation ? Math.floor((height - BLOCK_PADDING * 2 - SUBTITLE_LINE) / TITLE_LINE) : lines,
  );
  // While dragging (or saving), show the time it's moving to.
  const start = new Date(event.start.getTime() + (range.startMinute - entry.startMinute) * 60_000);

  // Read-only events can still be long-pressed to select them for Copy and Duplicate.
  const move = useDragGesture(
    entry,
    'move',
    { enabled: lifted || !selected || draggable, longPress: holdToDrag, hourHeight },
    handlers,
  );
  const resizeStart = useDragGesture(
    entry,
    'start',
    { enabled: editing, longPress: false, hourHeight },
    handlers,
  );
  const resizeEnd = useDragGesture(
    entry,
    'end',
    { enabled: editing, longPress: false, hourHeight },
    handlers,
  );

  const textColor = selected ? '#FFFFFF' : theme.text;

  return (
    // Never flattened away: the lifted shadow would otherwise turn this into a new native view
    // mid-drag, re-parenting the event and cancelling the gesture.
    <View
      collapsable={false}
      pointerEvents="box-none"
      style={[
        styles.eventFrame,
        frame,
        // A solid background lets iOS draw the shadow from the shape instead of each pixel.
        lifted && [styles.lifted, { backgroundColor: event.color }],
      ]}
    >
      <GestureDetector gesture={move}>
        <Pressable
          onPress={onPress}
          accessibilityRole="button"
          accessibilityLabel={`${event.title}, ${formatTime(start)}`}
          accessibilityHint={draggable ? 'Touch and hold to move' : undefined}
          style={[
            styles.block,
            styles.fill,
            selected
              ? { backgroundColor: event.color, borderLeftColor: event.color }
              : { backgroundColor: withAlpha(event.color, 0.22), borderLeftColor: event.color },
          ]}
        >
          <Text style={[styles.eventTitle, { color: textColor }]} numberOfLines={titleLines}>
            {event.title}
          </Text>
          {showLocation ? (
            <Text style={[styles.eventSubtitle, { color: textColor }]} numberOfLines={1}>
              {event.location}
            </Text>
          ) : null}
        </Pressable>
      </GestureDetector>
      {editing ? (
        <>
          {/* Like Calendar: the start handle sits on the top edge at the right, the end handle on
              the bottom edge at the left. */}
          <GestureDetector gesture={resizeStart}>
            <View
              accessible
              accessibilityLabel="Change start time"
              style={[styles.handleHit, { top: -HANDLE_HIT / 2, right: 12 - HANDLE_HIT / 2 }]}
            >
              <View style={[styles.handleDot, { borderColor: event.color }]} />
            </View>
          </GestureDetector>
          <GestureDetector gesture={resizeEnd}>
            <View
              accessible
              accessibilityLabel="Change end time"
              style={[styles.handleHit, { bottom: -HANDLE_HIT / 2, left: 24 - HANDLE_HIT / 2 }]}
            >
              <View style={[styles.handleDot, { borderColor: event.color }]} />
            </View>
          </GestureDetector>
        </>
      ) : null}
    </View>
  );
}

/** While dragging, the gutter shows the times the event would start and end at. */
function DragTimes({
  range,
  date,
  theme,
  hourHeight,
}: {
  range: MinuteRange;
  date: Date;
  theme: Theme;
  hourHeight: number;
}) {
  const at = (minute: number) => {
    const d = startOfDay(date);
    d.setMinutes(minute);
    return formatTime(d);
  };
  return (
    <>
      {[range.startMinute, range.endMinute].map((minute, i) => (
        <Text
          key={i}
          pointerEvents="none"
          numberOfLines={1}
          adjustsFontSizeToFit
          minimumFontScale={0.7}
          style={[
            styles.dragTime,
            {
              top: TIMELINE_PADDING + (minute / 60) * hourHeight - 8,
              color: theme.text,
              backgroundColor: theme.background,
            },
          ]}
        >
          {at(minute)}
        </Text>
      ))}
    </>
  );
}

function ReminderCheck({
  reminder,
  onToggle,
}: {
  reminder: CalendarReminder;
  onToggle: (reminder: CalendarReminder) => void;
}) {
  return (
    <Pressable
      onPress={() => onToggle(reminder)}
      hitSlop={8}
      accessibilityRole="checkbox"
      accessibilityState={{ checked: reminder.completed }}
      accessibilityLabel={reminder.title}
    >
      <Icon
        name={reminder.completed ? icons.checkCircle : icons.circle}
        size={16}
        color={reminder.color}
      />
    </Pressable>
  );
}

function ReminderChip({
  reminder,
  onToggle,
  onPress,
  theme,
}: {
  reminder: CalendarReminder;
  onToggle: (reminder: CalendarReminder) => void;
  onPress: (reminder: CalendarReminder) => void;
  theme: Theme;
}) {
  return (
    <Pressable
      onPress={() => onPress(reminder)}
      accessibilityRole="button"
      accessibilityLabel={reminder.title}
      style={[styles.allDayEvent, styles.reminderChip, { borderColor: reminder.color }]}
    >
      <ReminderCheck reminder={reminder} onToggle={onToggle} />
      <Text
        style={[styles.allDayTitle, { color: theme.text }, reminder.completed && styles.completed]}
        numberOfLines={1}
      >
        {reminder.title}
      </Text>
    </Pressable>
  );
}

function NowIndicator({ theme, hourHeight }: { theme: Theme; hourHeight: number }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(id);
  }, []);
  const top = TIMELINE_PADDING + (minutesIntoDay(now) / 60) * hourHeight;
  return (
    <View
      pointerEvents="none"
      accessible
      accessibilityLabel={`Current time, ${formatTime(now)}`}
      style={[styles.nowRow, { top: top - 8 }]}
    >
      <Text style={[styles.nowLabel, { color: theme.tint, backgroundColor: theme.background }]}>
        {formatTime(now)}
      </Text>
      <View style={[styles.nowLine, { backgroundColor: theme.tint }]} />
    </View>
  );
}

const styles = StyleSheet.create({
  allDay: {
    flexDirection: 'row',
    paddingVertical: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  allDayLabel: { width: GUTTER, fontSize: 11, textAlign: 'right', paddingRight: 8, paddingTop: 4 },
  allDayItems: { flex: 1, gap: 2, paddingRight: 8 },
  allDayEvent: { borderRadius: 4, paddingHorizontal: 6, paddingVertical: 3 },
  allDayTitle: { fontSize: 13, fontWeight: '600', flexShrink: 1 },
  reminderChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: 1,
  },
  hourRow: {
    position: 'absolute',
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    height: 16,
    marginTop: -8,
  },
  hourLabel: { width: GUTTER, fontSize: 11, textAlign: 'right', paddingRight: 8 },
  hourLine: { flex: 1, height: StyleSheet.hairlineWidth },
  viewport: { flex: 1 },
  events: { position: 'absolute', top: 0, bottom: 0 },
  eventFrame: { position: 'absolute', borderRadius: 4 },
  lifted: {
    shadowColor: '#000000',
    shadowOpacity: 0.3,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
    // Over neighboring events while it moves.
    zIndex: 5,
  },
  fill: { top: 0, left: 0, right: 0, bottom: 0 },
  handleHit: {
    position: 'absolute',
    width: HANDLE_HIT,
    height: HANDLE_HIT,
    alignItems: 'center',
    justifyContent: 'center',
  },
  handleDot: {
    width: 11,
    height: 11,
    borderRadius: 5.5,
    borderWidth: 2,
    backgroundColor: '#FFFFFF',
  },
  dragTime: {
    position: 'absolute',
    left: 0,
    width: GUTTER - 2,
    height: 16,
    fontSize: 11,
    fontWeight: '600',
    textAlign: 'right',
    paddingRight: 2,
  },
  block: {
    position: 'absolute',
    borderRadius: 4,
    borderLeftWidth: 3,
    paddingHorizontal: 5,
    paddingVertical: BLOCK_PADDING,
    overflow: 'hidden',
  },
  reminderBlock: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: 1,
    borderLeftWidth: 1,
  },
  blockTitle: { fontSize: 12, fontWeight: '600', flexShrink: 1 },
  eventTitle: { fontSize: 12, lineHeight: TITLE_LINE, fontWeight: '600' },
  eventSubtitle: { fontSize: 11, lineHeight: SUBTITLE_LINE, opacity: 0.8 },
  completed: { textDecorationLine: 'line-through', opacity: 0.5 },
  nowRow: {
    position: 'absolute',
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    height: 16,
  },
  nowLabel: {
    width: GUTTER,
    fontSize: 11,
    fontWeight: '600',
    textAlign: 'right',
    paddingRight: 4,
  },
  nowLine: { flex: 1, height: 2 },
});
