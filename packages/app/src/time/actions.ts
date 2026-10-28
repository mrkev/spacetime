import { router } from 'expo-router';
import { useCallback } from 'react';
import { ActionSheetIOS, Alert, Platform } from 'react-native';

import { REMINDERS_COLLECTION_ID } from '../space/store';
import { useCalendar, type CalendarEvent, type CalendarReminder } from './CalendarProvider';
import { copyEvent, getCopiedEvent, snapshotEvent, type CopiedEvent } from './editing';

/** Next half hour from now, on the given day. */
function defaultStart(day?: Date): Date {
  const now = new Date();
  const start = day ? new Date(day) : new Date(now);
  start.setHours(now.getHours(), now.getMinutes() < 30 ? 30 : 60, 0, 0);
  return start;
}

type Option = { label: string; destructive?: boolean; run: () => void };

/** An action sheet on iOS, an alert elsewhere. */
function showOptions(title: string | undefined, options: Option[], onCancel?: () => void) {
  if (Platform.OS === 'ios') {
    const destructive = options.findIndex((o) => o.destructive);
    ActionSheetIOS.showActionSheetWithOptions(
      {
        title,
        options: [...options.map((o) => o.label), 'Cancel'],
        cancelButtonIndex: options.length,
        destructiveButtonIndex: destructive === -1 ? undefined : destructive,
      },
      (index) => (options[index]?.run ?? onCancel)?.(),
    );
  } else {
    Alert.alert(
      title ?? '',
      undefined,
      [
        ...options.map((o) => ({
          text: o.label,
          onPress: o.run,
          style: o.destructive ? ('destructive' as const) : undefined,
        })),
        { text: 'Cancel', style: 'cancel' as const, onPress: onCancel },
      ],
      { cancelable: true, onDismiss: onCancel },
    );
  }
}

type Span = 'this' | 'future';

/** Like Calendar, ask whether a change to a repeating event applies to later ones too. */
function chooseSpan(event: CalendarEvent, verb: 'Save' | 'Delete'): Promise<Span | null> {
  if (!event.recurring) return Promise.resolve('this');
  return new Promise((resolve) => {
    const pick = (span: Span) => () => resolve(span);
    showOptions(
      verb === 'Save'
        ? 'This is a repeating event.'
        : 'Are you sure you want to delete this event? This is a repeating event.',
      [
        { label: `${verb} This Event Only`, destructive: verb === 'Delete', run: pick('this') },
        { label: `${verb} All Future Events`, destructive: verb === 'Delete', run: pick('future') },
      ],
      () => resolve(null),
    );
  });
}

function occurrence(event: CalendarEvent, span: Span) {
  if (span === 'this') return event.source;
  // Rebinds the event to the "this and future" span, so update/delete apply to the rest of the series.
  return event.source.getOccurrenceSync({
    instanceStartDate: event.start.toISOString(),
    futureEvents: true,
  });
}

function reportFailure(action: string, error: unknown) {
  console.warn(`[calendar] failed to ${action}`, error);
  Alert.alert(`Couldn’t ${action[0].toUpperCase()}${action.slice(1)}`, String(error));
}

export function useTimeActions() {
  const { status, requestAccess, defaultEventCalendar, writableCalendar, refresh } = useCalendar();

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
          // Events from listEvents are bare native objects that skip expo-calendar's JS wrapper,
          // so dates must already be strings (the native side rejects Date objects).
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

  const openReminder = useCallback((reminder: CalendarReminder) => {
    router.push({ pathname: '/reminder/[id]', params: { id: reminder.key } });
  }, []);

  const createLocationReminder = useCallback(() => {
    router.push({ pathname: '/place/new', params: { collectionId: REMINDERS_COLLECTION_ID } });
  }, []);

  /** The "+" menu: event, reminder, or location reminder. */
  const showAddMenu = useCallback(
    (day?: Date) => {
      const options: Option[] = [
        { label: 'New Event', run: () => createEvent(day ? defaultStart(day) : undefined) },
      ];
      if (Platform.OS === 'ios') {
        options.push({ label: 'New Reminder', run: () => createReminder(day) });
      }
      options.push({ label: 'New Location Reminder', run: createLocationReminder });
      showOptions(Platform.OS === 'ios' ? undefined : 'Add', options);
    },
    [createEvent, createReminder, createLocationReminder],
  );

  /** Saves new times for a dragged event. Resolves false if it wasn't saved. */
  const rescheduleEvent = useCallback(
    async (event: CalendarEvent, start: Date, end: Date) => {
      const span = await chooseSpan(event, 'Save');
      if (!span) return false;
      try {
        // ISO strings for the same reason as in openEvent.
        await occurrence(event, span).update({
          startDate: start.toISOString(),
          endDate: end.toISOString(),
        });
        return true;
      } catch (error) {
        reportFailure('move event', error);
        return false;
      } finally {
        refresh();
      }
    },
    [refresh],
  );

  const deleteEvent = useCallback(
    async (event: CalendarEvent) => {
      const span = await chooseSpan(event, 'Delete');
      if (!span) return false;
      try {
        await occurrence(event, span).delete();
        return true;
      } catch (error) {
        reportFailure('delete event', error);
        return false;
      } finally {
        refresh();
      }
    },
    [refresh],
  );

  const insertCopy = useCallback(
    async (copied: CopiedEvent, start: Date) => {
      const calendar = writableCalendar(copied.calendarId) ?? defaultEventCalendar();
      if (!calendar) {
        Alert.alert('No Calendar', 'Add a calendar account in Settings to create events.');
        return;
      }
      try {
        await calendar.createEvent({
          title: copied.title,
          startDate: start.toISOString(),
          endDate: new Date(start.getTime() + copied.durationMinutes * 60_000).toISOString(),
          allDay: false,
          location: copied.location,
          notes: copied.notes,
          url: copied.url,
          alarms: copied.alarms,
          availability: copied.availability,
        });
      } catch (error) {
        reportFailure('paste event', error);
      } finally {
        refresh();
      }
    },
    [writableCalendar, defaultEventCalendar, refresh],
  );

  const pasteEvent = useCallback(
    async (start: Date) => {
      const copied = getCopiedEvent();
      if (copied) await insertCopy(copied, start);
    },
    [insertCopy],
  );

  // Calendar puts the duplicate at the same time, alongside the original.
  const duplicateEvent = useCallback(
    (event: CalendarEvent) => insertCopy(snapshotEvent(event), event.start),
    [insertCopy],
  );

  const cutEvent = useCallback(
    async (event: CalendarEvent) => {
      copyEvent(event);
      await deleteEvent(event);
    },
    [deleteEvent],
  );

  return {
    createEvent,
    openEvent,
    createReminder,
    openReminder,
    createLocationReminder,
    showAddMenu,
    rescheduleEvent,
    deleteEvent,
    duplicateEvent,
    cutEvent,
    copyEvent,
    pasteEvent,
  };
}
