import * as Calendar from 'expo-calendar';
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { AppState, Platform } from 'react-native';

import {
  addDays,
  addMonths,
  dayKey,
  monthKey,
  startOfDay,
  startOfMonth,
  toDate,
} from '../lib/dates';
import { reconcileReminderMeta } from './reminderMeta';

export type AccessStatus = 'loading' | 'undetermined' | 'granted' | 'denied';

export type CalendarEvent = {
  /** Unique per occurrence, so recurring events get distinct keys. */
  key: string;
  title: string;
  start: Date;
  end: Date;
  allDay: boolean;
  color: string;
  calendarTitle: string;
  location: string | null;
  /** False for read-only calendars (subscriptions, birthdays, invitations we can't change). */
  editable: boolean;
  recurring: boolean;
  source: Calendar.ExpoCalendarEvent;
};

export type CalendarReminder = {
  key: string;
  /** The server's ID, shared across devices (see `ReminderRef`). */
  externalId?: string;
  title: string;
  due: Date | null;
  /** True when the reminder has a date but no time. */
  allDay: boolean;
  completed: boolean;
  color: string;
  listTitle: string;
  notes?: string;
  source: Calendar.ExpoCalendarReminder;
};

export type DayItems = { events: CalendarEvent[]; reminders: CalendarReminder[] };

type MonthData = Map<string, DayItems>;

type CalendarContextValue = {
  status: AccessStatus;
  remindersStatus: AccessStatus;
  requestAccess: () => Promise<void>;
  /** Items for a given day, or undefined if that month hasn't loaded yet. */
  getDay: (date: Date) => DayItems | undefined;
  /** Kicks off loading the months around `date` (no-op if cached). */
  ensureMonths: (date: Date, radius?: number) => void;
  /** A loaded reminder (from an open list or a loaded month) by ID. */
  getReminder: (id: string) => CalendarReminder | undefined;
  /** Incomplete reminders across all lists (iOS only). */
  openReminders: CalendarReminder[];
  reminderLists: Calendar.ExpoCalendar[];
  /** The list new reminders go into by default. */
  defaultReminderList: () => Calendar.ExpoCalendar | null;
  /** The calendar new events go into by default. */
  defaultEventCalendar: () => Calendar.ExpoCalendar | null;
  /** A writable event calendar by ID. */
  writableCalendar: (id: string) => Calendar.ExpoCalendar | null;
  toggleReminder: (reminder: CalendarReminder) => Promise<void>;
  /** Drops all cached data and reloads what's on screen. */
  refresh: () => void;
  /** Increments whenever cached data changes, so consumers can re-render. */
  version: number;
};

const CalendarContext = createContext<CalendarContextValue | null>(null);

/** Unique per occurrence, so recurring events get distinct keys. */
export function eventKey(id: string, start: Date): string {
  return `${id}:${start.getTime()}`;
}

const EMPTY_DAY: DayItems = { events: [], reminders: [] };
const supportsReminders = Platform.OS === 'ios';

function toStatus(response: Calendar.PermissionResponse): AccessStatus {
  if (response.granted) return 'granted';
  return response.canAskAgain ? 'undetermined' : 'denied';
}

type PermissionState = { status: AccessStatus; remindersStatus: AccessStatus };

async function fetchPermissions(): Promise<PermissionState> {
  try {
    return {
      status: toStatus(await Calendar.getCalendarPermissions()),
      remindersStatus: supportsReminders
        ? toStatus(await Calendar.getRemindersPermissions())
        : 'denied',
    };
  } catch (error) {
    console.warn('[calendar] permission check failed', error);
    return { status: 'denied', remindersStatus: 'denied' };
  }
}

async function requestPermissions(): Promise<PermissionState> {
  const status = toStatus(await Calendar.requestCalendarPermissions());
  const remindersStatus = supportsReminders
    ? toStatus(await Calendar.requestRemindersPermissions())
    : 'denied';
  return { status, remindersStatus };
}

async function fetchCalendars(status: AccessStatus, remindersStatus: AccessStatus) {
  const lists = { events: [] as Calendar.ExpoCalendar[], reminders: [] as Calendar.ExpoCalendar[] };
  try {
    if (status === 'granted') {
      const calendars = await Calendar.getCalendars(
        Platform.OS === 'ios' ? Calendar.EntityTypes.EVENT : undefined,
      );
      lists.events = calendars.filter((c) => c.isVisible !== false);
    }
    if (remindersStatus === 'granted') {
      lists.reminders = await Calendar.getCalendars(Calendar.EntityTypes.REMINDER);
    }
  } catch (error) {
    console.warn('[calendar] failed to list calendars', error);
  }
  return lists;
}

async function fetchOpenReminders(lists: Calendar.ExpoCalendar[]) {
  if (!supportsReminders || lists.length === 0) return [];
  const results = await Promise.all(
    lists.map((list) =>
      list.listReminders(null, null, Calendar.ReminderStatus.INCOMPLETE).catch(() => []),
    ),
  );
  return results.flat();
}

