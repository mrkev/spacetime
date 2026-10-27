import { router } from 'expo-router';
import { useCallback } from 'react';
import { ActionSheetIOS, Alert, Platform } from 'react-native';

import { REMINDERS_COLLECTION_ID } from '../space/store';
import { useCalendar, type CalendarEvent } from './CalendarProvider';

/** Next half hour from now, on the given day. */
function defaultStart(day?: Date): Date {
  const now = new Date();
  const start = day ? new Date(day) : new Date(now);
  start.setHours(now.getHours(), now.getMinutes() < 30 ? 30 : 60, 0, 0);
  return start;
}

export function useTimeActions() {
  const { status, requestAccess, defaultEventCalendar, refresh } = useCalendar();

  const createEvent = useCallback(
    async (start?: Date) => {
      if (status !== 'granted') {
        await requestAccess();
        return;
      }
      const calendar = defaultEventCalendar();
      if (!calendar) {
        Alert.alert('No Calendar', 'Add a calendar account in Settings to create events.');
        return;
      }
      const startDate = start ?? defaultStart();
      const endDate = new Date(startDate.getTime() + 60 * 60_000);
      // Use the system editor so events get every field Calendar supports.
      const result = await calendar.addEventWithForm({ startDate, endDate });
      if (result.action === 'saved' || result.action === 'done') refresh();
    },
    [status, requestAccess, defaultEventCalendar, refresh],
  );

  const openEvent = useCallback(
    async (event: CalendarEvent) => {
      try {
        const result = await event.source.openInCalendar({
          // Unlike its other methods, expo-calendar doesn't serialize Dates here, and the native
          // side only accepts a string or number.
          instanceStartDate: event.start.toISOString(),
          allowsEditing: true,
          allowsCalendarPreview: true,
        });
        if (result.action !== 'canceled') refresh();
      } catch (error) {
        console.warn('[calendar] failed to open event', error);
        Alert.alert('Couldn’t Open Event', 'It may have been deleted. Try again in a moment.');
        refresh();
      }
    },
    [refresh],
  );

  const createReminder = useCallback((date?: Date) => {
    router.push({
      pathname: '/reminder/new',
      params: date ? { date: date.toISOString() } : {},
    });
  }, []);

  const createLocationReminder = useCallback(() => {
    router.push({ pathname: '/place/new', params: { collectionId: REMINDERS_COLLECTION_ID } });
  }, []);

  /** The "+" menu: event, reminder, or location reminder. */
  const showAddMenu = useCallback(
    (day?: Date) => {
      const options: { label: string; run: () => void }[] = [
        { label: 'New Event', run: () => createEvent(day ? defaultStart(day) : undefined) },
      ];
      if (Platform.OS === 'ios') {
        options.push({ label: 'New Reminder', run: () => createReminder(day) });
      }
      options.push({ label: 'New Location Reminder', run: createLocationReminder });

      if (Platform.OS === 'ios') {
        ActionSheetIOS.showActionSheetWithOptions(
          { options: [...options.map((o) => o.label), 'Cancel'], cancelButtonIndex: options.length },
          (index) => options[index]?.run(),
        );
      } else {
        Alert.alert('Add', undefined, [
          ...options.map((o) => ({ text: o.label, onPress: o.run })),
          { text: 'Cancel', style: 'cancel' as const },
        ]);
      }
    },
    [createEvent, createReminder, createLocationReminder],
  );

  return { createEvent, openEvent, createReminder, createLocationReminder, showAddMenu };
}
