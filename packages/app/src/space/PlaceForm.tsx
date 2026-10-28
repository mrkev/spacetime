import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import MapView, { Circle, Marker } from 'react-native-maps';

import { Field, Section, Segmented, Separator } from '../components/Form';
import { Icon, icons } from '../components/Icon';
import { describeCoordinate, searchPlaces, type Coordinate } from '../lib/geo';
import { PIN_OFFSET, useTheme, withAlpha } from '../lib/theme';
import type { ReminderTrigger } from './locationReminders';
import { loadMapRegion } from './mapRegion';
import { REMINDERS_COLLECTION_ID, type Collection } from './store';

export const RADIUS_OPTIONS = [
  { label: '100 m', value: 100 },
  { label: '250 m', value: 250 },
  { label: '500 m', value: 500 },
  { label: '1 km', value: 1000 },
];

/** How far around the current pin (in degrees, about 5 km) search looks first. */
const SEARCH_DELTA = 0.05;

export type LocationState = { coordinate: Coordinate | null; name: string; address: string };

/** The name given to a place saved without one. */
export function placeName(state: Pick<LocationState, 'name'>) {
  return state.name.trim() || 'Dropped Pin';
}

/**
 * Where a place is: a search field, a map with a pin, and its name. The pin can be dragged unless
 * `fixed`, and a todo's radius is drawn around it.
 */
export function LocationFields({
  state,
  update,
  color,
  radius,
  radiusColor,
  fixed = false,
}: {
  state: LocationState;
  update: (changes: Partial<LocationState>) => void;
  color: string;
  radius?: number;
  radiusColor?: string;
  fixed?: boolean;
}) {
  const theme = useTheme();
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const mapRef = useRef<MapView>(null);

  // Fill in the name and address for a new pin.
  const resolveAddress = async (coordinate: Coordinate, overwriteName: boolean) => {
    const described = await describeCoordinate(coordinate);
    if (!described) return;
    update(overwriteName ? described : { address: described.address });
  };

  useEffect(() => {
    if (state.coordinate && !state.address && !fixed) {
      resolveAddress(state.coordinate, !state.name);
    }
    // Only on first mount; later moves are handled by onDragEnd.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (state.coordinate) {
      mapRef.current?.animateToRegion({ ...state.coordinate, ...regionSpan(radius ?? 0) });
    }
  }, [state.coordinate, radius]);

  const runSearch = async () => {
    setSearching(true);
    const near = state.coordinate
      ? { ...state.coordinate, latitudeDelta: SEARCH_DELTA, longitudeDelta: SEARCH_DELTA }
      : loadMapRegion();
    const [place] = await searchPlaces(query, near);
    setSearching(false);
    if (!place) {
      Alert.alert('Not Found', 'Try a different search.');
      return;
    }
    const { name, address, ...coordinate } = place;
    update({ coordinate, name, address });
  };

  return (
    <>
      <Section
        footer={
          state.coordinate
            ? state.address || (fixed ? undefined : 'Drag the pin to adjust the location.')
            : 'Search for a place or address, or long-press the map in Space.'
        }
      >
        {!fixed && (!state.coordinate || query) ? (
          <View style={styles.searchRow}>
            <Icon name={icons.search} color={theme.secondaryText} size={16} />
            <Field
              style={styles.searchField}
              placeholder="Search for a place or address"
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
            initialRegion={{ ...state.coordinate, ...regionSpan(radius ?? 0) }}
            pitchEnabled={false}
            rotateEnabled={false}
            scrollEnabled={!fixed}
            zoomEnabled={!fixed}
            toolbarEnabled={false}
          >
            <Marker
              key={color}
              coordinate={state.coordinate}
              pinColor={color}
              centerOffset={PIN_OFFSET}
              draggable={!fixed}
              onDragEnd={(e) => {
                const coordinate = e.nativeEvent.coordinate;
                update({ coordinate, address: '' });
                resolveAddress(coordinate, false);
              }}
            />
            {radius && radiusColor ? (
              <Circle
                key={`${radiusColor}:${radius}`}
                center={state.coordinate}
                radius={radius}
                strokeColor={withAlpha(radiusColor, 0.8)}
                fillColor={withAlpha(radiusColor, 0.15)}
              />
            ) : null}
          </MapView>
        ) : null}
      </Section>

      {fixed ? null : (
        <Section>
          <Field
            placeholder="Place name"
            value={state.name}
            onChangeText={(name) => update({ name })}
          />
        </Section>
      )}
    </>
  );
}

/** Picks any number of collections, in the order they're picked. */
export function CollectionPicker({
  collections,
  value,
  onChange,
  footer,
}: {
  collections: Collection[];
  value: string[];
  onChange: (collectionIds: string[]) => void;
  footer?: string;
}) {
  const theme = useTheme();
  return (
    <Section title="Collections" footer={footer}>
      <View style={styles.collections}>
        {collections
          .filter((c) => c.id !== REMINDERS_COLLECTION_ID)
          .map((collection) => {
            const selected = value.includes(collection.id);
            return (
              <Pressable
                key={collection.id}
                onPress={() =>
                  onChange(
                    selected
                      ? value.filter((id) => id !== collection.id)
                      : [...value, collection.id],
                  )
                }
                style={[
                  styles.collectionChip,
                  { borderColor: collection.color },
                  selected && { backgroundColor: collection.color },
                ]}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: selected }}
              >
                {selected ? <Icon name={icons.check} size={12} color="#fff" /> : null}
                <Text style={[styles.collectionLabel, { color: selected ? '#fff' : theme.text }]}>
                  {collection.name}
                </Text>
              </Pressable>
            );
          })}
      </View>
    </Section>
  );
}

/** What a todo (a location reminder) has besides its place. */
export type TodoState = { title: string; trigger: ReminderTrigger; radius: number; notes: string };

export const DEFAULT_TODO: TodoState = { title: '', trigger: 'arrive', radius: 250, notes: '' };

export function TodoFields({
  todo,
  update,
  optional = false,
}: {
  todo: TodoState;
  update: (changes: Partial<TodoState>) => void;
  /** Hides the trigger until there's a title, for a form where the todo is optional. */
  optional?: boolean;
}) {
  const showTrigger = !optional || !!todo.title.trim();
  return (
    <Section
      title="Todo"
      footer={
        showTrigger
          ? `Saved in Reminders, which notifies you when you ${todo.trigger}.`
          : 'Optional. Saved in Reminders, which notifies you when you get there.'
      }
    >
      <Field
        placeholder="Remind me to…"
        value={todo.title}
        onChangeText={(title) => update({ title })}
      />
      {showTrigger ? (
        <>
          <Separator />
          <Segmented<ReminderTrigger>
            options={[
              { label: 'When Arriving', value: 'arrive' },
              { label: 'When Leaving', value: 'leave' },
            ]}
            value={todo.trigger}
            onChange={(trigger) => update({ trigger })}
          />
          <Separator />
          <Segmented<number>
            options={RADIUS_OPTIONS}
            value={todo.radius}
            onChange={(radius) => update({ radius })}
          />
        </>
      ) : null}
    </Section>
  );
}

/** A map span that comfortably fits a geofence of the given radius. */
export function regionSpan(radius: number) {
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
