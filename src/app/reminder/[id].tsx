import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  ActionSheetIOS,
  Alert,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { HeaderButton } from '../../components/HeaderButton';
import { Icon, icons } from '../../components/Icon';
import { formatFullDate, formatTime } from '../../lib/dates';
import { useTheme, type Theme } from '../../lib/theme';
import { useCalendar, type CalendarReminder } from '../../time/CalendarProvider';
import { MiniTimeline } from '../../time/MiniTimeline';

/** Opens the reminder in the Reminders app (an undocumented URL), or just the app if that fails. */
function showInReminders(reminder: CalendarReminder) {
  Linking.openURL(`x-apple-reminderkit://REMCDReminder/${reminder.key}`).catch(() =>
    Linking.openURL('x-apple-reminderkit://').catch(() => {}),
  );
}

/** A reminder's details, like the card Calendar shows for one. */
export default function ReminderDetailsScreen() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { getReminder, getDay, ensureMonths, toggleReminder, refresh } = useCalendar();

  // Undated reminders drop out of the loaded data once completed, so keep showing the last copy.
  const found = getReminder(id);
  const [lastFound, setLastFound] = useState(found);
  if (found && found !== lastFound) setLastFound(found);
  const reminder = found ?? lastFound;
  // Checked state flips right away; the calendar catches up when it reloads.
  const [completed, setCompleted] = useState<boolean | null>(null);
  const isCompleted = completed ?? reminder?.completed ?? false;

  useEffect(() => {
    if (reminder?.due) ensureMonths(reminder.due, 0);
  }, [reminder?.due, ensureMonths]);

  if (!reminder) {
    return (
      <View style={[styles.missing, { backgroundColor: theme.groupedBackground }]}>
        <Stack.Screen options={{ title: '' }} />
        <Text style={{ color: theme.secondaryText }}>This reminder is no longer available.</Text>
      </View>
    );
  }

  const toggle = () => {
    setCompleted(!isCompleted);
    toggleReminder({ ...reminder, completed: isCompleted }).catch((error) => {
      setCompleted(null);
      Alert.alert('Couldn’t Update Reminder', String(error));
    });
  };

  const remove = () => {
    const confirm = () =>
      reminder.source
        .delete()
        .then(() => {
          refresh();
          router.back();
        })
        .catch((error) => Alert.alert('Couldn’t Delete Reminder', String(error)));
    ActionSheetIOS.showActionSheetWithOptions(
      {
        title: 'Are you sure you want to delete this reminder?',
        options: ['Delete Reminder', 'Cancel'],
        destructiveButtonIndex: 0,
        cancelButtonIndex: 1,
      },
      (index) => {
        if (index === 0) confirm();
      },
    );
  };

  return (
    <ScrollView
      style={{ backgroundColor: theme.groupedBackground }}
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={styles.content}
    >
      <Stack.Screen
        options={{
          title: '',
          headerLeft: () => (
            <HeaderButton
              icon={icons.xmark}
              accessibilityLabel="Close"
              color={theme.text}
              onPress={() => router.back()}
            />
          ),
          headerRight: () => (
            <HeaderButton
              label="Edit"
              color={theme.text}
              onPress={() =>
                router.push({ pathname: '/reminder/edit', params: { id: reminder.key } })
              }
            />
          ),
        }}
      />

      <View style={styles.titleRow}>
        <Pressable
          onPress={toggle}
          hitSlop={10}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: isCompleted }}
          accessibilityLabel={reminder.title}
        >
          <Icon
            name={isCompleted ? icons.checkCircle : icons.circle}
            size={34}
            color={reminder.color}
          />
        </Pressable>
        <Text
          style={[styles.title, { color: theme.text }, isCompleted && styles.completed]}
          accessibilityRole="header"
        >
          {reminder.title}
        </Text>
      </View>

      {reminder.due ? (
        <View>
          <Text style={[styles.secondary, { color: theme.secondaryText }]}>
            {formatFullDate(reminder.due)}
          </Text>
          {!reminder.allDay ? (
            <Text style={[styles.secondary, { color: theme.secondaryText }]}>
              {formatTime(reminder.due)}
            </Text>
          ) : null}
        </View>
      ) : null}

      <Detail label="List" value={reminder.listTitle} theme={theme} />
      {reminder.notes ? <Detail label="Notes" value={reminder.notes} theme={theme} /> : null}

      {reminder.due && !reminder.allDay ? (
        <MiniTimeline at={reminder.due} day={getDay(reminder.due)} highlightKey={reminder.key} />
      ) : null}

      <View style={styles.buttons}>
        <WideButton
          label="Show in Reminders"
          onPress={() => showInReminders(reminder)}
          theme={theme}
        />
        <WideButton label="Delete Reminder" destructive onPress={remove} theme={theme} />
      </View>
    </ScrollView>
  );
}

function Detail({ label, value, theme }: { label: string; value: string; theme: Theme }) {
  return (
    <View style={styles.detail}>
      <Text style={[styles.detailLabel, { color: theme.secondaryText }]}>{label}</Text>
      <Text style={[styles.secondary, { color: theme.secondaryText }]} selectable>
        {value}
      </Text>
    </View>
  );
}

function WideButton({
  label,
  onPress,
  destructive,
  theme,
}: {
  label: string;
  onPress: () => void;
  destructive?: boolean;
  theme: Theme;
}) {
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      style={({ pressed }) => [
        styles.wideButton,
        { backgroundColor: pressed ? theme.fill : theme.card },
      ]}
    >
      <Text style={[styles.wideLabel, { color: destructive ? theme.tint : theme.text }]}>
        {label}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  content: { paddingHorizontal: 20, paddingTop: 8, paddingBottom: 40, gap: 20 },
  missing: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 32 },
  titleRow: { flexDirection: 'row', alignItems: 'center', gap: 14 },
  title: { flex: 1, fontSize: 28, fontWeight: '700' },
  completed: { opacity: 0.5 },
  secondary: { fontSize: 17, lineHeight: 24 },
  detail: { gap: 2 },
  detailLabel: { fontSize: 15, fontWeight: '600' },
  buttons: { gap: 20, marginTop: 4 },
  wideButton: {
    height: 54,
    borderRadius: 27,
    alignItems: 'center',
    justifyContent: 'center',
  },
  wideLabel: { fontSize: 17 },
});
