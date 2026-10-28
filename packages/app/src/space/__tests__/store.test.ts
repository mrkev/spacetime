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
    first.addPlace({ ...coords, collectionId: collection.id, name: 'Blue Bottle' });

    const second = loadStore();
    expect(second.getSpaceState().collections.find((c) => c.id === collection.id)?.name).toBe(
      'Coffee',
    );
    expect(second.getSpaceState().places.some((p) => p.name === 'Blue Bottle')).toBe(true);
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
