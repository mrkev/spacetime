// Shared across isolated module registries so reloading the store reads what was saved.
const mockStorage = new Map<string, string>();
jest.mock('expo-sqlite/kv-store', () => ({
  __esModule: true,
  default: {
    getItemSync: (key: string) => mockStorage.get(key) ?? null,
    setItemSync: (key: string, value: string) => mockStorage.set(key, value),
  },
}));

type Store = typeof import('../store');

function loadStore(): Store {
  let store!: Store;
  jest.isolateModules(() => {
    store = require('../store');
  });
  return store;
}

const coords = { latitude: 37.78, longitude: -122.41 };

describe('space store', () => {
  it('seeds the Reminders collection', () => {
    const store = loadStore();
    expect(store.getSpaceState().collections.map((c) => c.id)).toContain(
      store.REMINDERS_COLLECTION_ID,
    );
  });

  it('persists changes across reloads', () => {
    const first = loadStore();
    const collection = first.addCollection('Coffee', '#A2845E');
    first.addPlace({ ...coords, collectionIds: [collection.id], name: 'Blue Bottle' });

    const second = loadStore();
    expect(second.getSpaceState().collections.find((c) => c.id === collection.id)?.name).toBe(
      'Coffee',
    );
    expect(second.getSpaceState().places.some((p) => p.name === 'Blue Bottle')).toBe(true);
  });

  it('deletes a collection with the places only in it, but never the Reminders collection', () => {
    const store = loadStore();
    const collection = store.addCollection('Temp', '#8E8E93');
    const other = store.addCollection('Other', '#8E8E93');
    const only = store.addPlace({ ...coords, collectionIds: [collection.id], name: 'Somewhere' });
    const both = store.addPlace({
      ...coords,
      collectionIds: [collection.id, other.id],
      name: 'Both',
    });
    expect(store.placesOnlyIn(collection.id).map((p) => p.id)).toEqual([only.id]);
    store.deleteCollection(collection.id);
    const { places } = store.getSpaceState();
    expect(places.some((p) => p.id === only.id)).toBe(false);
    expect(places.find((p) => p.id === both.id)?.collectionIds).toEqual([other.id]);

    store.deleteCollection(store.REMINDERS_COLLECTION_ID);
    expect(
      store.getSpaceState().collections.some((c) => c.id === store.REMINDERS_COLLECTION_ID),
    ).toBe(true);
  });

  it('moves places saved in a single collection to a list of them', () => {
    mockStorage.set(
      'spacetime.space.v1',
      JSON.stringify({
        collections: [],
        places: [{ ...coords, id: 'p', collectionId: 'c', name: 'Old', createdAt: 0 }],
      }),
    );
    const [place] = loadStore().getSpaceState().places;
    expect(place.collectionIds).toEqual(['c']);
    expect('collectionId' in place).toBe(false);
  });

  it('deletes a place taken out of every collection', () => {
    const store = loadStore();
    const place = store.addPlace({ ...coords, collectionIds: ['a'], name: 'Gone' });
    store.updatePlace(place.id, { collectionIds: [] });
    expect(store.getSpaceState().places.some((p) => p.id === place.id)).toBe(false);
  });

  it('notifies subscribers', () => {
    const store = loadStore();
    const listener = jest.fn();
    const unsubscribe = store.subscribeSpace(listener);
    store.addCollection('Bars', '#FF2D55');
    expect(listener).toHaveBeenCalledTimes(1);
    unsubscribe();
    store.addCollection('More bars', '#FF2D55');
    expect(listener).toHaveBeenCalledTimes(1);
  });
});
