import type * as Calendar from 'expo-calendar';
import { Stack, router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { DateField } from '../components/DateField';
import { Field, Row, Section, Separator, SwitchRow } from '../components/Form';
import { HeaderButton } from '../components/HeaderButton';
import { Icon, icons } from '../components/Icon';
import { useKeyboardHeight } from '../lib/keyboard';
import { useTheme } from '../lib/theme';
import { useCalendar, type CalendarReminder } from './CalendarProvider';

type Props =
  /** A new reminder, optionally on a given day. */
  | { reminder?: undefined; date?: Date }
  /** Changes to an existing reminder. */
  | { reminder: CalendarReminder; date?: undefined };

/** Creates or edits a reminder in the system Reminders app. */
export function ReminderEditor({ reminder, date }: Props) {
  const theme = useTheme();
  const { reminderLists, defaultReminderList, remindersStatus, requestAccess, refresh } =
    useCalendar();
  const keyboardHeight = useKeyboardHeight();

  const [title, setTitle] = useState(reminder?.title ?? '');
  const [notes, setNotes] = useState(reminder?.notes ?? '');
  const [hasDate, setHasDate] = useState(reminder ? !!reminder.due : !!date);
  const [hasTime, setHasTime] = useState(!!reminder?.due && !reminder.allDay);
  const [due, setDue] = useState(() => {
    if (reminder?.due) return new Date(reminder.due);
    const day = date ? new Date(date) : new Date();
    day.setHours(9, 0, 0, 0);
    return day;
  });
  const [listId, setListId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (remindersStatus === 'undetermined') requestAccess();
  }, [remindersStatus, requestAccess]);

  const writableLists = reminderLists.filter((l) => l.allowsModifications);
  const list = writableLists.find((l) => l.id === listId) ?? defaultReminderList();

  const save = async () => {
    if (!title.trim() || (!reminder && !list)) return;
    setSaving(true);
    try {
      if (reminder) {
        await saveChanges(reminder.source);
        refresh();
        router.back();
        return;
      }
      if (!list) return;
      const dueDate = hasDate ? due : undefined;
      await list.createReminder({
        title: title.trim(),
        notes: notes.trim() || undefined,
        startDate: dueDate,
        dueDate,
        allDay: hasDate && !hasTime,
        // An alarm at the due time is what makes Reminders notify.
        alarms: hasDate && hasTime ? [{ relativeOffset: 0 }] : undefined,
      });
      refresh();
      router.back();
    } catch (error) {
      setSaving(false);
      Alert.alert('Couldn’t Save Reminder', String(error));
    }
  };

  const saveChanges = (source: Calendar.ExpoCalendarReminder) => {
    // Reminders from a list are bare native objects that skip expo-calendar's JS wrapper, so dates
    // go in as strings and cleared fields are named explicitly.
    const dueDate = hasDate ? due.toISOString() : undefined;
    const cleared: ('dueDate' | 'startDate' | 'notes')[] = [];
    if (!dueDate) cleared.push('dueDate', 'startDate');
    if (!notes.trim()) cleared.push('notes');
    // The JS wrapper reads nulls as "clear this"; the native method takes the names separately.
    const update = source.update as (
      details: Record<string, unknown>,
      nullableFields: string[],
    ) => Promise<void>;
    return update.call(
      source,
      {
        title: title.trim(),
        ...(notes.trim() ? { notes: notes.trim() } : {}),
        ...(dueDate ? { dueDate, startDate: dueDate } : {}),
        ...Object.fromEntries(cleared.map((field) => [field, null])),
        allDay: hasDate && !hasTime,
        // An alarm at the due time is what makes Reminders notify; keep any the user already set.
        ...(hasDate && hasTime && !source.alarms?.length
          ? { alarms: [{ relativeOffset: 0 }] }
          : {}),
      },
      cleared,
    );
  };

  if (Platform.OS !== 'ios') {
    return (
      <View style={[styles.center, { backgroundColor: theme.groupedBackground }]}>
        <Text style={{ color: theme.secondaryText, textAlign: 'center' }}>
          Reminders use Apple Reminders and are only available on iOS.
        </Text>
      </View>
    );
  }

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: theme.groupedBackground }}
      keyboardShouldPersistTaps="handled"
      keyboardDismissMode="interactive"
      // Room to scroll the list picker at the bottom up from under the keyboard. (RN's
      // automaticallyAdjustKeyboardInsets does this too, but scrolls the form up under its header.)
      contentContainerStyle={[styles.content, { paddingBottom: 40 + keyboardHeight }]}
    >
      <Stack.Screen
        options={{
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (
            <HeaderButton
              label={reminder ? 'Done' : 'Add'}
              bold
              disabled={!title.trim() || (!reminder && !list) || saving}
              onPress={save}
            />
          ),
        }}
      />

      {remindersStatus === 'denied' ? (
        <Section footer="Allow access to Reminders in Settings to add reminders.">
          <Row label="Reminders access is off" />
        </Section>
      ) : null}

      <Section>
        <Field placeholder="Title" value={title} onChangeText={setTitle} autoFocus={!reminder} />
        <Separator />
        <Field placeholder="Notes" value={notes} onChangeText={setNotes} multiline />
      </Section>

      <Section>
        <SwitchRow label="Date" value={hasDate} onValueChange={setHasDate} />
        {hasDate ? (
          <>
            <Separator />
            <Row label="Day">
              <DateField value={due} mode="date" onChange={setDue} />
            </Row>
            <Separator />
            <SwitchRow label="Time" value={hasTime} onValueChange={setHasTime} />
            {hasTime ? (
              <>
                <Separator />
                <Row label="At">
                  <DateField value={due} mode="time" onChange={setDue} />
                </Row>
              </>
            ) : null}
          </>
        ) : null}
      </Section>

      {reminder ? (
        // EventKit's reminder updates can't move a reminder between lists.
        <Section title="List">
          <Row label={reminder.listTitle} />
        </Section>
      ) : writableLists.length > 1 ? (
        <Section title="List">
          {writableLists.map((l, i) => (
            <View key={l.id}>
              {i > 0 ? <Separator /> : null}
              <Pressable style={styles.listRow} onPress={() => setListId(l.id)}>
                <View style={[styles.listDot, { backgroundColor: l.color ?? theme.tint }]} />
                <Text style={[styles.listName, { color: theme.text }]}>{l.title}</Text>
                {l.id === list?.id ? (
                  <Icon name={icons.check} color={theme.tint} size={16} />
                ) : null}
              </Pressable>
            </View>
          ))}
        </Section>
      ) : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { paddingBottom: 40 },
  center: { flex: 1, padding: 32, justifyContent: 'center' },
  listRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    minHeight: 44,
  },
  listDot: { width: 12, height: 12, borderRadius: 6 },
  listName: { flex: 1, fontSize: 17 },
});
