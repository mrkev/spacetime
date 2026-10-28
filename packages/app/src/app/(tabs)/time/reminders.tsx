import { Stack, router } from 'expo-router';
import { useMemo } from 'react';
import { Platform, Pressable, SectionList, StyleSheet, Text, View } from 'react-native';

import { HeaderButton } from '../../../components/HeaderButton';
import { Icon, icons } from '../../../components/Icon';
import { formatRelativeDay, formatTime } from '../../../lib/dates';
import { useTheme, type Theme } from '../../../lib/theme';
import {
  describeTrigger,
  useLocationReminders,
  type LocationReminder,
} from '../../../space/locationReminders';
import { REMINDERS_COLLECTION_ID, useSpaceState } from '../../../space/store';
import { useCalendar, type CalendarReminder } from '../../../time/CalendarProvider';
import { useTimeActions } from '../../../time/actions';

type Row =
  | { kind: 'place'; key: string; location: LocationReminder }
  | { kind: 'reminder'; key: string; reminder: CalendarReminder };

export default function RemindersScreen() {
  const theme = useTheme();
  const { openReminders, toggleReminder, remindersStatus, requestAccess } = useCalendar();
  const { collections } = useSpaceState();
  const locationReminders = useLocationReminders();
  const { showAddMenu } = useTimeActions();
  const placeColor = collections.find((c) => c.id === REMINDERS_COLLECTION_ID)?.color ?? theme.tint;

  const sections = useMemo(() => {
    const placeRows: Row[] = locationReminders.map((location) => ({
      kind: 'place',
      key: location.id,
      location,
    }));
    const located = new Set(locationReminders.map((l) => l.id));
    const others = openReminders.filter((r) => !located.has(r.key));
    const scheduled: Row[] = others
      .filter((r) => r.due)
      .map((reminder) => ({ kind: 'reminder', key: reminder.key, reminder }));
    const unscheduled: Row[] = others
      .filter((r) => !r.due)
      .map((reminder) => ({ kind: 'reminder', key: reminder.key, reminder }));

    return [
      {
        title: 'At a Place',
        data: placeRows,
        empty: 'Long-press the map to add a place reminder.',
      },
      ...(Platform.OS === 'ios'
        ? [
            { title: 'Scheduled', data: scheduled, empty: 'No upcoming reminders.' },
            { title: 'No Date', data: unscheduled, empty: '' },
          ]
        : []),
    ].filter((s) => s.data.length > 0 || s.empty);
  }, [locationReminders, openReminders]);

  return (
    <View style={{ flex: 1, backgroundColor: theme.groupedBackground }}>
      <Stack.Screen
        options={{
          headerRight: () => (
            <HeaderButton
              icon={icons.plus}
              accessibilityLabel="Add"
              onPress={() => showAddMenu()}
            />
          ),
        }}
      />
      <SectionList
        sections={sections}
        keyExtractor={(row) => row.key}
        contentInsetAdjustmentBehavior="automatic"
        stickySectionHeadersEnabled={false}
        contentContainerStyle={styles.content}
        ListHeaderComponent={
          Platform.OS === 'ios' &&
          remindersStatus !== 'granted' &&
          remindersStatus !== 'loading' ? (
            <Pressable
              onPress={requestAccess}
              style={[styles.notice, { backgroundColor: theme.card }]}
            >
              <Text style={{ color: theme.text }}>
                Allow access to Reminders to see your scheduled reminders here.
              </Text>
            </Pressable>
          ) : undefined
        }
        renderSectionHeader={({ section }) => (
          <Text style={[styles.sectionTitle, { color: theme.text }]}>{section.title}</Text>
        )}
        renderSectionFooter={({ section }) =>
          section.data.length === 0 ? (
            <Text style={[styles.empty, { color: theme.secondaryText }]}>{section.empty}</Text>
          ) : null
        }
        renderItem={({ item, index, section }) => (
          <View
            style={[
              { backgroundColor: theme.card },
              index === 0 && styles.firstRow,
              index === section.data.length - 1 && styles.lastRow,
            ]}
          >
            {item.kind === 'place' ? (
              <PlaceReminderRow
                location={item.location}
                color={placeColor}
                onToggle={toggleReminder}
                theme={theme}
              />
            ) : (
              <DatedReminderRow reminder={item.reminder} onToggle={toggleReminder} theme={theme} />
            )}
            {index < section.data.length - 1 ? (
              <View style={[styles.separator, { backgroundColor: theme.separator }]} />
            ) : null}
          </View>
        )}
      />
    </View>
  );
}

