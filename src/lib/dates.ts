export const MS_PER_MINUTE = 60_000;
export const MS_PER_DAY = 86_400_000;

export function toDate(value: string | Date | null | undefined): Date | null {
  if (value == null) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

export function addDays(date: Date, days: number): Date {
  // Construct from components so DST transitions don't shift the time of day.
  return new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate() + days,
    date.getHours(),
    date.getMinutes(),
    date.getSeconds(),
    date.getMilliseconds(),
  );
}

export function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

export function addMonths(date: Date, months: number): Date {
  return new Date(date.getFullYear(), date.getMonth() + months, 1);
}

export function startOfWeek(date: Date, weekStartsOn = 0): Date {
  const day = startOfDay(date);
  const diff = (day.getDay() - weekStartsOn + 7) % 7;
  return addDays(day, -diff);
}

export function daysInMonth(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
}

export function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

export function isToday(date: Date): boolean {
  return isSameDay(date, new Date());
}

/** Whole calendar days between two dates (b - a), ignoring time of day. */
export function differenceInDays(a: Date, b: Date): number {
  const utcA = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
  const utcB = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
  return Math.round((utcB - utcA) / MS_PER_DAY);
}

export function differenceInMonths(a: Date, b: Date): number {
  return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
}

function pad(n: number): string {
  return n.toString().padStart(2, '0');
}

/** Local-time key like `2026-10-26`. */
export function dayKey(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function parseDayKey(key: string | undefined | null): Date | null {
  const match = key ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(key) : null;
  if (!match) return null;
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

/** Local-time key like `2026-10`. */
export function monthKey(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}`;
}

export function minutesIntoDay(date: Date): number {
  return date.getHours() * 60 + date.getMinutes();
}

const timeFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
const hourFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric' });
const monthFormat = new Intl.DateTimeFormat(undefined, { month: 'long' });
const shortMonthFormat = new Intl.DateTimeFormat(undefined, { month: 'short' });
const monthYearFormat = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' });
const fullDateFormat = new Intl.DateTimeFormat(undefined, {
  weekday: 'long',
  month: 'long',
  day: 'numeric',
  year: 'numeric',
});
const mediumDateFormat = new Intl.DateTimeFormat(undefined, {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
});
const narrowWeekdayFormat = new Intl.DateTimeFormat(undefined, { weekday: 'narrow' });

export const formatTime = (date: Date) => timeFormat.format(date);
export const formatHour = (date: Date) => hourFormat.format(date);
export const formatMonth = (date: Date) => monthFormat.format(date);
export const formatShortMonth = (date: Date) => shortMonthFormat.format(date);
export const formatMonthYear = (date: Date) => monthYearFormat.format(date);
export const formatFullDate = (date: Date) => fullDateFormat.format(date);
export const formatMediumDate = (date: Date) => mediumDateFormat.format(date);

/** Narrow weekday labels (S M T W T F S) starting from `weekStartsOn`. */
export function weekdayLabels(weekStartsOn = 0): string[] {
  // Jan 4 2026 is a Sunday.
  return Array.from({ length: 7 }, (_, i) =>
    narrowWeekdayFormat.format(new Date(2026, 0, 4 + ((i + weekStartsOn) % 7))),
  );
}

/** "Today", "Tomorrow", "Yesterday", or a medium date. */
export function formatRelativeDay(date: Date): string {
  const diff = differenceInDays(new Date(), date);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Tomorrow';
  if (diff === -1) return 'Yesterday';
  return formatMediumDate(date);
}
