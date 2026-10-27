import { memo, useEffect, useMemo, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  type GestureResponderEvent,
} from 'react-native';

import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon, icons } from '../components/Icon';
import {
  addDays,
  formatHour,
  formatTime,
  isToday,
  minutesIntoDay,
  startOfDay,
} from '../lib/dates';
import { useTheme, withAlpha, type Theme } from '../lib/theme';
import { useCalendar, type CalendarEvent, type CalendarReminder } from './CalendarProvider';
import { layoutDay, type PositionedItem, type TimedItem } from './layout';

export const HOUR_HEIGHT = 56;
const GUTTER = 56;
const TIMELINE_PADDING = 12;
const REMINDER_MINUTES = 30;

type Props = {
  date: Date;
  width: number;
  /** Where the timeline starts scrolled to; shared across pages so swiping keeps the time of day. */
  initialScrollY: number;
  onScrollY: (y: number) => void;
  onPressEvent: (event: CalendarEvent) => void;
  onToggleReminder: (reminder: CalendarReminder) => void;
  onCreateAt: (start: Date) => void;
};

type TimelineEntry =
  | (TimedItem & { kind: 'event'; event: CalendarEvent })
  | (TimedItem & { kind: 'reminder'; reminder: CalendarReminder });

export const DayPage = memo(function DayPage({
  date,
  width,
  initialScrollY,
  onScrollY,
  onPressEvent,
  onToggleReminder,
  onCreateAt,
}: Props) {
  const theme = useTheme();
  // The tab bar floats over content, so leave room to scroll the last hours above it.
  const { bottom } = useSafeAreaInsets();
  const { getDay, ensureMonths } = useCalendar();
  const items = getDay(date);

  useEffect(() => {
    ensureMonths(date, 0);
  }, [date, ensureMonths]);

  const { allDayEvents, allDayReminders, timed } = useMemo(() => {
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
      const startMinute = minutesIntoDay(reminder.due);
      timed.push({
        kind: 'reminder',
        key: reminder.key,
        reminder,
        startMinute,
        endMinute: Math.min(24 * 60, startMinute + REMINDER_MINUTES),
      });
    }
    return { allDayEvents, allDayReminders, timed: layoutDay(timed) };
  }, [items, date]);

  const today = isToday(date);
  // Captured once so re-renders don't fight the user's scrolling.
  const [initialOffset] = useState(() => ({ x: 0, y: initialScrollY }));

  const onLongPress = (e: GestureResponderEvent) => {
    const y = e.nativeEvent.locationY - TIMELINE_PADDING;
    // Snap to the quarter hour like Calendar does.
    const minutes = Math.max(0, Math.min(23 * 60 + 45, Math.round((y / HOUR_HEIGHT) * 4) * 15));
    const start = startOfDay(date);
    start.setMinutes(minutes);
    onCreateAt(start);
  };

  const columnWidth = width - GUTTER - 8;

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
                theme={theme}
              />
            ))}
          </View>
        </View>
      ) : null}

      <ScrollView
        contentOffset={initialOffset}
        onScroll={(e) => onScrollY(e.nativeEvent.contentOffset.y)}
        scrollEventThrottle={32}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: bottom }}
      >
        {/* Long-press empty space to create an event. Children don't take touches (except
            events), so locationY is always relative to the timeline itself. */}
        <Pressable onLongPress={onLongPress} delayLongPress={350}>
          <View style={{ height: 24 * HOUR_HEIGHT + TIMELINE_PADDING * 2 }}>
            <HourGrid theme={theme} />
            <View
              pointerEvents="box-none"
              style={[styles.events, { left: GUTTER, width: columnWidth }]}
            >
              {timed.map((entry) => (
                <TimelineBlock
                  key={entry.key}
                  entry={entry}
                  width={columnWidth}
                  theme={theme}
                  onPressEvent={onPressEvent}
                  onToggleReminder={onToggleReminder}
                />
              ))}
            </View>
            {today ? <NowIndicator theme={theme} /> : null}
          </View>
        </Pressable>
      </ScrollView>
    </View>
  );
});