export function CalendarProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AccessStatus>('loading');
  const [remindersStatus, setRemindersStatus] = useState<AccessStatus>(
    supportsReminders ? 'loading' : 'denied',
  );
  const [version, setVersion] = useState(0);
  const [openReminders, setOpenReminders] = useState<CalendarReminder[]>([]);
  const [eventCalendars, setEventCalendars] = useState<Calendar.ExpoCalendar[]>([]);
  const [reminderLists, setReminderLists] = useState<Calendar.ExpoCalendar[]>([]);

  const months = useRef(new Map<string, MonthData>());
  const pending = useRef(new Map<string, Promise<void>>());
  // Bumped on refresh so in-flight loads from before the refresh are discarded.
  const generation = useRef(0);
  // Months we've been asked for, so a refresh can reload exactly what's on screen.
  const requested = useRef(new Set<string>());

  const bump = useCallback(() => setVersion((v) => v + 1), []);
  // Bumped to re-read the calendar lists (e.g. when returning from the Calendar app).
  const [calendarsNonce, setCalendarsNonce] = useState(0);

  const applyPermissions = useCallback((result: PermissionState) => {
    setStatus(result.status);
    setRemindersStatus(result.remindersStatus);
  }, []);

  useEffect(() => {
    fetchPermissions().then(applyPermissions);
  }, [applyPermissions]);

  const requestAccess = useCallback(async () => {
    applyPermissions(await requestPermissions());
  }, [applyPermissions]);

  useEffect(() => {
    let cancelled = false;
    fetchCalendars(status, remindersStatus).then((lists) => {
      if (cancelled) return;
      setEventCalendars(lists.events);
      setReminderLists(lists.reminders);
    });
    return () => {
      cancelled = true;
    };
  }, [status, remindersStatus, calendarsNonce]);

  const calendarsById = useMemo(() => {
    const map = new Map<string, Calendar.ExpoCalendar>();
    for (const c of [...eventCalendars, ...reminderLists]) map.set(c.id, c);
    return map;
  }, [eventCalendars, reminderLists]);

  const toReminder = useCallback(
    (r: Calendar.ExpoCalendarReminder): CalendarReminder | null => {
      if (!r.id) return null;
      const list = r.calendarId ? calendarsById.get(r.calendarId) : undefined;
      const due = toDate(r.dueDate ?? r.startDate);
      return {
        key: r.id,
        externalId: r.externalId ?? undefined,
        title: r.title || 'Untitled',
        due,
        allDay: !!r.allDay,
        completed: !!r.completed,
        color: list?.color ?? '#FF9500',
        listTitle: list?.title ?? 'Reminders',
        notes: r.notes,
        source: r,
      };
    },
    [calendarsById],
  );

  const loadMonth = useCallback(
    (key: string, month: Date): Promise<void> => {
      const existing = pending.current.get(key);
      if (existing) return existing;
      const gen = generation.current;
      const start = startOfMonth(month);
      const end = addMonths(month, 1);

      const task = (async () => {
        const data: MonthData = new Map();
        const bucket = (date: Date) => {
          const k = dayKey(date);
          let day = data.get(k);
          if (!day) data.set(k, (day = { events: [], reminders: [] }));
          return day;
        };

        if (eventCalendars.length > 0) {
          const events = await Calendar.listEvents(eventCalendars, start, end);
          for (const e of events) {
            const eventStart = toDate(e.startDate);
            const eventEnd = toDate(e.endDate) ?? eventStart;
            if (!eventStart || !eventEnd) continue;
            const calendar = calendarsById.get(e.calendarId);
            const event: CalendarEvent = {
              key: eventKey(e.id, eventStart),
              title: e.title || 'New Event',
              start: eventStart,
              end: eventEnd,
              allDay: e.allDay,
              color: calendar?.color ?? '#007AFF',
              calendarTitle: calendar?.title ?? '',
              location: e.location,
              editable: !!calendar?.allowsModifications,
              recurring: e.recurrenceRule != null,
              source: e,
            };
            // Add multi-day events to every day they touch (within this month).
            const lastMoment = new Date(Math.max(eventStart.getTime(), eventEnd.getTime() - 1));
            for (
              let day = startOfDay(eventStart);
              day <= lastMoment && day < end;
              day = addDays(day, 1)
            ) {
              if (day >= start) bucket(day).events.push(event);
            }
          }
        }

        if (supportsReminders && reminderLists.length > 0) {
          const results = await Promise.all(
            reminderLists.map((list) => list.listReminders(start, end).catch(() => [])),
          );
          for (const r of results.flat()) {
            const reminder = toReminder(r);
            if (reminder?.due && reminder.due >= start && reminder.due < end) {
              bucket(reminder.due).reminders.push(reminder);
            }
          }
        }

        for (const day of data.values()) {
          day.events.sort((a, b) => a.start.getTime() - b.start.getTime());
          day.reminders.sort((a, b) => (a.due?.getTime() ?? 0) - (b.due?.getTime() ?? 0));
        }

        if (gen === generation.current) {
          months.current.set(key, data);
          bump();
        }
      })()
        .catch((error) => console.warn(`[calendar] failed to load ${key}`, error))
        .finally(() => {
          if (pending.current.get(key) === task) pending.current.delete(key);
        });

      pending.current.set(key, task);
      return task;
    },
    [eventCalendars, reminderLists, calendarsById, toReminder, bump],
  );

  const ensureMonths = useCallback(
    (date: Date, radius = 1) => {
      if (status !== 'granted') return;
      for (let offset = -radius; offset <= radius; offset++) {
        const month = addMonths(date, offset);
        const key = monthKey(month);
        requested.current.add(key);
        if (!months.current.has(key)) loadMonth(key, month);
      }
    },
    [status, loadMonth],
  );

  const refresh = useCallback(() => {
    // Keep showing cached data while reloading; each month swaps in when it arrives.
    generation.current++;
    pending.current.clear();
    for (const key of requested.current) {
      const [year, month] = key.split('-').map(Number);
      loadMonth(key, new Date(year, month - 1, 1));
    }
    fetchOpenReminders(reminderLists)
      .then((reminders) =>
        setOpenReminders(
          reminders
            .map(toReminder)
            .filter((r): r is CalendarReminder => r != null)
            .sort((a, b) => (a.due?.getTime() ?? Infinity) - (b.due?.getTime() ?? Infinity)),
        ),
      )
      .catch((error) => console.warn('[calendar] reminders failed', error));
  }, [loadMonth, reminderLists, toReminder]);

  // Reload whenever the calendars change. Events may also have changed in the Calendar app while
  // we were in the background, so re-read everything when the app becomes active.
  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (next) => {
      if (next !== 'active') return;
      fetchPermissions().then(applyPermissions);
      // New calendar objects trigger a full refresh.
      setCalendarsNonce((n) => n + 1);
    });
    return () => subscription.remove();
  }, [applyPermissions]);

  const getDay = useCallback(
    (date: Date) => {
      const month = months.current.get(monthKey(date));
      if (!month) return undefined;
      return month.get(dayKey(date)) ?? EMPTY_DAY;
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [version],
  );

  const getReminder = useCallback(
    (id: string) => {
      for (const month of months.current.values()) {
        for (const day of month.values()) {
          const found = day.reminders.find((r) => r.key === id);
          if (found) return found;
        }
      }
      return openReminders.find((r) => r.key === id);
    },
    // Months live in a ref; `version` changes whenever they do.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [openReminders, version],
  );

  const defaultEventCalendar = useCallback(() => {
    if (Platform.OS === 'ios') {
      try {
        return Calendar.getDefaultCalendarSync();
      } catch {
        // Fall through to picking a writable calendar.
      }
    }
    return (
      eventCalendars.find((c) => c.allowsModifications && c.isPrimary) ??
      eventCalendars.find((c) => c.allowsModifications) ??
      null
    );
  }, [eventCalendars]);

  const defaultReminderList = useCallback(() => {
    const writable = reminderLists.filter((l) => l.allowsModifications);
    return writable.find((l) => l.isDefaultForReminders) ?? writable[0] ?? null;
  }, [reminderLists]);

  // Keep what we store about reminders matched up with them, and forget deleted ones.
  useEffect(() => {
    if (remindersStatus !== 'granted') return;
    reconcileReminderMeta(
      openReminders.map((r) => ({ id: r.key, externalId: r.externalId })),
    ).catch((error) => console.warn('[calendar] reminder metadata failed', error));
  }, [openReminders, remindersStatus]);

  const writableCalendar = useCallback(
    (id: string) => {
      const calendar = calendarsById.get(id);
      return calendar?.allowsModifications ? calendar : null;
    },
    [calendarsById],
  );

  const toggleReminder = useCallback(
    async (reminder: CalendarReminder) => {
      // EventKit sets or clears the completion date along with the flag.
      await reminder.source.update({ completed: !reminder.completed });
      refresh();
    },
    [refresh],
  );

  const value = useMemo<CalendarContextValue>(
    () => ({
      status,
      remindersStatus,
      requestAccess,
      getDay,
      ensureMonths,
      getReminder,
      openReminders,
      reminderLists,
      defaultReminderList,
      defaultEventCalendar,
      writableCalendar,
      toggleReminder,
      refresh,
      version,
    }),
    [
      status,
      remindersStatus,
      requestAccess,
      getDay,
      ensureMonths,
      getReminder,
      openReminders,
      reminderLists,
      defaultReminderList,
      defaultEventCalendar,
      writableCalendar,
      toggleReminder,
      refresh,
      version,
    ],
  );

  return <CalendarContext.Provider value={value}>{children}</CalendarContext.Provider>;
}

export function useCalendar(): CalendarContextValue {
  const value = useContext(CalendarContext);
  if (!value) throw new Error('useCalendar must be used inside <CalendarProvider>');
  return value;
}
