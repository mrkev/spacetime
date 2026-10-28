import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Alert, ScrollView } from 'react-native';

import { Field, Section } from '../../components/Form';
import { HeaderButton } from '../../components/HeaderButton';
import { useTheme } from '../../lib/theme';
import { createLocationReminder } from '../../space/locationReminders';
import {
  CollectionPicker,
  DEFAULT_TODO,
  LocationFields,
  TodoFields,
  placeName,
  type LocationState,
  type TodoState,
} from '../../space/PlaceForm';
import { placeCollections } from '../../space/places';
import { REMINDERS_COLLECTION_ID, addPlace, useSpaceState } from '../../space/store';
import { useRemindersAccess, useTodoList } from '../../space/TodoEditor';
import { useCalendar } from '../../time/CalendarProvider';

type Params = {
  latitude?: string;
  longitude?: string;
  /** The collection the map is showing, which the place starts out in. */
  collectionId?: string;
  name?: string;
  address?: string;
};

/** Saves a place in collections, adds a todo there, or both. */
export default function NewPlaceScreen() {
  const theme = useTheme();
  const params = useLocalSearchParams<Params>();
  const { collections } = useSpaceState();
  const { refresh } = useCalendar();
  const todoList = useTodoList();

  const latitude = Number(params.latitude);
  const longitude = Number(params.longitude);
  const hasCoordinate = Number.isFinite(latitude) && Number.isFinite(longitude);
  const [location, setLocation] = useState<LocationState>({
    coordinate: hasCoordinate ? { latitude, longitude } : null,
    name: params.name ?? '',
    address: params.address ?? '',
  });
  // From the Reminders collection, start with just a todo.
  const [collectionIds, setCollectionIds] = useState<string[]>(() => {
    if (params.collectionId === REMINDERS_COLLECTION_ID) return [];
    const initial =
      collections.find((c) => c.id === params.collectionId) ??
      collections.find((c) => c.id !== REMINDERS_COLLECTION_ID);
    return initial ? [initial.id] : [];
  });
  const [todo, setTodo] = useState<TodoState>(DEFAULT_TODO);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  const hasTodo = !!todo.title.trim();
  useRemindersAccess(hasTodo);
  const canSave = !!location.coordinate && (collectionIds.length > 0 || hasTodo);
  const reminderColor =
    collections.find((c) => c.id === REMINDERS_COLLECTION_ID)?.color ?? theme.tint;
  const color = placeCollections({ collectionIds }, collections)[0]?.color ?? reminderColor;

  const save = async () => {
    if (!canSave || saving) return;
    const place = {
      name: placeName(location),
      address: location.address || undefined,
      ...location.coordinate!,
    };
    const saved = collectionIds.length > 0;
    if (hasTodo) {
      const list = todoList();
      if (!list) return;
      setSaving(true);
      try {
        await createLocationReminder(list, {
          ...place,
          placeName: place.name,
          title: todo.title.trim(),
          // Notes go on the place if there is one.
          notes: (!saved && notes.trim()) || undefined,
          trigger: todo.trigger,
          radius: todo.radius,
        });
        refresh();
      } catch (error) {
        setSaving(false);
        Alert.alert('Couldn’t Save Todo', String(error));
        return;
      }
    }
    if (saved) addPlace({ ...place, collectionIds, notes: notes.trim() || undefined });
    router.back();
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
          title: 'New Place',
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (
            <HeaderButton label="Save" bold disabled={!canSave || saving} onPress={save} />
          ),
        }}
      />
      <LocationFields
        state={location}
        update={(changes) => setLocation((l) => ({ ...l, ...changes }))}
        color={color}
        radius={hasTodo ? todo.radius : undefined}
        radiusColor={reminderColor}
      />
      <CollectionPicker
        collections={collections}
        value={collectionIds}
        onChange={setCollectionIds}
        footer={
          collectionIds.length === 0
            ? 'In no collection, the place stays on the map only until its todos are done.'
            : undefined
        }
      />
      <TodoFields
        todo={todo}
        update={(changes) => setTodo((t) => ({ ...t, ...changes }))}
        optional
      />
      <Section title="Notes">
        <Field placeholder="Notes" value={notes} onChangeText={setNotes} multiline />
      </Section>
    </ScrollView>
  );
}
