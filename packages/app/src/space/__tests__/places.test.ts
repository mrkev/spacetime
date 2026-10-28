jest.mock('expo-sqlite/kv-store', () => ({
  __esModule: true,
  default: { getItemSync: () => null, setItemSync: () => {} },
}));
jest.mock('expo-calendar', () => ({}));
jest.mock('../../time/CalendarProvider', () => ({}));

import type { LocationReminder } from '../locationReminders';
import { buildMapPlaces, findMapPlace, isInCollection, pinColor } from '../places';
import { REMINDERS_COLLECTION_ID, type Collection, type Place } from '../store';

const bakery = { latitude: 19.4326, longitude: -99.1332 };
// About 11 m north of the bakery.
const nearBakery = { latitude: 19.4327, longitude: -99.1332 };
// About 1.1 km north.
const elsewhere = { latitude: 19.4426, longitude: -99.1332 };

function place(id: string, collectionIds: string[], at = bakery): Place {
  return { ...at, id, collectionIds, name: id, createdAt: 0 };
}

function todo(id: string, at: typeof bakery, placeName = 'Spot'): LocationReminder {
  return {
    ...at,
    id,
    title: id,
    placeName,
    trigger: 'arrive',
    radius: 100,
    completed: false,
    reminder: {} as LocationReminder['reminder'],
  };
}

const collections: Collection[] = [
  { id: REMINDERS_COLLECTION_ID, name: 'Reminders', color: '#FF9500', createdAt: 0 },
  { id: 'food', name: 'Food', color: '#34C759', createdAt: 1 },
  { id: 'favorites', name: 'Favorites', color: '#007AFF', createdAt: 2 },
];

describe('buildMapPlaces', () => {
  it('gives saved places the todos near them', () => {
    const [mapPlace, ...rest] = buildMapPlaces(
      [place('bakery', ['food'])],
      [todo('bread', nearBakery)],
    );
    expect(rest).toEqual([]);
    expect(mapPlace.saved?.id).toBe('bakery');
    expect(mapPlace.todos.map((t) => t.id)).toEqual(['bread']);
  });

  it('groups todos that aren’t at a saved place into unsaved places', () => {
    const mapPlaces = buildMapPlaces(
      [place('bakery', ['food'])],
      [todo('a', elsewhere, 'Market'), todo('b', elsewhere), todo('bread', bakery)],
    );
    const unsaved = mapPlaces.filter((p) => !p.saved);
    expect(unsaved).toHaveLength(1);
    expect(unsaved[0].name).toBe('Market');
    expect(unsaved[0].todos.map((t) => t.id)).toEqual(['a', 'b']);
  });

  it('leaves out places waiting to move to Reminders', () => {
    expect(buildMapPlaces([place('old', [REMINDERS_COLLECTION_ID])], [])).toEqual([]);
  });
});

describe('findMapPlace', () => {
  it('finds an unsaved place by where it is, after its ID changes', () => {
    const before = buildMapPlaces([], [todo('bread', bakery)]);
    const after = buildMapPlaces([place('bakery', ['food'], nearBakery)], [todo('bread', bakery)]);
    expect(findMapPlace(after, before[0].id)?.id).toBe('bakery');
  });

  it('falls back to the place nearest where it was', () => {
    const mapPlaces = buildMapPlaces([place('bakery', ['food'])], []);
    expect(findMapPlace(mapPlaces, 'gone', nearBakery)?.id).toBe('bakery');
    expect(findMapPlace(mapPlaces, 'gone', elsewhere)).toBeNull();
  });
});

describe('pinColor', () => {
  it('uses the first collection, or the Reminders color for an unsaved place', () => {
    const [saved, unsaved] = buildMapPlaces(
      [place('bakery', ['favorites', 'food'])],
      [todo('a', elsewhere)],
    );
    expect(pinColor(saved, collections, '#000')).toBe('#007AFF');
    expect(pinColor(unsaved, collections, '#000')).toBe('#FF9500');
  });
});

describe('isInCollection', () => {
  it('puts places with todos in the Reminders collection', () => {
    const [saved, unsaved] = buildMapPlaces([place('bakery', ['food'])], [todo('a', elsewhere)]);
    expect(isInCollection(saved, 'food')).toBe(true);
    expect(isInCollection(saved, REMINDERS_COLLECTION_ID)).toBe(false);
    expect(isInCollection(unsaved, REMINDERS_COLLECTION_ID)).toBe(true);
  });
});
