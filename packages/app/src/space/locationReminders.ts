import type * as Calendar from 'expo-calendar';
import { useMemo } from 'react';

import type { Coordinate } from '../lib/geo';
import { useCalendar, type CalendarReminder } from '../time/CalendarProvider';
import { getReminderMeta, setReminderMeta, useReminderMetaVersion } from '../time/reminderMeta';

export type ReminderTrigger = 'arrive' | 'leave';

/** Reminders uses its own default when a location alarm's radius is 0. */
export const DEFAULT_RADIUS = 100;

/**
 * A reminder in Apple Reminders with a location alarm, which Reminders fires when you arrive at or
 * leave the place. These are the places in the Reminders collection.
 */
export type LocationReminder = Coordinate & {
  /** The reminder's ID. */
  id: string;
  title: string;
  placeName: string;
  address?: string;
  notes?: string;
  trigger: ReminderTrigger;
  /** In meters. */
  radius: number;
  completed: boolean;
  reminder: CalendarReminder;
};

/** What the place form saves as a location reminder. */
export type LocationReminderInput = Coordinate & {
  title: string;
  placeName: string;
  address?: string;
  notes?: string;
  trigger: ReminderTrigger;
  radius: number;
};

type LocatedAlarm = Calendar.Alarm & {
  structuredLocation: Calendar.AlarmLocation & { coords: Coordinate };
};

function isLocated(alarm: Calendar.Alarm): alarm is LocatedAlarm {
  const coords = alarm.structuredLocation?.coords;
  return coords?.latitude != null && coords.longitude != null;
}

export function toLocationReminder(reminder: CalendarReminder): LocationReminder | null {
  const alarm = reminder.source.alarms?.find(isLocated);
  if (!alarm) return null;
  const { title, proximity, radius, coords } = alarm.structuredLocation;
  const meta = getReminderMeta({ id: reminder.key, externalId: reminder.externalId });
  return {
    id: reminder.key,
    title: reminder.title,
    placeName: title || 'Location',
    address: meta.address,
    notes: reminder.notes,
    latitude: coords.latitude,
    longitude: coords.longitude,
    trigger: proximity === 'leave' ? 'leave' : 'arrive',
    radius: radius || DEFAULT_RADIUS,
    completed: reminder.completed,
    reminder,
  };
}

/** Every incomplete reminder with a location, from any list (including ones made in Reminders). */
export function useLocationReminders(): LocationReminder[] {
  const { openReminders } = useCalendar();
  const metaVersion = useReminderMetaVersion();
  return useMemo(
    () => openReminders.map(toLocationReminder).filter((r): r is LocationReminder => r != null),
    // Addresses come from the metadata store.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [openReminders, metaVersion],
  );
}

function toAlarm(
  input: Pick<LocationReminderInput, 'placeName' | 'trigger' | 'radius' | 'latitude' | 'longitude'>,
): Calendar.Alarm {
  return {
    structuredLocation: {
      title: input.placeName,
      proximity: input.trigger === 'leave' ? 'leave' : 'enter',
      radius: input.radius,
      coords: { latitude: input.latitude, longitude: input.longitude },
    },
  };
}

export async function createLocationReminder(
  list: Calendar.ExpoCalendar,
  input: LocationReminderInput,
  { completed = false } = {},
): Promise<void> {
  const created = await list.createReminder({
    title: input.title,
    notes: input.notes,
    alarms: [toAlarm(input)],
    completed,
  });
  if (created.id) {
    setReminderMeta({ id: created.id, externalId: created.externalId }, { address: input.address });
  }
}

export async function updateLocationReminder(
  existing: LocationReminder,
  input: LocationReminderInput,
): Promise<void> {
  const { source } = existing.reminder;
  // Keep any other alarms (e.g. a time set in Reminders); only the location one is replaced.
  const alarms = [...(source.alarms ?? []).filter((a) => !isLocated(a)), toAlarm(input)];
  // Reminders from a list are bare native objects, so cleared fields are named separately (see
  // ReminderEditor).
  const update = source.update as (
    details: Record<string, unknown>,
    nullableFields: string[],
  ) => Promise<void>;
  await update.call(
    source,
    { title: input.title, alarms, ...(input.notes ? { notes: input.notes } : { notes: null }) },
    input.notes ? [] : ['notes'],
  );
  const ref = { id: existing.id, externalId: existing.reminder.externalId };
  setReminderMeta(ref, { ...getReminderMeta(ref), address: input.address });
}

/**
 * Gives a reminder a location: a place it reminds you at, replacing any it had. It keeps its trigger
 * and radius if it had a location, or else gets `defaults`.
 */
export async function moveReminderTo(
  reminder: CalendarReminder,
  place: Coordinate & { name: string; address?: string },
  defaults: Pick<LocationReminderInput, 'trigger' | 'radius'>,
): Promise<void> {
  const { source } = reminder;
  const located = toLocationReminder(reminder);
  const alarm = toAlarm({
    placeName: place.name,
    latitude: place.latitude,
    longitude: place.longitude,
    trigger: located?.trigger ?? defaults.trigger,
    radius: located?.radius ?? defaults.radius,
  });
  // Bare native objects, as in updateLocationReminder.
  const update = source.update as (details: Record<string, unknown>) => Promise<void>;
  await update.call(source, {
    alarms: [...(source.alarms ?? []).filter((a) => !isLocated(a)), alarm],
  });
  const ref = { id: reminder.key, externalId: reminder.externalId };
  setReminderMeta(ref, { ...getReminderMeta(ref), address: place.address });
}

export function describeTrigger(reminder: Pick<LocationReminder, 'trigger' | 'radius'>): string {
  const when = reminder.trigger === 'arrive' ? 'Arriving' : 'Leaving';
  const radius = reminder.radius >= 1000 ? `${reminder.radius / 1000} km` : `${reminder.radius} m`;
  return `${when} · ${radius}`;
}
