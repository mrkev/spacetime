import Storage from 'expo-sqlite/kv-store';
import { useSyncExternalStore } from 'react';

import { createId } from '../lib/id';

/** The built-in collection whose places trigger a notification when you're nearby. */
export const REMINDERS_COLLECTION_ID = 'reminders';

export type Collection = {
  id: string;
  name: string;
  color: string;
  createdAt: number;
};

export type ReminderTrigger = 'arrive' | 'leave';

export type LocationReminder = {
  /** What to remind the user about, e.g. "Pick up dry cleaning". */
  title: string;
  trigger: ReminderTrigger;
  /** Geofence radius in meters. */
  radius: number;
  /** Keep the reminder active after it fires instead of completing it. */
  repeat: boolean;
  enabled: boolean;
  /** Last geofence state we observed, used to only notify on real transitions. */
  lastState?: 'inside' | 'outside';
  lastFiredAt?: number;
};

export type Place = {
  id: string;
  collectionId: string;
  name: string;
  address?: string;
  notes?: string;
  latitude: number;
  longitude: number;
  createdAt: number;
  /** Present only for places in the Reminders collection. */
  reminder?: LocationReminder;
};

export type SpaceState = {
  collections: Collection[];
  places: Place[];
};

const STORAGE_KEY = 'spacetime.space.v1';

function seed(): SpaceState {
  const now = Date.now();
  return {
    collections: [
      { id: REMINDERS_COLLECTION_ID, name: 'Reminders', color: '#FF9500', createdAt: now },
      { id: createId(), name: 'Favorites', color: '#007AFF', createdAt: now + 1 },
      { id: createId(), name: 'Want to Go', color: '#34C759', createdAt: now + 2 },
    ],
    places: [],
  };
}

function load(): SpaceState {
  try {
    const raw = Storage.getItemSync(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as SpaceState;
      if (!parsed.collections.some((c) => c.id === REMINDERS_COLLECTION_ID)) {
        parsed.collections.unshift(seed().collections[0]);
      }
      return parsed;
    }
  } catch (error) {
    console.warn('[space] failed to load saved places', error);
  }
  return seed();
}

let state: SpaceState = load();
const listeners = new Set<() => void>();

function setState(next: SpaceState) {
  state = next;
  try {
    Storage.setItemSync(STORAGE_KEY, JSON.stringify(next));
  } catch (error) {
    console.warn('[space] failed to save places', error);
  }
  listeners.forEach((listener) => listener());
}

export function getSpaceState(): SpaceState {
  return state;
}

export function subscribeSpace(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useSpaceState(): SpaceState {
  return useSyncExternalStore(subscribeSpace, getSpaceState);
}

// Collections

export function addCollection(name: string, color: string): Collection {
  const collection: Collection = { id: createId(), name, color, createdAt: Date.now() };
  setState({ ...state, collections: [...state.collections, collection] });
  return collection;
}

export function updateCollection(id: string, changes: Partial<Pick<Collection, 'name' | 'color'>>) {
  setState({
    ...state,
    collections: state.collections.map((c) => (c.id === id ? { ...c, ...changes } : c)),
  });
}

/** Deletes a collection and every place in it. The Reminders collection can't be deleted. */
export function deleteCollection(id: string) {
  if (id === REMINDERS_COLLECTION_ID) return;
  setState({
    collections: state.collections.filter((c) => c.id !== id),
    places: state.places.filter((p) => p.collectionId !== id),
  });
}

// Places

export type PlaceInput = Omit<Place, 'id' | 'createdAt'>;

function normalizePlace<T extends PlaceInput>(place: T): T {
  // Only places in the Reminders collection carry reminder settings.
  if (place.collectionId !== REMINDERS_COLLECTION_ID && place.reminder) {
    const { reminder: _reminder, ...rest } = place;
    return rest as T;
  }
  return place;
}

export function addPlace(input: PlaceInput): Place {
  const place: Place = normalizePlace({ ...input, id: createId(), createdAt: Date.now() });
  setState({ ...state, places: [...state.places, place] });
  return place;
}

export function updatePlace(id: string, changes: Partial<PlaceInput>) {
  setState({
    ...state,
    places: state.places.map((p) => {
      if (p.id !== id) return p;
      const next = normalizePlace({ ...p, ...changes });
      // Moving or resizing a geofence invalidates whatever state we last observed.
      if (next.reminder && p.reminder && geofenceChanged(p, next)) {
        next.reminder = { ...next.reminder, lastState: undefined };
      }
      return next;
    }),
  });
}

function geofenceChanged(a: Place, b: Place): boolean {
  return (
    a.latitude !== b.latitude ||
    a.longitude !== b.longitude ||
    a.reminder?.radius !== b.reminder?.radius ||
    (!a.reminder?.enabled && !!b.reminder?.enabled)
  );
}

export function updateReminderState(id: string, changes: Partial<LocationReminder>) {
  setState({
    ...state,
    places: state.places.map((p) =>
      p.id === id && p.reminder ? { ...p, reminder: { ...p.reminder, ...changes } } : p,
    ),
  });
}

export function deletePlace(id: string) {
  setState({ ...state, places: state.places.filter((p) => p.id !== id) });
}

export function isActiveReminder(place: Place): boolean {
  return place.collectionId === REMINDERS_COLLECTION_ID && !!place.reminder?.enabled;
}

export function describeReminder(reminder: LocationReminder): string {
  const when = reminder.trigger === 'arrive' ? 'Arriving' : 'Leaving';
  const radius = reminder.radius >= 1000 ? `${reminder.radius / 1000} km` : `${reminder.radius} m`;
  return `${when} · ${radius}`;
}
