import type { CalendarEvent } from '../CalendarProvider';
import { applyRange, canDrag, dragRange, snapMinutes } from '../editing';

const nineToTen = { startMinute: 9 * 60, endMinute: 10 * 60 };

function makeEvent(start: Date, end: Date, overrides: Partial<CalendarEvent> = {}): CalendarEvent {
  return {
    key: 'e',
    title: 'Medicina',
    start,
    end,
    allDay: false,
    color: '#FF3B30',
    calendarTitle: 'Home',
    location: null,
    place: null,
    editable: true,
    recurring: false,
    source: {} as CalendarEvent['source'],
    ...overrides,
  };
}

describe('snapMinutes', () => {
  it('rounds to the nearest quarter hour', () => {
    expect(snapMinutes(7)).toBe(0);
    expect(snapMinutes(8)).toBe(15);
    expect(snapMinutes(-8)).toBe(-15);
    expect(snapMinutes(52)).toBe(45);
  });
});

describe('dragRange', () => {
  it('moves an event and keeps its duration', () => {
    expect(dragRange(nineToTen, 'move', 50)).toEqual({
      startMinute: 9 * 60 + 45,
      endMinute: 10 * 60 + 45,
    });
  });

  it('keeps moved events within the day', () => {
    expect(dragRange(nineToTen, 'move', -24 * 60)).toEqual({ startMinute: 0, endMinute: 60 });
    expect(dragRange(nineToTen, 'move', 24 * 60)).toEqual({
      startMinute: 23 * 60,
      endMinute: 24 * 60,
    });
  });

  it('resizes either edge without inverting the event', () => {
    expect(dragRange(nineToTen, 'start', -30)).toEqual({
      startMinute: 8 * 60 + 30,
      endMinute: 10 * 60,
    });
    expect(dragRange(nineToTen, 'start', 120)).toEqual({
      startMinute: 9 * 60 + 45,
      endMinute: 10 * 60,
    });
    expect(dragRange(nineToTen, 'end', 15)).toEqual({
      startMinute: 9 * 60,
      endMinute: 10 * 60 + 15,
    });
    expect(dragRange(nineToTen, 'end', -120)).toEqual({
      startMinute: 9 * 60,
      endMinute: 9 * 60 + 15,
    });
  });

  it('snaps off-grid events onto the grid once they move', () => {
    const offGrid = { startMinute: 9 * 60 + 10, endMinute: 9 * 60 + 40 };
    expect(dragRange(offGrid, 'move', 4)).toBe(offGrid);
    expect(dragRange(offGrid, 'move', 15)).toEqual({
      startMinute: 9 * 60 + 30,
      endMinute: 10 * 60,
    });
  });
});

describe('canDrag', () => {
  const day = new Date(2026, 9, 28);
  const at = (hour: number, minute = 0, date = 28) => new Date(2026, 9, date, hour, minute);

  it('allows timed, editable events within the day', () => {
    expect(canDrag(makeEvent(at(9), at(10)), day)).toBe(true);
    expect(canDrag(makeEvent(at(23), at(0, 0, 29)), day)).toBe(true);
  });

  it('rejects read-only, all-day, and multi-day events', () => {
    expect(canDrag(makeEvent(at(9), at(10), { editable: false }), day)).toBe(false);
    expect(canDrag(makeEvent(at(0), at(0, 0, 29), { allDay: true }), day)).toBe(false);
    expect(canDrag(makeEvent(at(22, 0, 27), at(1)), day)).toBe(false);
  });
});

describe('applyRange', () => {
  it('shifts the dates by how far each edge moved', () => {
    const event = makeEvent(new Date(2026, 9, 28, 9), new Date(2026, 9, 28, 10));
    const { start, end } = applyRange(event, nineToTen, {
      startMinute: 9 * 60 + 30,
      endMinute: 11 * 60,
    });
    expect(start).toEqual(new Date(2026, 9, 28, 9, 30));
    expect(end).toEqual(new Date(2026, 9, 28, 11));
  });
});
