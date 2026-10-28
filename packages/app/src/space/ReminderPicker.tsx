import { Stack, router } from 'expo-router';
import { useState, type ReactNode } from 'react';
import { ActivityIndicator, Alert, ScrollView, View } from 'react-native';

import { PickRow, SearchRow, Section, Separator } from '../components/Form';
import { HeaderButton } from '../components/HeaderButton';
import { formatRelativeDay } from '../lib/dates';
import { useTheme } from '../lib/theme';
import { useCalendar, type CalendarReminder } from '../time/CalendarProvider';
import { moveReminderTo, toLocationReminder } from './locationReminders';
import { DEFAULT_TODO } from './PlaceForm';
import type { MapPlace } from './places';
import { useRemindersAccess } from './TodoEditor';

/**
 * Picks an open reminder to remind you at a place. It lists the ones without a location; search
 * finds ones with a location too, which then move here.
 */
export function ReminderPicker({ place, header }: { place: MapPlace; header?: ReactNode }) {
  const theme = useTheme();
  const { openReminders, refresh } = useCalendar();
  useRemindersAccess(true);
  const [query, setQuery] = useState('');
  const [saving, setSaving] = useState(false);

  const term = query.trim().toLocaleLowerCase();
  const shown = openReminders.filter(
    (r) =>
      !place.todos.some((t) => t.id === r.key) &&
      (term ? r.title.toLocaleLowerCase().includes(term) : !toLocationReminder(r)),
  );

  const move = async (reminder: CalendarReminder) => {
    setSaving(true);
    try {
      await moveReminderTo(reminder, place, DEFAULT_TODO);
      refresh();
      router.back();
    } catch (error) {
      setSaving(false);
      Alert.alert('Couldn’t Save Reminder', String(error));
    }
  };

  const pick = (reminder: CalendarReminder) => {
    if (saving) return;
    const located = toLocationReminder(reminder);
    if (!located) {
      move(reminder);
      return;
    }
    Alert.alert(`Move “${reminder.title}” Here?`, `It reminds you at ${located.placeName} now.`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Move', onPress: () => move(reminder) },
    ]);
  };

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: theme.groupedBackground }}
      contentContainerStyle={{ paddingBottom: 40 }}
      keyboardShouldPersistTaps="handled"
      automaticallyAdjustKeyboardInsets
    >
      <Stack.Screen
        options={{
          title: 'Add to Reminder',
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (saving ? <ActivityIndicator /> : null),
        }}
      />
      {header}
      <Section
        footer={
          term
            ? shown.length === 0
              ? `No reminders match “${query.trim()}”.`
              : undefined
            : shown.length === 0
              ? 'No reminders without a location. Search to find ones with a location.'
              : 'Reminders without a location. Search to find ones with a location too.'
        }
      >
        <SearchRow placeholder="Search reminders" value={query} onChangeText={setQuery} />
        {shown.map((reminder) => {
          const located = toLocationReminder(reminder);
          return (
            <View key={reminder.key}>
              <Separator />
              <PickRow
                title={reminder.title}
                subtitle={[
                  reminder.listTitle,
                  reminder.due ? formatRelativeDay(reminder.due) : null,
                  located?.placeName,
                ]
                  .filter(Boolean)
                  .join(' · ')}
                color={reminder.color}
                onPress={() => pick(reminder)}
              />
            </View>
          );
        })}
      </Section>
    </ScrollView>
  );
}
