import { Stack, router } from 'expo-router';
import { useEffect, useState, type ReactNode } from 'react';
import { Alert, Linking, ScrollView } from 'react-native';

import { Field, Row, Section, Separator } from '../components/Form';
import { HeaderButton } from '../components/HeaderButton';
import { useTheme } from '../lib/theme';
import { showInReminders } from '../time/actions';
import { useCalendar } from '../time/CalendarProvider';
import {
  createLocationReminder,
  updateLocationReminder,
  type LocationReminder,
} from './locationReminders';
import {
  DEFAULT_TODO,
  LocationFields,
  TodoFields,
  placeName,
  type LocationState,
  type TodoState,
} from './PlaceForm';
import { pinColor, type MapPlace } from './places';
import { REMINDERS_COLLECTION_ID, useSpaceState } from './store';

/**
 * The reminder list new todos go into, or null (after telling the user why) if there isn't one.
 */
export function useTodoList() {
  const { remindersStatus, defaultReminderList } = useCalendar();
  return () => {
    const list = defaultReminderList();
    if (list) return list;
    Alert.alert(
      'Can’t Save Todo',
      remindersStatus === 'granted'
        ? 'Add a list in Reminders to save todos.'
        : 'Todos are saved in Reminders. Allow access to Reminders in Settings.',
      remindersStatus === 'granted'
        ? undefined
        : [
            { text: 'Not Now', style: 'cancel' },
            { text: 'Open Settings', onPress: () => Linking.openSettings() },
          ],
    );
    return null;
  };
}

/** Asks for access to Reminders as soon as a todo is being made. */
export function useRemindersAccess(needed: boolean) {
  const { remindersStatus, requestAccess } = useCalendar();
  useEffect(() => {
    if (needed && remindersStatus === 'undetermined') requestAccess();
  }, [needed, remindersStatus, requestAccess]);
}

/**
 * Makes or edits a todo at a place. A saved place's todos stay where it is; a todo that isn't at
 * a saved place can be moved.
 */
export function TodoEditor({
  existing,
  place,
  header,
}: {
  existing?: LocationReminder;
  place: MapPlace | null;
  /** Shown above the form. */
  header?: ReactNode;
}) {
  const theme = useTheme();
  const { collections } = useSpaceState();
  const { toggleReminder, refresh } = useCalendar();
  const todoList = useTodoList();
  useRemindersAccess(!existing);
  const [saving, setSaving] = useState(false);

  const fixed = !!place?.saved;
  const anchor = existing ?? place;
  const [location, setLocation] = useState<LocationState>({
    coordinate: anchor ? { latitude: anchor.latitude, longitude: anchor.longitude } : null,
    name: existing?.placeName ?? place?.name ?? '',
    address: existing?.address ?? place?.address ?? '',
  });
  const [todo, setTodo] = useState<TodoState>(
    existing
      ? {
          title: existing.title,
          trigger: existing.trigger,
          radius: existing.radius,
          notes: existing.notes ?? '',
        }
      : DEFAULT_TODO,
  );
  const reminderColor =
    collections.find((c) => c.id === REMINDERS_COLLECTION_ID)?.color ?? theme.tint;
  const color = place ? pinColor(place, collections, theme.tint) : reminderColor;
  const canSave = !!location.coordinate && !!todo.title.trim();

  const save = async () => {
    if (!canSave || saving) return;
    const input = {
      title: todo.title.trim(),
      notes: todo.notes.trim() || undefined,
      trigger: todo.trigger,
      radius: todo.radius,
      placeName: placeName(location),
      address: location.address || undefined,
      latitude: location.coordinate!.latitude,
      longitude: location.coordinate!.longitude,
    };
    setSaving(true);
    try {
      if (existing) {
        await updateLocationReminder(existing, input);
      } else {
        const list = todoList();
        if (!list) {
          setSaving(false);
          return;
        }
        await createLocationReminder(list, input);
      }
      refresh();
      router.back();
    } catch (error) {
      setSaving(false);
      Alert.alert('Couldn’t Save Todo', String(error));
    }
  };

  // Checking it off applies right away, like in a list. It then drops out of the open reminders,
  // so keep track of it here.
  const [completed, setCompleted] = useState(existing?.completed ?? false);
  const toggleCompleted = () => {
    if (!existing) return;
    setCompleted(!completed);
    toggleReminder({ ...existing.reminder, completed }).catch((error) => {
      setCompleted(completed);
      Alert.alert('Couldn’t Update Todo', String(error));
    });
  };

  const confirmDelete = () => {
    if (!existing) return;
    Alert.alert(`Delete “${existing.title}”?`, undefined, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () =>
          existing.reminder.source
            .delete()
            .then(() => {
              refresh();
              router.back();
            })
            .catch((error) => Alert.alert('Couldn’t Delete Todo', String(error))),
      },
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
          title: existing ? 'Todo' : 'Add to Reminder',
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (
            <HeaderButton
              label={existing ? 'Done' : 'Add'}
              bold
              disabled={!canSave || saving}
              onPress={save}
            />
          ),
        }}
      />
      {header}
      <TodoFields todo={todo} update={(changes) => setTodo((t) => ({ ...t, ...changes }))} />
      <LocationFields
        state={location}
        update={(changes) => setLocation((l) => ({ ...l, ...changes }))}
        color={color}
        radius={todo.radius}
        radiusColor={reminderColor}
        fixed={fixed}
      />
      <Section title="Notes">
        <Field
          placeholder="Notes"
          value={todo.notes}
          onChangeText={(notes) => setTodo((t) => ({ ...t, notes }))}
          multiline
        />
      </Section>
      {existing ? (
        <>
          <Section>
            <Row
              label={completed ? 'Mark as Incomplete' : 'Mark as Completed'}
              onPress={toggleCompleted}
            />
            <Separator />
            <Row label="Show in Reminders" onPress={() => showInReminders(existing.id)} />
          </Section>
          <Section>
            <Row label="Delete Todo" destructive onPress={confirmDelete} />
          </Section>
        </>
      ) : null}
    </ScrollView>
  );
}
