// Shared across isolated module registries so reloading the store reads what was saved.
const mockStorage = new Map<string, string>();
jest.mock('expo-sqlite/kv-store', () => ({
  __esModule: true,
  default: {
    getItemSync: (key: string) => mockStorage.get(key) ?? null,
    setItemSync: (key: string, value: string) => mockStorage.set(key, value),
  },
}));
jest.mock('expo-calendar', () => ({}));

type Store = typeof import('../reminderMeta');

function loadStore(): Store {
  let store!: Store;
  jest.isolateModules(() => {
    store = require('../reminderMeta');
  });
  return store;
}

const exists = (ids: string[]) => async (id: string) => ids.includes(id);

describe('reminder metadata', () => {
  beforeEach(() => mockStorage.clear());

  it('persists across reloads and forgets empty metadata', () => {
    loadStore().setReminderMeta({ id: 'a' }, { address: '1 Main St' });
    const store = loadStore();
    expect(store.getReminderMeta({ id: 'a' })).toEqual({ address: '1 Main St' });

    store.setReminderMeta({ id: 'a' }, { address: undefined });
    expect(loadStore().getReminderMeta({ id: 'a' })).toEqual({});
  });

  it('finds a reminder by its external ID after its local ID changes', () => {
    const store = loadStore();
    store.setReminderMeta({ id: 'old', externalId: 'X' }, { address: 'Home' });
    expect(store.getReminderMeta({ id: 'new', externalId: 'X' })).toEqual({ address: 'Home' });
  });

  it('picks up new IDs from the reminders it sees', async () => {
    const store = loadStore();
    store.setReminderMeta({ id: 'a' }, { address: 'Home' });
    await store.reconcileReminderMeta([{ id: 'a', externalId: 'X' }], exists([]));
    // Now it can be found after a resync changes the local ID.
    expect(store.getReminderMeta({ id: 'b', externalId: 'X' })).toEqual({ address: 'Home' });

    await store.reconcileReminderMeta([{ id: 'b', externalId: 'X' }], exists([]));
    expect(store.getReminderMeta({ id: 'b' })).toEqual({ address: 'Home' });
  });

  it('forgets reminders that no longer exist, but keeps unseen ones that do', async () => {
    const store = loadStore();
    store.setReminderMeta({ id: 'deleted' }, { address: 'Gone' });
    store.setReminderMeta({ id: 'completed' }, { address: 'Done' });
    store.setReminderMeta({ id: 'open' }, { address: 'Here' });
    await store.reconcileReminderMeta([{ id: 'open' }], exists(['completed', 'open']));
    expect(store.getReminderMeta({ id: 'deleted' })).toEqual({});
    expect(store.getReminderMeta({ id: 'completed' })).toEqual({ address: 'Done' });
    expect(store.getReminderMeta({ id: 'open' })).toEqual({ address: 'Here' });
  });

  it('keeps metadata saved while it was reconciling', async () => {
    const store = loadStore();
    store.setReminderMeta({ id: 'deleted' }, { address: 'Gone' });
    await store.reconcileReminderMeta([], async () => {
      store.setReminderMeta({ id: 'new' }, { address: 'Just saved' });
      return false;
    });
    expect(store.getReminderMeta({ id: 'new' })).toEqual({ address: 'Just saved' });
    expect(store.getReminderMeta({ id: 'deleted' })).toEqual({});
  });
});
