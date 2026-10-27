import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import * as TaskManager from 'expo-task-manager';
import { AppState, Linking, Platform } from 'react-native';

import { distanceMeters, type Coordinate } from '../lib/geo';
import {
  getSpaceState,
  isActiveReminder,
  subscribeSpace,
  updateReminderState,
  type Place,
} from './store';

export const GEOFENCE_TASK = 'spacetime-location-reminders';
export const REMINDER_CHANNEL_ID = 'location-reminders';

// iOS monitors at most 20 regions per app; Android allows 100.
const MAX_REGIONS = Platform.OS === 'ios' ? 20 : 100;
// Ignore GPS jitter at the edge of a region so one visit doesn't notify twice.
const REFIRE_COOLDOWN_MS = 10 * 60_000;

type GeofenceEvent = {
  eventType: Location.GeofencingEventType;
  region: Location.LocationRegion;
};

// Must be defined at module scope so it exists when iOS relaunches the app for a geofence event.
TaskManager.defineTask<GeofenceEvent>(GEOFENCE_TASK, async ({ data, error }) => {
  if (error) {
    console.warn('[geofence] task error', error.message);
    return;
  }
  const placeId = data?.region?.identifier;
  if (!placeId) return;
  await handleTransition(placeId, data.eventType === Location.GeofencingEventType.Enter);
});

async function handleTransition(placeId: string, inside: boolean) {
  const place = getSpaceState().places.find((p) => p.id === placeId);
  const reminder = place?.reminder;
  if (!place || !reminder || !isActiveReminder(place)) return;

  const previous = reminder.lastState;
  const now = Date.now();
  // iOS reports the current state of each region when monitoring starts, so only notify on an
  // actual transition: arriving requires that we weren't already inside, leaving requires that we were.
  const shouldFire =
    reminder.trigger === 'arrive' ? inside && previous !== 'inside' : !inside && previous === 'inside';
  const coolingDown = reminder.lastFiredAt != null && now - reminder.lastFiredAt < REFIRE_COOLDOWN_MS;

  if (!shouldFire || coolingDown) {
    const state = inside ? 'inside' : 'outside';
    if (previous !== state) updateReminderState(placeId, { lastState: state });
    return;
  }

  updateReminderState(placeId, {
    lastState: inside ? 'inside' : 'outside',
    lastFiredAt: now,
    // One-off reminders complete once they fire, like Apple's Reminders.
    enabled: reminder.repeat,
  });

  await Notifications.scheduleNotificationAsync({
    content: {
      title: reminder.title || place.name,
      body: `${reminder.trigger === 'arrive' ? 'Arrived at' : 'Left'} ${place.name}`,
      data: { placeId },
      sound: 'default',
    },
    trigger: Platform.OS === 'android' ? { channelId: REMINDER_CHANNEL_ID } : null,
  });
}

/** Signature of the regions we last registered, to avoid needless re-registration. */
let registeredSignature: string | null = null;
let syncQueue: Promise<void> = Promise.resolve();

/** Registers geofences for every active location reminder (or stops monitoring if there are none). */
export function syncGeofences(): Promise<void> {
  syncQueue = syncQueue.then(doSync).catch((error) => {
    console.warn('[geofence] sync failed', error);
  });
  return syncQueue;
}

async function doSync() {
  const active = getSpaceState().places.filter(isActiveReminder);
  const started = await Location.hasStartedGeofencingAsync(GEOFENCE_TASK).catch(() => false);

  if (active.length === 0) {
    if (started) await Location.stopGeofencingAsync(GEOFENCE_TASK);
    registeredSignature = null;
    return;
  }

  const permission = await Location.getBackgroundPermissionsAsync();
  if (!permission.granted) return;

  const position = await Location.getLastKnownPositionAsync().catch(() => null);
  const here = position?.coords ?? null;
  const regions = pickRegions(active, here);

  // Seed unknown states from our current position so creating a reminder where you
  // already are doesn't immediately notify.
  if (here) {
    for (const place of regions) {
      if (place.reminder && !place.reminder.lastState) {
        const inside = distanceMeters(here, place) <= place.reminder.radius;
        updateReminderState(place.id, { lastState: inside ? 'inside' : 'outside' });
      }
    }
  }

  const signature = regions
    .map((p) => `${p.id}:${p.latitude}:${p.longitude}:${p.reminder?.radius}`)
    .join('|');
  if (started && signature === registeredSignature) return;

  await Location.startGeofencingAsync(
    GEOFENCE_TASK,
    regions.map((place) => ({
      identifier: place.id,
      latitude: place.latitude,
      longitude: place.longitude,
      radius: place.reminder?.radius ?? 200,
      notifyOnEnter: true,
      notifyOnExit: true,
    })),
  );
  registeredSignature = signature;
}

/** The OS caps monitored regions, so keep the ones closest to the user. */
function pickRegions(places: Place[], here: Coordinate | null): Place[] {
  if (places.length <= MAX_REGIONS || !here) return places.slice(0, MAX_REGIONS);
  return [...places]
    .sort((a, b) => distanceMeters(here, a) - distanceMeters(here, b))
    .slice(0, MAX_REGIONS);
}

export type ReminderPermissionResult =
  | { ok: true }
  | { ok: false; reason: 'location' | 'background' | 'notifications' };

/**
 * Asks for everything location reminders need: location (Always), and notifications.
 * Returns which step failed so the UI can explain it.
 */
export async function requestReminderPermissions(): Promise<ReminderPermissionResult> {
  const foreground = await Location.requestForegroundPermissionsAsync();
  if (!foreground.granted) return { ok: false, reason: 'location' };

  const background = await Location.requestBackgroundPermissionsAsync();
  if (!background.granted) return { ok: false, reason: 'background' };

  const notifications = await Notifications.requestPermissionsAsync();
  if (!notifications.granted) return { ok: false, reason: 'notifications' };

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync(REMINDER_CHANNEL_ID, {
      name: 'Location reminders',
      // eslint-disable-next-line import/namespace -- exported via `export *`, which the plugin misses
      importance: Notifications.AndroidImportance.HIGH,
    });
  }
  return { ok: true };
}

export const permissionMessages: Record<
  Exclude<ReminderPermissionResult, { ok: true }>['reason'],
  string
> = {
  location: 'Spacetime needs your location to remind you when you arrive at or leave a place.',
  background:
    'To remind you while the app is closed, set Location access to "Always" in Settings.',
  notifications: 'Turn on notifications in Settings so Spacetime can alert you.',
};

export function openSettings() {
  Linking.openSettings().catch(() => {});
}

let started = false;

/** Keeps the registered geofences in sync with the store. Call once at app startup. */
export function startGeofenceSync() {
  if (started) return;
  started = true;
  let lastActiveKey = '';
  const check = () => {
    const key = getSpaceState()
      .places.filter(isActiveReminder)
      .map((p) => `${p.id}:${p.latitude}:${p.longitude}:${p.reminder?.radius}`)
      .join('|');
    if (key !== lastActiveKey) {
      lastActiveKey = key;
      syncGeofences();
    }
  };
  subscribeSpace(check);
  check();
  // Re-pick the nearest regions (and pick up permission changes) whenever the app returns.
  AppState.addEventListener('change', (status) => {
    if (status === 'active') syncGeofences();
  });
}
