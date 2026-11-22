import {
  addDays,
  dayKey,
  daysInMonth,
  differenceInDays,
  differenceInMonths,
  isSameDay,
  minutesIntoDay,
  monthKey,
  parseDayKey,
  parseMonthKey,
  startOfWeek,
  toDate,
  weekdayLabels,
} from '../dates';

describe('dates', () => {
  it('round-trips day keys in local time', () => {
    const date = new Date(2026, 9, 26);
    expect(dayKey(date)).toBe('2026-10-26');
    expect(parseDayKey('2026-10-26')).toEqual(date);
    expect(parseDayKey('not a date')).toBeNull();
    expect(parseDayKey(undefined)).toBeNull();
  });

  it('round-trips month keys to the first of the month', () => {
    expect(monthKey(new Date(2027, 2, 15))).toBe('2027-03');
    expect(parseMonthKey('2027-03')).toEqual(new Date(2027, 2, 1));
    expect(parseMonthKey('2027-03-15')).toBeNull();
    expect(parseMonthKey(undefined)).toBeNull();
  });

  it('adds days across month and year boundaries', () => {
    expect(dayKey(addDays(new Date(2026, 11, 31), 1))).toBe('2027-01-01');
    expect(dayKey(addDays(new Date(2026, 2, 1), -1))).toBe('2026-02-28');
  });

  it('keeps the time of day when adding days', () => {
    const start = new Date(2026, 2, 7, 9, 30);
    const next = addDays(start, 1);
    expect(next.getHours()).toBe(9);
    expect(next.getMinutes()).toBe(30);
  });

  it('finds the start of the week', () => {
    // Oct 28 2026 is a Wednesday.
    expect(dayKey(startOfWeek(new Date(2026, 9, 28)))).toBe('2026-10-25');
    expect(dayKey(startOfWeek(new Date(2026, 9, 28), 1))).toBe('2026-10-26');
    expect(dayKey(startOfWeek(new Date(2026, 9, 25)))).toBe('2026-10-25');
  });

  it('counts calendar days and months between dates', () => {
    expect(differenceInDays(new Date(2026, 0, 1, 23), new Date(2026, 0, 2, 1))).toBe(1);
    expect(differenceInDays(new Date(2026, 0, 10), new Date(2026, 0, 1))).toBe(-9);
    expect(differenceInMonths(new Date(2026, 10, 30), new Date(2027, 1, 1))).toBe(3);
  });

  it('knows month lengths', () => {
    expect(daysInMonth(new Date(2028, 1, 1))).toBe(29);
    expect(daysInMonth(new Date(2026, 1, 1))).toBe(28);
    expect(daysInMonth(new Date(2026, 9, 1))).toBe(31);
  });

  it('compares days ignoring time', () => {
    expect(isSameDay(new Date(2026, 9, 26, 1), new Date(2026, 9, 26, 23))).toBe(true);
    expect(isSameDay(new Date(2026, 9, 26), new Date(2026, 9, 27))).toBe(false);
  });

  it('converts values to dates', () => {
    expect(toDate(null)).toBeNull();
    expect(toDate('garbage')).toBeNull();
    expect(toDate('2026-10-26T10:00:00.000Z')?.toISOString()).toBe('2026-10-26T10:00:00.000Z');
  });

  it('measures minutes into the day', () => {
    expect(minutesIntoDay(new Date(2026, 0, 1, 13, 45))).toBe(825);
  });

  it('produces seven weekday labels', () => {
    expect(weekdayLabels()).toHaveLength(7);
  });
});
