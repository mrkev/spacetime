import { useEffect } from 'react';

import { useCalendar } from '../time/CalendarProvider';
import { createLocationReminder } from './locationReminders';
import { REMINDERS_COLLECTION_ID, deletePlace, useSpaceState } from './store';

// Once per launch, so a reminder that can't be moved isn't retried on every render.
let attempted = false;

/**
 * Location reminders used to be places in our own store, notified by our own geofencing. Moves any
 * left from then into Apple Reminders, once there's access to it.
 */
export function LegacyReminderMigration() {
  const { places } = useSpaceState();
  const { remindersStatus, requestAccess, defaultReminderList, refresh } = useCalendar();
  const legacy = places.filter((p) => p.collectionId === REMINDERS_COLLECTION_ID);
  const list = remindersStatus === 'granted' ? defaultReminderList() : null;

  useEffect(() => {
    if (legacy.length > 0 && remindersStatus === 'undetermined') requestAccess();
  }, [legacy.length, remindersStatus, requestAccess]);

  useEffect(() => {
    if (legacy.length === 0 || !list || attempted) return;
    attempted = true;
    (async () => {
      for (const place of legacy) {
        try {
          await createLocationReminder(
            list,
            {
              title: place.reminder?.title || place.name,
              placeName: place.name,
              address: place.address,
              notes: place.notes,
              latitude: place.latitude,
              longitude: place.longitude,
              trigger: place.reminder?.trigger ?? 'arrive',
              radius: place.reminder?.radius ?? 250,
            },
            { completed: place.reminder ? !place.reminder.enabled : false },
          );
          deletePlace(place.id);
        } catch (error) {
          console.warn(`[space] couldn't move reminder “${place.name}” to Reminders`, error);
        }
      }
      refresh();
    })();
  }, [legacy, list, refresh]);

  return null;
}