const HourGrid = memo(function HourGrid({ theme }: { theme: Theme }) {
  return (
    <>
      {Array.from({ length: 25 }, (_, hour) => {
        const label = hour === 0 || hour === 24 ? '12 AM' : formatHour(new Date(2026, 0, 1, hour));
        return (
          <View
            key={hour}
            pointerEvents="none"
            style={[styles.hourRow, { top: TIMELINE_PADDING + hour * HOUR_HEIGHT }]}>
            <Text style={[styles.hourLabel, { color: theme.secondaryText }]}>{label}</Text>
            <View style={[styles.hourLine, { backgroundColor: theme.hourLine }]} />
          </View>
        );
      })}
    </>
  );
});

function TimelineBlock({
  entry,
  width,
  theme,
  onPressEvent,
  onToggleReminder,
}: {
  entry: PositionedItem<TimelineEntry>;
  width: number;
  theme: Theme;
  onPressEvent: (event: CalendarEvent) => void;
  onToggleReminder: (reminder: CalendarReminder) => void;
}) {
  const top = TIMELINE_PADDING + (entry.startMinute / 60) * HOUR_HEIGHT;
  const height = Math.max(20, ((entry.endMinute - entry.startMinute) / 60) * HOUR_HEIGHT - 2);
  const columnWidth = width / entry.columns;
  const frame = { top, height, left: entry.column * columnWidth, width: columnWidth - 2 };

  if (entry.kind === 'reminder') {
    const { reminder } = entry;
    return (
      <View style={[styles.block, frame, styles.reminderBlock, { borderColor: reminder.color }]}>
        <ReminderCheck reminder={reminder} onToggle={onToggleReminder} />
        <Text
          style={[styles.blockTitle, { color: theme.text }, reminder.completed && styles.completed]}
          numberOfLines={1}
        >
          {reminder.title}
        </Text>
      </View>
    );
  }

  const { event } = entry;
  const compact = height < 40;
  return (
    <Pressable
      onPress={() => onPressEvent(event)}
      style={[
        styles.block,
        frame,
        { backgroundColor: withAlpha(event.color, 0.22), borderLeftColor: event.color },
      ]}
    >
      <Text style={[styles.blockTitle, { color: theme.text }]} numberOfLines={compact ? 1 : 2}>
        {event.title}
        {compact ? <Text style={styles.blockMeta}>  {formatTime(event.start)}</Text> : null}
      </Text>
      {!compact && event.location ? (
        <Text style={[styles.blockMeta, { color: theme.text }]} numberOfLines={1}>
          {event.location}
        </Text>
      ) : null}
      {!compact ? (
        <Text style={[styles.blockMeta, { color: theme.text }]} numberOfLines={1}>
          {formatTime(event.start)}
        </Text>
      ) : null}
    </Pressable>
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
  theme,
}: {
  reminder: CalendarReminder;
  onToggle: (reminder: CalendarReminder) => void;
  theme: Theme;
}) {
  return (
    <View style={[styles.allDayEvent, styles.reminderChip, { borderColor: reminder.color }]}>
      <ReminderCheck reminder={reminder} onToggle={onToggle} />
      <Text
        style={[styles.allDayTitle, { color: theme.text }, reminder.completed && styles.completed]}
        numberOfLines={1}
      >
        {reminder.title}
      </Text>
    </View>
  );
}

function NowIndicator({ theme }: { theme: Theme }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(id);
  }, []);
  const top = TIMELINE_PADDING + (minutesIntoDay(now) / 60) * HOUR_HEIGHT;
  return (
    <View pointerEvents="none" style={[styles.nowRow, { top: top - 8 }]}>
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
  events: { position: 'absolute', top: 0, bottom: 0 },
  block: {
    position: 'absolute',
    borderRadius: 4,
    borderLeftWidth: 3,
    paddingHorizontal: 5,
    paddingVertical: 2,
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
  blockMeta: { fontSize: 11, fontWeight: '400', opacity: 0.8 },
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