function PlaceReminderRow({
  location,
  color,
  onToggle,
  theme,
}: {
  location: LocationReminder;
  color: string;
  onToggle: (reminder: CalendarReminder) => void;
  theme: Theme;
}) {
  const done = location.completed;
  return (
    <Pressable
      style={styles.row}
      onPress={() => router.push({ pathname: '/place/reminder/[id]', params: { id: location.id } })}
    >
      <Pressable
        hitSlop={10}
        onPress={() => onToggle(location.reminder)}
        accessibilityRole="checkbox"
        accessibilityState={{ checked: done }}
      >
        <Icon name={done ? icons.checkCircle : icons.circle} color={color} size={24} />
      </Pressable>
      <View style={styles.rowText}>
        <Text style={[styles.title, { color: theme.text }, done && styles.done]} numberOfLines={2}>
          {location.title}
        </Text>
        <View style={styles.metaRow}>
          <Icon name={icons.locationFill} color={theme.secondaryText} size={11} />
          <Text style={[styles.meta, { color: theme.secondaryText }]} numberOfLines={1}>
            {location.placeName} · {describeTrigger(location)}
          </Text>
        </View>
      </View>
      <Icon name={icons.chevronRight} color={theme.tertiaryText} size={14} />
    </Pressable>
  );
}

function DatedReminderRow({
  reminder,
  onToggle,
  theme,
}: {
  reminder: CalendarReminder;
  onToggle: (reminder: CalendarReminder) => void;
  theme: Theme;
}) {
  const overdue = !!reminder.due && reminder.due < new Date();
  return (
    <View style={styles.row}>
      <Pressable
        hitSlop={10}
        onPress={() => onToggle(reminder)}
        accessibilityRole="checkbox"
        accessibilityState={{ checked: reminder.completed }}
      >
        <Icon
          name={reminder.completed ? icons.checkCircle : icons.circle}
          color={reminder.color}
          size={24}
        />
      </Pressable>
      <Pressable
        style={styles.rowText}
        onPress={() => router.push({ pathname: '/reminder/[id]', params: { id: reminder.key } })}
        accessibilityRole="button"
      >
        <Text style={[styles.title, { color: theme.text }]} numberOfLines={2}>
          {reminder.title}
        </Text>
        <Text
          style={[styles.meta, { color: overdue ? theme.tint : theme.secondaryText }]}
          numberOfLines={1}
        >
          {[
            reminder.due &&
              `${formatRelativeDay(reminder.due)}${reminder.allDay ? '' : `, ${formatTime(reminder.due)}`}`,
            reminder.listTitle,
          ]
            .filter(Boolean)
            .join(' · ')}
        </Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  content: { paddingHorizontal: 16, paddingBottom: 40 },
  notice: { borderRadius: 10, padding: 14, marginTop: 12 },
  sectionTitle: { fontSize: 20, fontWeight: '700', marginTop: 24, marginBottom: 8 },
  empty: { fontSize: 15, paddingVertical: 4 },
  firstRow: { borderTopLeftRadius: 10, borderTopRightRadius: 10 },
  lastRow: { borderBottomLeftRadius: 10, borderBottomRightRadius: 10 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  rowText: { flex: 1, gap: 2 },
  title: { fontSize: 17 },
  done: { color: '#8E8E93' },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  meta: { fontSize: 13, flexShrink: 1 },
  separator: { height: StyleSheet.hairlineWidth, marginLeft: 50 },
});
