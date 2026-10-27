const mockStorage = new Map<string, string>();
jest.mock('expo-sqlite/kv-store', () => ({
  __esModule: true,
  default: {
    getItemSync: (key: string) => mockStorage.get(key) ?? null,
    setItemSync: (key: string, value: string) => mockStorage.set(key, value),
  },
}));

const mockTasks = new Map<string, (body: unknown) => Promise<void>>();
jest.mock('expo-task-manager', () => ({
  defineTask: (name: string, executor: (body: unknown) => Promise<void>) =>
    mockTasks.set(name, executor),
}));

jest.mock('expo-notifications', () => ({
  scheduleNotificationAsync: jest.fn(async () => 'id'),
  requestPermissionsAsync: jest.fn(async () => ({ granted: true })),
  setNotificationChannelAsync: jest.fn(),
  AndroidImportance: { HIGH: 4 },
}));

jest.mock('expo-location', () => ({
  GeofencingEventType: { Enter: 1, Exit: 2 },
  hasStartedGeofencingAsync: jest.fn(async () => false),
  startGeofencingAsync: jest.fn(async () => {}),
  stopGeofencingAsync: jest.fn(async () => {}),
  getBackgroundPermissionsAsync: jest.fn(async () => ({ granted: true })),
  getLastKnownPositionAsync: jest.fn(async () => null),
}));

import type { LocationReminder } from '../store';

// Required (not imported) so the mocks above exist before geofence.ts defines its task.
const Location = require('expo-location');
const Notifications = require('expo-notifications');
const { GEOFENCE_TASK, syncGeofences } = require('../geofence') as typeof import('../geofence');
const { REMINDERS_COLLECTION_ID, addPlace, getSpaceState } =
  require('../store') as typeof import('../store');

const schedule = Notifications.scheduleNotificationAsync as jest.Mock;
const ENTER = 1;
const EXIT = 2;

function makeReminder(overrides: Partial<LocationReminder> = {}) {
  return addPlace({
    collectionId: REMINDERS_COLLECTION_ID,
    name: 'Grocery Store',
    latitude: 37.78,
    longitude: -122.41,
    reminder: {
      title: 'Buy milk',
      trigger: 'arrive',
      radius: 250,
      repeat: false,
      enabled: true,
      ...overrides,
    },
  });
}

function fire(placeId: string, eventType: number) {
  const task = mockTasks.get(GEOFENCE_TASK)!;
  return task({ data: { eventType, region: { identifier: placeId } }, error: null });
}

const reminderOf = (id: string) => getSpaceState().places.find((p) => p.id === id)!.reminder!;

beforeEach(() => {
  schedule.mockClear();
});

describe('geofence task', () => {
  it('notifies when arriving and completes one-off reminders', async () => {
    const place = makeReminder({ lastState: 'outside' });
    await fire(place.id, ENTER);

    expect(schedule).toHaveBeenCalledTimes(1);
    expect(schedule.mock.calls[0][0].content).toMatchObject({
      title: 'Buy milk',
      body: 'Arrived at Grocery Store',
      data: { placeId: place.id },
    });
    expect(reminderOf(place.id)).toMatchObject({ enabled: false, lastState: 'inside' });
  });

  it('ignores the initial "inside" report when we already knew we were there', async () => {
    const place = makeReminder({ lastState: 'inside' });
    await fire(place.id, ENTER);
    expect(schedule).not.toHaveBeenCalled();
  });

  it('only fires a leave reminder after we were inside', async () => {
    const place = makeReminder({ trigger: 'leave' });
    await fire(place.id, EXIT);
    expect(schedule).not.toHaveBeenCalled();
    expect(reminderOf(place.id).lastState).toBe('outside');

    await fire(place.id, ENTER);
    expect(schedule).not.toHaveBeenCalled();

    await fire(place.id, EXIT);
    expect(schedule).toHaveBeenCalledTimes(1);
    expect(schedule.mock.calls[0][0].content.body).toBe('Left Grocery Store');
  });

  it('keeps repeating reminders active but skips flapping at the edge', async () => {
    const place = makeReminder({ repeat: true, lastState: 'outside' });
    await fire(place.id, ENTER);
    await fire(place.id, EXIT);
    await fire(place.id, ENTER);

    expect(schedule).toHaveBeenCalledTimes(1);
    expect(reminderOf(place.id)).toMatchObject({ enabled: true, lastState: 'inside' });
  });

  it('ignores events for disabled or unknown reminders', async () => {
    const place = makeReminder({ enabled: false, lastState: 'outside' });
    await fire(place.id, ENTER);
    await fire('missing', ENTER);
    expect(schedule).not.toHaveBeenCalled();
  });
});

describe('syncGeofences', () => {
  it('registers active reminders and seeds their state from the current position', async () => {
    (Location.getLastKnownPositionAsync as jest.Mock).mockResolvedValueOnce({
      coords: { latitude: 37.78, longitude: -122.41 },
    });
    const place = makeReminder();
    await syncGeofences();

    const regions = (Location.startGeofencingAsync as jest.Mock).mock.calls.at(-1)[1];
    expect(regions).toContainEqual(
      expect.objectContaining({ identifier: place.id, radius: 250, notifyOnEnter: true, notifyOnExit: true }),
    );
    // We're standing on the pin, so arriving shouldn't fire until we leave and come back.
    expect(reminderOf(place.id).lastState).toBe('inside');
  });

  it('does not register geofences without background permission', async () => {
    (Location.getBackgroundPermissionsAsync as jest.Mock).mockResolvedValueOnce({ granted: false });
    (Location.startGeofencingAsync as jest.Mock).mockClear();
    makeReminder({ title: 'Another' });
    await syncGeofences();
    expect(Location.startGeofencingAsync).not.toHaveBeenCalled();
  });
});
