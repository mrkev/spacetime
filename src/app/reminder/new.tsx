import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { DateField } from '../../components/DateField';
import { Field, Row, Section, Separator, SwitchRow } from '../../components/Form';
import { HeaderButton } from '../../components/HeaderButton';
import { Icon, icons } from '../../components/Icon';
import { useTheme } from '../../lib/theme';
import { useCalendar } from '../../time/CalendarProvider';

/** Creates a reminder in the system Reminders app. */
export default function NewReminderScreen() {
  const theme = useTheme();
  const params = useLocalSearchParams<{ date?: string }>();
  const { reminderLists, remindersStatus, requestAccess, refresh } = useCalendar();

  const initialDate = useMemo(() => {
    const date = params.date ? new Date(params.date) : new Date();
    date.setHours(9, 0, 0, 0);
    return date;
  }, [params.date]);

  const [title, setTitle] = useState('');
  const [notes, setNotes] = useState('');
  const [hasDate, setHasDate] = useState(!!params.date);
  const [hasTime, setHasTime] = useState(false);
  const [due, setDue] = useState(initialDate);
  const [listId, setListId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (remindersStatus === 'undetermined') requestAccess();
  }, [remindersStatus, requestAccess]);

  const writableLists = reminderLists.filter((l) => l.allowsModifications);
  const list = writableLists.find((l) => l.id === listId) ?? writableLists[0];

  const save = async () => {
    if (!list || !title.trim()) return;
    setSaving(true);
    try {
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

  if (Platform.OS !== 'ios') {
    return (
      <View style={[styles.center, { backgroundColor: theme.groupedBackground }]}>
        <Text style={{ color: theme.secondaryText, textAlign: 'center' }}>
          Dated reminders use Apple Reminders and are only available on iOS. Location reminders
          work everywhere — add one from the Space tab.
        </Text>
      </View>
    );
  }

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: theme.groupedBackground }}
      keyboardShouldPersistTaps="handled"
      contentContainerStyle={styles.content}
    >
      <Stack.Screen
        options={{
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (
            <HeaderButton
              label="Add"
              bold
              disabled={!title.trim() || !list || saving}
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
        <Field placeholder="Title" value={title} onChangeText={setTitle} autoFocus />
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

      {writableLists.length > 1 ? (
        <Section title="List">
          {writableLists.map((l, i) => (
            <View key={l.id}>
              {i > 0 ? <Separator /> : null}
              <Pressable style={styles.listRow} onPress={() => setListId(l.id)}>
                <View style={[styles.listDot, { backgroundColor: l.color ?? theme.tint }]} />
                <Text style={[styles.listName, { color: theme.text }]}>{l.title}</Text>
                {l.id === list?.id ? <Icon name={icons.check} color={theme.tint} size={16} /> : null}
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
  listRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, minHeight: 44 },
  listDot: { width: 12, height: 12, borderRadius: 6 },
  listName: { flex: 1, fontSize: 17 },
});
