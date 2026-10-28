import type { EventLocation } from 'expo-calendar';

import { formatRelativeDay, formatTime } from '../lib/dates';
import { distanceMeters, type Coordinate } from '../lib/geo';
import { useCalendar, type CalendarEvent } from '../time/CalendarProvider';
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

/** How close (in meters) a todo or event has to be to a place to belong to it. */
export const LINK_RADIUS = 30;

const UNSAVED_PREFIX = 'unsaved:';

/**
 * A pin on the map: a saved place, or a spot with todos or upcoming events that isn't saved in any
 * collection. Todos (location reminders) and events belong to the nearest place within
 * `LINK_RADIUS`.
 */
export type MapPlace = Coordinate & {
  /** The saved place's ID, or `unsaved:<latitude>,<longitude>`. */
  id: string;
  name: string;
  address?: string;
  /** Null if the place only exists because of its todos or events. */
  saved: Place | null;
  collectionIds: string[];
  todos: LocationReminder[];
  /** Upcoming events here, soonest first. */
  events: CalendarEvent[];
};

export function buildMapPlaces(
  places: Place[],
  todos: LocationReminder[],
  events: CalendarEvent[] = [],
): MapPlace[] {
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
      events: [],
    }));
  const unsaved: MapPlace[] = [];
  const ownerAt = (at: Coordinate, name: string, address: string | undefined) => {
    const owner = nearest(saved, at) ?? nearest(unsaved, at);
    if (owner) return owner;
    const place: MapPlace = {
      id: `${UNSAVED_PREFIX}${at.latitude.toFixed(6)},${at.longitude.toFixed(6)}`,
      name,
      address,
      latitude: at.latitude,
      longitude: at.longitude,
      saved: null,
      collectionIds: [],
      todos: [],
      events: [],
    };
    unsaved.push(place);
    return place;
  };
  for (const todo of todos) {
    ownerAt(todo, todo.placeName, todo.address).todos.push(todo);
  }
  for (const event of events) {
    if (!event.place) continue;
    const { name, address } = parseLocationTitle(event.place.title);
    ownerAt(event.place, name, address).events.push(event);
  }
  return [...saved, ...unsaved];
}

/**
 * An event's location for a place. Like Calendar, it's the name with the address on the next line.
 */
export function eventLocation(
  place: Coordinate & { name: string; address?: string },
): EventLocation {
  return {
    title: place.address ? `${place.name}\n${place.address}` : place.name,
    latitude: place.latitude,
    longitude: place.longitude,
  };
}

/** When an event is, for a list of a place's events: "Tomorrow · 8:00 PM · Repeats". */
export function describeEventTime(event: CalendarEvent): string {
  return [
    formatRelativeDay(event.start),
    event.allDay ? 'All Day' : formatTime(event.start),
    event.recurring ? 'Repeats' : null,
  ]
    .filter(Boolean)
    .join(' · ');
}

/** The name and address in an event's location (see `eventLocation`). */
export function parseLocationTitle(title: string): { name: string; address?: string } {
  const [name, ...rest] = title.split('\n');
  const address = rest.join(', ').trim();
  return { name: name.trim() || 'Dropped Pin', address: address || undefined };
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
  const { upcomingEvents } = useCalendar();
  return buildMapPlaces(places, todos, upcomingEvents);
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

/**
 * Its first collection's color. If it's in none: the Reminders collection's if it has todos, or
 * else its next event's calendar's.
 */
export function pinColor(place: MapPlace, collections: Collection[], fallback: string): string {
  const [first] = placeCollections(place, collections);
  if (first) return first.color;
  if (place.todos.length === 0 && place.events.length > 0) return place.events[0].color;
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
