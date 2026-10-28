import { distanceMeters, type Coordinate } from '../lib/geo';
import {
  updateLocationReminder,
  useLocationReminders,
  type LocationReminder,
} from './locationReminders';
import {
  REMINDERS_COLLECTION_ID,
  addPlace,
  isLegacyReminder,
  updatePlace,
  useSpaceState,
  type Collection,
  type Place,
} from './store';

/** How close (in meters) a todo has to be to a place to belong to it. */
export const LINK_RADIUS = 30;

const UNSAVED_PREFIX = 'unsaved:';

/**
 * A pin on the map: a saved place, or a spot with todos that isn't saved in any collection. Todos
 * are location reminders, and belong to the nearest place within `LINK_RADIUS`.
 */
export type MapPlace = Coordinate & {
  /** The saved place's ID, or `unsaved:<latitude>,<longitude>`. */
  id: string;
  name: string;
  address?: string;
  /** Null if the place only exists because of its todos. */
  saved: Place | null;
  collectionIds: string[];
  todos: LocationReminder[];
};

export function buildMapPlaces(places: Place[], todos: LocationReminder[]): MapPlace[] {
  const saved: MapPlace[] = places
    .filter((p) => !isLegacyReminder(p))
    .map((place) => ({
      id: place.id,
      name: place.name,
      address: place.address,
      latitude: place.latitude,
      longitude: place.longitude,
      saved: place,
      collectionIds: place.collectionIds,
      todos: [],
    }));
  const unsaved: MapPlace[] = [];
  for (const todo of todos) {
    const owner = nearest(saved, todo) ?? nearest(unsaved, todo);
    if (owner) {
      owner.todos.push(todo);
      continue;
    }
    unsaved.push({
      id: `${UNSAVED_PREFIX}${todo.latitude.toFixed(6)},${todo.longitude.toFixed(6)}`,
      name: todo.placeName,
      address: todo.address,
      latitude: todo.latitude,
      longitude: todo.longitude,
      saved: null,
      collectionIds: [],
      todos: [todo],
    });
  }
  return [...saved, ...unsaved];
}

function nearest(candidates: MapPlace[], to: Coordinate): MapPlace | null {
  let best: MapPlace | null = null;
  let bestDistance = LINK_RADIUS;
  for (const candidate of candidates) {
    const distance = distanceMeters(candidate, to);
    if (distance <= bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

/**
 * Finds a place by ID or, failing that, the place nearest `near`. A place's ID changes when it's
 * saved or unsaved, but it stays where it was.
 */
export function findMapPlace(
  mapPlaces: MapPlace[],
  id: string,
  near?: Coordinate,
): MapPlace | null {
  const found = mapPlaces.find((p) => p.id === id);
  if (found) return found;
  const anchor = near ?? parseUnsavedId(id);
  return anchor ? nearest(mapPlaces, anchor) : null;
}

function parseUnsavedId(id: string): Coordinate | null {
  if (!id.startsWith(UNSAVED_PREFIX)) return null;
  const [latitude, longitude] = id.slice(UNSAVED_PREFIX.length).split(',').map(Number);
  return Number.isFinite(latitude) && Number.isFinite(longitude) ? { latitude, longitude } : null;
}

export function useMapPlaces(): MapPlace[] {
  const { places } = useSpaceState();
  const todos = useLocationReminders();
  return buildMapPlaces(places, todos);
}

/** The place's collections, in its order, skipping any that were deleted. */
export function placeCollections(
  place: Pick<MapPlace, 'collectionIds'>,
  collections: Collection[],
): Collection[] {
  return place.collectionIds.flatMap((id) => {
    const collection = collections.find((c) => c.id === id);
    return collection ? [collection] : [];
  });
}

/** Its first collection's color or, if it's in none, the Reminders collection's. */
export function pinColor(place: MapPlace, collections: Collection[], fallback: string): string {
  const [first] = placeCollections(place, collections);
  if (first) return first.color;
  return collections.find((c) => c.id === REMINDERS_COLLECTION_ID)?.color ?? fallback;
}

/** Whether the place shows when the map is filtered to a collection. */
export function isInCollection(place: MapPlace, collectionId: string): boolean {
  if (collectionId === REMINDERS_COLLECTION_ID) return place.todos.length > 0;
  return place.collectionIds.includes(collectionId);
}

/** Adds a place to a collection, saving it if it wasn't. */
export function addToCollection(place: MapPlace, collectionId: string) {
  if (place.collectionIds.includes(collectionId)) return;
  if (place.saved) {
    updatePlace(place.saved.id, { collectionIds: [...place.collectionIds, collectionId] });
    return;
  }
  addPlace({
    name: place.name,
    address: place.address,
    latitude: place.latitude,
    longitude: place.longitude,
    collectionIds: [collectionId],
  });
}

/** Sets a saved place's collections. Taking it out of all of them unsaves it. */
export function setCollections(place: MapPlace, collectionIds: string[]) {
  if (place.saved) updatePlace(place.saved.id, { collectionIds });
}

/** Moves a place's todos along with it, and keeps their place name and address in sync. */
export async function syncTodos(
  todos: LocationReminder[],
  place: Coordinate & { name: string; address?: string },
) {
  await Promise.all(
    todos.map((todo) =>
      updateLocationReminder(todo, {
        title: todo.title,
        notes: todo.notes,
        trigger: todo.trigger,
        radius: todo.radius,
        placeName: place.name,
        address: place.address,
        latitude: place.latitude,
        longitude: place.longitude,
      }),
    ),
  );
}
