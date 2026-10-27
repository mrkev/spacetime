import { StyleSheet, Text, View } from 'react-native';

import { Icon, icons } from '../components/Icon';
import { addDays, formatHour, minutesIntoDay, startOfDay } from '../lib/dates';
import { useTheme, withAlpha } from '../lib/theme';
import type { DayItems } from './CalendarProvider';
import { layoutDay, type TimedItem } from './layout';

const HOUR = 44;
const HOURS = 3;
const GUTTER = 52;
const PADDING = 14;
const REMINDER_MINUTES = 30;

type Item = TimedItem & { title: string; color: string; kind: 'event' | 'reminder' };

/**
 * A few hours of the day around `at`, like the preview in Calendar's details: what else is going
 * on then, with the item `highlightKey` picked out.
 */
export function MiniTimeline({
  at,
  day,
  highlightKey,
}: {
  at: Date;
  day: DayItems | undefined;
  highlightKey: string;
}) {
  const theme = useTheme();
  const firstHour = Math.max(0, Math.min(24 - HOURS, at.getHours() - 1));
  const from = firstHour * 60;
  const to = from + HOURS * 60;

  const dayStart = startOfDay(at);
  const dayEnd = addDays(dayStart, 1);
  const items: Item[] = [];
  for (const event of day?.events ?? []) {
    if (event.allDay || (event.start <= dayStart && event.end >= dayEnd)) continue;
    const startMinute = event.start < dayStart ? 0 : minutesIntoDay(event.start);
    const endMinute = event.end >= dayEnd ? 24 * 60 : minutesIntoDay(event.end);
    if (endMinute <= from || startMinute >= to) continue;
    items.push({
      key: event.key,
      title: event.title,
      color: event.color,
      kind: 'event',
      startMinute,
      endMinute,
    });
  }
  for (const reminder of day?.reminders ?? []) {
    if (reminder.allDay || !reminder.due) continue;
    const startMinute = minutesIntoDay(reminder.due);
    const endMinute = startMinute + REMINDER_MINUTES;
    if (endMinute <= from || startMinute >= to) continue;
    items.push({
      key: reminder.key,
      title: reminder.title,
      color: reminder.color,
      kind: 'reminder',
      startMinute,
      endMinute,
    });
  }

  const y = (minute: number) => PADDING + ((minute - from) / 60) * HOUR;

  return (
    <View
      style={[styles.card, { backgroundColor: theme.card, height: HOURS * HOUR + PADDING * 2 }]}
    >
      {Array.from({ length: HOURS + 1 }, (_, i) => (
        <View key={i} style={[styles.hourRow, { top: y(from + i * 60) - 8 }]}>
          <Text style={[styles.hourLabel, { color: theme.secondaryText }]}>
            {formatHour(new Date(2026, 0, 1, (firstHour + i) % 24))}
          </Text>
          <View style={[styles.hourLine, { backgroundColor: theme.hourLine }]} />
        </View>
      ))}
      <View style={styles.items}>
        {layoutDay(items).map((item) => {
          const top = Math.max(y(item.startMinute), PADDING / 2);
          const bottom = Math.min(y(item.endMinute), HOURS * HOUR + PADDING * 1.5);
          const highlighted = item.key === highlightKey;
          return (
            <View
              key={item.key}
              style={[
                styles.block,
                {
                  top,
                  height: Math.max(22, bottom - top - 2),
                  left: `${(item.column / item.columns) * 100}%`,
                  width: `${100 / item.columns}%`,
                },
              ]}
            >
              <View
                style={[
                  styles.blockInner,
                  item.kind === 'event'
                    ? { backgroundColor: withAlpha(item.color, 0.22), borderLeftColor: item.color }
                    : styles.reminderInner,
                  item.kind === 'reminder' && {
                    backgroundColor: highlighted ? theme.fill : 'transparent',
                    borderColor: highlighted ? theme.fill : item.color,
                  },
                ]}
              >
                {item.kind === 'reminder' ? (
                  <Icon
                    name={icons.circle}
                    size={13}
                    color={highlighted ? theme.text : item.color}
                  />
                ) : null}
                <Text style={[styles.title, { color: theme.text }]} numberOfLines={1}>
                  {item.title}
                </Text>
              </View>
            </View>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: 22, overflow: 'hidden' },
  hourRow: {
    position: 'absolute',
    left: 0,
    right: 14,
    height: 16,
    flexDirection: 'row',
    alignItems: 'center',
  },
  hourLabel: { width: GUTTER, fontSize: 12, textAlign: 'right', paddingRight: 8 },
  hourLine: { flex: 1, height: StyleSheet.hairlineWidth },
  items: { position: 'absolute', top: 0, bottom: 0, left: GUTTER, right: 14 },
  block: { position: 'absolute', paddingRight: 2 },
  blockInner: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 5,
    borderRadius: 5,
    borderLeftWidth: 3,
    paddingHorizontal: 5,
    paddingVertical: 3,
  },
  reminderInner: { borderWidth: 1, borderLeftWidth: 1, alignItems: 'center' },
  title: { fontSize: 12, fontWeight: '600', flexShrink: 1 },
});
