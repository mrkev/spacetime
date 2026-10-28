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
const reminder = {
  title: 'Buy milk',
  trigger: 'arrive' as const,
  radius: 250,
  repeat: false,
  enabled: true,
};

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
    first.addPlace({ ...coords, collectionId: collection.id, name: 'Blue Bottle' });

    const second = loadStore();
    expect(second.getSpaceState().collections.find((c) => c.id === collection.id)?.name).toBe(
      'Coffee',
    );
    expect(second.getSpaceState().places.some((p) => p.name === 'Blue Bottle')).toBe(true);
  });

  it('only keeps reminder settings on places in the Reminders collection', () => {
    const store = loadStore();
    const other = store
      .getSpaceState()
      .collections.find((c) => c.id !== store.REMINDERS_COLLECTION_ID)!;
    const place = store.addPlace({ ...coords, collectionId: other.id, name: 'Park', reminder });
    expect(place.reminder).toBeUndefined();

    store.updatePlace(place.id, { collectionId: store.REMINDERS_COLLECTION_ID, reminder });
    const moved = store.getSpaceState().places.find((p) => p.id === place.id)!;
    expect(store.isActiveReminder(moved)).toBe(true);

    store.updatePlace(place.id, { collectionId: other.id });
    expect(store.getSpaceState().places.find((p) => p.id === place.id)?.reminder).toBeUndefined();
  });

  it('resets the observed geofence state when a reminder moves', () => {
    const store = loadStore();
    const place = store.addPlace({
      ...coords,
      collectionId: store.REMINDERS_COLLECTION_ID,
      name: 'Store',
      reminder: { ...reminder, lastState: 'inside' },
    });
    store.updatePlace(place.id, { latitude: coords.latitude + 0.01 });
    expect(
      store.getSpaceState().places.find((p) => p.id === place.id)?.reminder?.lastState,
    ).toBeUndefined();
  });

  it('deletes a collection with its places but never the Reminders collection', () => {
    const store = loadStore();
    const collection = store.addCollection('Temp', '#8E8E93');
    store.addPlace({ ...coords, collectionId: collection.id, name: 'Somewhere' });
    store.deleteCollection(collection.id);
    expect(store.getSpaceState().places.some((p) => p.collectionId === collection.id)).toBe(false);

    store.deleteCollection(store.REMINDERS_COLLECTION_ID);
    expect(
      store.getSpaceState().collections.some((c) => c.id === store.REMINDERS_COLLECTION_ID),
    ).toBe(true);
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
