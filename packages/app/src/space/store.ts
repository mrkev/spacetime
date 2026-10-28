import Storage from 'expo-sqlite/kv-store';
import { useSyncExternalStore } from 'react';

import { createId } from '../lib/id';

/**
 * The built-in collection of location reminders. Its places are reminders in Apple Reminders (see
 * `locationReminders.ts`); only its name and color are stored here.
 */
export const REMINDERS_COLLECTION_ID = 'reminders';

export type Collection = {
  id: string;
  name: string;
  color: string;
  createdAt: number;
};

/** A location reminder from before they moved to Apple Reminders. */
export type LegacyReminder = {
  title: string;
  trigger: 'arrive' | 'leave';
  radius: number;
  enabled: boolean;
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
  /** Only on places saved in the Reminders collection by older versions, until they're moved. */
  reminder?: LegacyReminder;
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

export type PlaceInput = Omit<Place, 'id' | 'createdAt' | 'reminder'>;

export function addPlace(input: PlaceInput): Place {
  const place: Place = { ...input, id: createId(), createdAt: Date.now() };
  setState({ ...state, places: [...state.places, place] });
  return place;
}

export function updatePlace(id: string, changes: Partial<PlaceInput>) {
  setState({
    ...state,
    places: state.places.map((p) => (p.id === id ? { ...p, ...changes } : p)),
  });
}

export function deletePlace(id: string) {
  setState({ ...state, places: state.places.filter((p) => p.id !== id) });
}
