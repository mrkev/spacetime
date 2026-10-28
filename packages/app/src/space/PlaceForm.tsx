import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, Linking, Pressable, StyleSheet, Text, View } from 'react-native';
import MapView, { Circle, Marker } from 'react-native-maps';

import { Field, Section, Segmented, Separator } from '../components/Form';
import { Icon, icons } from '../components/Icon';
import { describeCoordinate, searchAddress, type Coordinate } from '../lib/geo';
import { useTheme, withAlpha } from '../lib/theme';
import { useCalendar } from '../time/CalendarProvider';
import {
  createLocationReminder,
  updateLocationReminder,
  type LocationReminder,
  type LocationReminderInput,
  type ReminderTrigger,
} from './locationReminders';
import {
  REMINDERS_COLLECTION_ID,
  addPlace,
  deletePlace,
  updatePlace,
  type Collection,
  type Place,
  type PlaceInput,
} from './store';

export const RADIUS_OPTIONS = [
  { label: '100 m', value: 100 },
  { label: '250 m', value: 250 },
  { label: '500 m', value: 500 },
  { label: '1 km', value: 1000 },
];

/** The fields only location reminders have. */
export type ReminderFields = { title: string; trigger: ReminderTrigger; radius: number };

const DEFAULT_REMINDER: ReminderFields = { title: '', trigger: 'arrive', radius: 250 };

export type PlaceFormState = {
  coordinate: Coordinate | null;
  name: string;
  address: string;
  notes: string;
  collectionId: string;
  reminder: ReminderFields;
};

export function usePlaceForm(initial: Partial<PlaceFormState> & { collectionId: string }) {
  const { remindersStatus, requestAccess } = useCalendar();
  const [state, setState] = useState<PlaceFormState>({
    coordinate: null,
    name: '',
    address: '',
    notes: '',
    ...initial,
    reminder: { ...DEFAULT_REMINDER, ...initial.reminder },
  });
  const update = (changes: Partial<PlaceFormState>) => setState((s) => ({ ...s, ...changes }));
  const updateReminder = (changes: Partial<ReminderFields>) =>
    setState((s) => ({ ...s, reminder: { ...s.reminder, ...changes } }));

  const isReminder = state.collectionId === REMINDERS_COLLECTION_ID;
  // Location reminders are saved in Reminders, so ask for access as soon as one is being made.
  useEffect(() => {
    if (isReminder && remindersStatus === 'undetermined') requestAccess();
  }, [isReminder, remindersStatus, requestAccess]);
  const canSave =
    !!state.coordinate &&
    (isReminder ? !!(state.reminder.title.trim() || state.name.trim()) : !!state.name.trim());

  return { state, update, updateReminder, isReminder, canSave };
}

export type PlaceForm = ReturnType<typeof usePlaceForm>;

function placeName(state: PlaceFormState) {
  return state.name.trim() || 'Dropped Pin';
}

function toPlaceInput(state: PlaceFormState): PlaceInput {
  return {
    collectionId: state.collectionId,
    name: placeName(state),
    address: state.address || undefined,
    notes: state.notes.trim() || undefined,
    latitude: state.coordinate!.latitude,
    longitude: state.coordinate!.longitude,
  };
}

/** A reminder saved without a title is titled after its place, like in Reminders. */
function toLocationReminderInput(state: PlaceFormState): LocationReminderInput {
  return {
    title: state.reminder.title.trim() || placeName(state),
    placeName: placeName(state),
    address: state.address || undefined,
    notes: state.notes.trim() || undefined,
    latitude: state.coordinate!.latitude,
    longitude: state.coordinate!.longitude,
    trigger: state.reminder.trigger,
    radius: state.reminder.radius,
  };
}

/** What the form is editing: a saved place, a location reminder, or (if neither) something new. */
export type PlaceFormOriginal =
  { kind: 'place'; place: Place } | { kind: 'reminder'; reminder: LocationReminder };

/**
 * Saves the form as a place or, in the Reminders collection, a location reminder, moving it from
 * one to the other if its collection changed. Resolves false if it couldn't be saved.
 */
export function useSavePlaceForm() {
  const { remindersStatus, defaultReminderList, refresh } = useCalendar();

  return async (state: PlaceFormState, original?: PlaceFormOriginal): Promise<boolean> => {
    try {
      if (state.collectionId !== REMINDERS_COLLECTION_ID) {
        const input = toPlaceInput(state);
        if (original?.kind === 'place') updatePlace(original.place.id, input);
        else addPlace(input);
        if (original?.kind === 'reminder') {
          await original.reminder.reminder.source.delete();
          refresh();
        }
        return true;
      }

      const input = toLocationReminderInput(state);
      if (original?.kind === 'reminder') {
        await updateLocationReminder(original.reminder, input);
      } else {
        const list = defaultReminderList();
        if (!list) {
          Alert.alert(
            'Can’t Save Reminder',
            remindersStatus === 'granted'
              ? 'Add a list in Reminders to save location reminders.'
              : 'Location reminders are saved in Reminders. Allow access to Reminders in Settings.',
            remindersStatus === 'granted'
              ? undefined
              : [
                  { text: 'Not Now', style: 'cancel' },
                  { text: 'Open Settings', onPress: () => Linking.openSettings() },
                ],
          );
          return false;
        }
        await createLocationReminder(list, input);
        if (original?.kind === 'place') deletePlace(original.place.id);
      }
      refresh();
      return true;
    } catch (error) {
      Alert.alert('Couldn’t Save', String(error));
      return false;
    }
  };
}

