import Storage from 'expo-sqlite/kv-store';
import { useSyncExternalStore } from 'react';

import { createId } from '../lib/id';

/**
 * The built-in collection of places with todos, which are location reminders in Apple Reminders
 * (see `locationReminders.ts`). Places can't be added to it; only its name and color are stored.
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

/** A saved place: one that's in at least one collection. */
export type Place = {
  id: string;
  /** In the order the user sorted them. The first one colors the place's pin. */
  collectionIds: string[];
  name: string;
  address?: string;
  notes?: string;
  latitude: number;
  longitude: number;
  createdAt: number;
  /** Only on places saved in the Reminders collection by older versions, until they're moved. */
  reminder?: LegacyReminder;
};

/** A place in the Reminders collection, from before location reminders moved to Apple Reminders. */
export function isLegacyReminder(place: Place): boolean {
  return place.collectionIds.includes(REMINDERS_COLLECTION_ID);
}

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
      // Places used to be in a single collection.
      parsed.places = parsed.places.map(
        ({ collectionId, ...place }: Place & { collectionId?: string }) =>
          place.collectionIds
            ? place
            : { ...place, collectionIds: collectionId ? [collectionId] : [] },
      );
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

/**
 * Deletes a collection, and the places that were only in it. The Reminders collection can't be
 * deleted.
 */
export function deleteCollection(id: string) {
  if (id === REMINDERS_COLLECTION_ID) return;
  setState({
    collections: state.collections.filter((c) => c.id !== id),
    places: state.places.flatMap((p) => {
      if (!p.collectionIds.includes(id)) return [p];
      const collectionIds = p.collectionIds.filter((c) => c !== id);
      return collectionIds.length > 0 ? [{ ...p, collectionIds }] : [];
    }),
  });
}

/** The places that are only in this collection, which deleting it deletes. */
export function placesOnlyIn(id: string): Place[] {
  return state.places.filter((p) => p.collectionIds.length === 1 && p.collectionIds[0] === id);
}

// Places

export type PlaceInput = Omit<Place, 'id' | 'createdAt' | 'reminder'>;

export function addPlace(input: PlaceInput): Place {
  const place: Place = { ...input, id: createId(), createdAt: Date.now() };
  setState({ ...state, places: [...state.places, place] });
  return place;
}

/** Updates a place. Taking it out of every collection deletes it. */
export function updatePlace(id: string, changes: Partial<PlaceInput>) {
  if (changes.collectionIds?.length === 0) {
    deletePlace(id);
    return;
  }
  setState({
    ...state,
    places: state.places.map((p) => (p.id === id ? { ...p, ...changes } : p)),
  });
}

export function deletePlace(id: string) {
  setState({ ...state, places: state.places.filter((p) => p.id !== id) });
}
