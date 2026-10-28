import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import MapView, { Circle, Marker } from 'react-native-maps';

import { Field, Section, Segmented, Separator, SwitchRow } from '../components/Form';
import { Icon, icons } from '../components/Icon';
import { describeCoordinate, searchAddress, type Coordinate } from '../lib/geo';
import { useTheme, withAlpha } from '../lib/theme';
import {
  openSettings,
  permissionMessages,
  requestReminderPermissions,
  syncGeofences,
} from './geofence';
import {
  REMINDERS_COLLECTION_ID,
  type Collection,
  type LocationReminder,
  type PlaceInput,
  type ReminderTrigger,
} from './store';

export const RADIUS_OPTIONS = [
  { label: '100 m', value: 100 },
  { label: '250 m', value: 250 },
  { label: '500 m', value: 500 },
  { label: '1 km', value: 1000 },
];

const DEFAULT_REMINDER: LocationReminder = {
  title: '',
  trigger: 'arrive',
  radius: 250,
  repeat: false,
  enabled: true,
};

export type PlaceFormState = {
  coordinate: Coordinate | null;
  name: string;
  address: string;
  notes: string;
  collectionId: string;
  reminder: LocationReminder;
};

export function usePlaceForm(initial: Partial<PlaceFormState> & { collectionId: string }) {
  const [state, setState] = useState<PlaceFormState>({
    coordinate: null,
    name: '',
    address: '',
    notes: '',
    ...initial,
    reminder: { ...DEFAULT_REMINDER, ...initial.reminder },
  });
  const update = (changes: Partial<PlaceFormState>) => setState((s) => ({ ...s, ...changes }));
  const updateReminder = (changes: Partial<LocationReminder>) =>
    setState((s) => ({ ...s, reminder: { ...s.reminder, ...changes } }));

  const isReminder = state.collectionId === REMINDERS_COLLECTION_ID;
  const canSave =
    !!state.coordinate &&
    (isReminder ? !!(state.reminder.title.trim() || state.name.trim()) : !!state.name.trim());

  return { state, update, updateReminder, isReminder, canSave };
}

export type PlaceForm = ReturnType<typeof usePlaceForm>;

/** Converts form state to a place, filling in a name for reminders saved without one. */
export function toPlaceInput(state: PlaceFormState): PlaceInput {
  const isReminder = state.collectionId === REMINDERS_COLLECTION_ID;
  return {
    collectionId: state.collectionId,
    name: state.name.trim() || 'Dropped Pin',
    address: state.address || undefined,
    notes: state.notes.trim() || undefined,
    latitude: state.coordinate!.latitude,
    longitude: state.coordinate!.longitude,
    reminder: isReminder ? { ...state.reminder, title: state.reminder.title.trim() } : undefined,
  };
}

/**
 * Makes sure a location reminder can actually fire, explaining what's missing if not.
 * The reminder is saved either way; it starts working once permissions are granted.
 */
export async function ensureReminderPermissions() {
  const result = await requestReminderPermissions();
  if (result.ok) {
    await syncGeofences();
    return;
  }
  Alert.alert('Reminder Saved', permissionMessages[result.reason], [
    { text: 'Not Now', style: 'cancel' },
    { text: 'Open Settings', onPress: openSettings },
  ]);
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
          footer={
            state.reminder.repeat
              ? 'You’ll be notified every time.'
              : 'The reminder completes after it notifies you once.'
          }
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
          <Separator />
          <SwitchRow
            label="Repeat"
            value={state.reminder.repeat}
            onValueChange={(repeat) => updateReminder({ repeat })}
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