export function PlaceFormFields({
  form,
  collections,
  footer,
}: {
  form: PlaceForm;
  collections: Collection[];
  footer?: React.ReactNode;
}) {
  const theme = useTheme();
  const { state, update, updateReminder, isReminder } = form;
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const mapRef = useRef<MapView>(null);
  const reminderColor =
    collections.find((c) => c.id === REMINDERS_COLLECTION_ID)?.color ?? theme.tint;
  const color = collections.find((c) => c.id === state.collectionId)?.color ?? theme.tint;

  // Fill in the name and address for a new pin.
  const resolveAddress = async (coordinate: Coordinate, overwriteName: boolean) => {
    const described = await describeCoordinate(coordinate);
    if (!described) return;
    form.update({ address: described.address });
    if (overwriteName) form.update({ name: described.name });
  };

  useEffect(() => {
    if (state.coordinate && !state.address) resolveAddress(state.coordinate, !state.name);
    // Only on first mount; later moves are handled by onDragEnd.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (state.coordinate) {
      mapRef.current?.animateToRegion({
        ...state.coordinate,
        ...regionSpan(isReminder ? state.reminder.radius : 0),
      });
    }
  }, [state.coordinate, isReminder, state.reminder.radius]);

  const runSearch = async () => {
    setSearching(true);
    const coordinate = await searchAddress(query);
    setSearching(false);
    if (!coordinate) {
      Alert.alert('Not Found', 'Try a more specific address.');
      return;
    }
    update({ coordinate });
    resolveAddress(coordinate, true);
  };

  return (
    <>
      <Section
        footer={
          state.coordinate
            ? state.address || 'Drag the pin to adjust the location.'
            : 'Search for an address, or long-press the map in Space.'
        }
      >
        {!state.coordinate || query ? (
          <View style={styles.searchRow}>
            <Icon name={icons.search} color={theme.secondaryText} size={16} />
            <Field
              style={styles.searchField}
              placeholder="Search for an address"
              value={query}
              onChangeText={setQuery}
              onSubmitEditing={runSearch}
              returnKeyType="search"
              autoCorrect={false}
            />
            {searching ? <ActivityIndicator /> : null}
          </View>
        ) : null}
        {state.coordinate ? (
          <MapView
            ref={mapRef}
            style={styles.preview}
            initialRegion={{
              ...state.coordinate,
              ...regionSpan(isReminder ? state.reminder.radius : 0),
            }}
            pitchEnabled={false}
            rotateEnabled={false}
            toolbarEnabled={false}
          >
            <Marker
              key={color}
              coordinate={state.coordinate}
              pinColor={color}
              draggable
              onDragEnd={(e) => {
                const coordinate = e.nativeEvent.coordinate;
                update({ coordinate, address: '' });
                resolveAddress(coordinate, false);
              }}
            />
            {isReminder ? (
              <Circle
                key={`${reminderColor}:${state.reminder.radius}`}
                center={state.coordinate}
                radius={state.reminder.radius}
                strokeColor={withAlpha(reminderColor, 0.8)}
                fillColor={withAlpha(reminderColor, 0.15)}
              />
            ) : null}
          </MapView>
        ) : null}
      </Section>

      <Section>
        {isReminder ? (
          <>
            <Field
              placeholder="Remind me to…"
              value={state.reminder.title}
              onChangeText={(title) => updateReminder({ title })}
            />
            <Separator />
          </>
        ) : null}
        <Field
          placeholder="Place name"
          value={state.name}
          onChangeText={(name) => update({ name })}
        />
      </Section>

      <Section title="Collection">
        <View style={styles.collections}>
          {collections.map((collection) => {
            const selected = collection.id === state.collectionId;
            return (
              <Pressable
                key={collection.id}
                onPress={() => update({ collectionId: collection.id })}
                style={[
                  styles.collectionChip,
                  { borderColor: collection.color },
                  selected && { backgroundColor: collection.color },
                ]}
                accessibilityRole="radio"
                accessibilityState={{ selected }}
              >
                {collection.id === REMINDERS_COLLECTION_ID ? (
                  <Icon name={icons.bell} size={12} color={selected ? '#fff' : collection.color} />
                ) : null}
                <Text style={[styles.collectionLabel, { color: selected ? '#fff' : theme.text }]}>
                  {collection.name}
                </Text>
              </Pressable>
            );
          })}
        </View>
      </Section>

      {isReminder ? (
        <Section
          title="Remind Me"
          footer={`Saved in Reminders, which notifies you when you ${
            state.reminder.trigger === 'arrive' ? 'arrive' : 'leave'
          }.`}
        >
          <Segmented<ReminderTrigger>
            options={[
              { label: 'When Arriving', value: 'arrive' },
              { label: 'When Leaving', value: 'leave' },
            ]}
            value={state.reminder.trigger}
            onChange={(trigger) => updateReminder({ trigger })}
          />
          <Separator />
          <Segmented<number>
            options={RADIUS_OPTIONS}
            value={state.reminder.radius}
            onChange={(radius) => updateReminder({ radius })}
          />
        </Section>
      ) : null}

      <Section title="Notes">
        <Field
          placeholder="Notes"
          value={state.notes}
          onChangeText={(notes) => update({ notes })}
          multiline
        />
      </Section>

      {footer}
    </>
  );
}

/** A map span that comfortably fits a geofence of the given radius. */
function regionSpan(radius: number) {
  const meters = Math.max(400, radius * 3.2);
  const delta = meters / 111_000;
  return { latitudeDelta: delta, longitudeDelta: delta };
}

const styles = StyleSheet.create({
  searchRow: { flexDirection: 'row', alignItems: 'center', paddingLeft: 14, paddingRight: 12 },
  searchField: { flex: 1, paddingHorizontal: 8 },
  preview: { height: 180 },
  collections: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, padding: 12 },
  collectionChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 16,
    borderWidth: 1.5,
  },
  collectionLabel: { fontSize: 15, fontWeight: '500' },
});
