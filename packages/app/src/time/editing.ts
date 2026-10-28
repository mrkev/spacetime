import type { CalendarEvent } from './CalendarProvider';

/** Drags snap to the quarter hour, like Calendar. */
export const SNAP_MINUTES = 15;
const DAY_MINUTES = 24 * 60;

export type MinuteRange = { startMinute: number; endMinute: number };
export type DragMode = 'move' | 'start' | 'end';

export function snapMinutes(minutes: number): number {
  return Math.round(minutes / SNAP_MINUTES) * SNAP_MINUTES;
}

/**
 * Applies a drag of `deltaMinutes` to a range. Moving keeps the duration; resizing keeps at least
 * one snap interval. Everything stays within the day.
 */
export function dragRange(range: MinuteRange, mode: DragMode, deltaMinutes: number): MinuteRange {
  const delta = snapMinutes(deltaMinutes);
  // Holding still leaves an off-grid event where it is instead of nudging it onto the grid.
  if (delta === 0) return range;
  const { startMinute, endMinute } = range;
  switch (mode) {
    case 'move': {
      const duration = endMinute - startMinute;
      const start = clamp(snapMinutes(startMinute + delta), 0, DAY_MINUTES - duration);
      return { startMinute: start, endMinute: start + duration };
    }
    case 'start':
      return {
        startMinute: clamp(snapMinutes(startMinute + delta), 0, endMinute - SNAP_MINUTES),
        endMinute,
      };
    case 'end':
      return {
        startMinute,
        endMinute: clamp(snapMinutes(endMinute + delta), startMinute + SNAP_MINUTES, DAY_MINUTES),
      };
  }
}

/** Only timed events that fit within one day can be dragged around the timeline. */
export function canDrag(event: CalendarEvent, dayStart: Date): boolean {
  if (!event.editable || event.allDay) return false;
  const dayEnd = new Date(dayStart);
  dayEnd.setDate(dayEnd.getDate() + 1);
  return event.start >= dayStart && event.end <= dayEnd;
}

/** Shifts an event's dates by how far its range moved on the timeline. */
export function applyRange(event: CalendarEvent, from: MinuteRange, to: MinuteRange) {
  return {
    start: new Date(event.start.getTime() + (to.startMinute - from.startMinute) * 60_000),
    end: new Date(event.end.getTime() + (to.endMinute - from.endMinute) * 60_000),
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

/** What "Copy" or "Cut" put aside, so "Paste" can recreate it. */
export type CopiedEvent = {
  title: string;
  durationMinutes: number;
  calendarId: string;
  location: string | null;
  notes: string;
  url?: string;
  alarms: CalendarEvent['source']['alarms'];
  availability: CalendarEvent['source']['availability'];
};

let clipboard: CopiedEvent | null = null;

export function snapshotEvent(event: CalendarEvent): CopiedEvent {
  return {
    title: event.title,
    durationMinutes: Math.round((event.end.getTime() - event.start.getTime()) / 60_000),
    calendarId: event.source.calendarId,
    location: event.location,
    notes: event.source.notes,
    url: event.source.url,
    alarms: event.source.alarms,
    availability: event.source.availability,
  };
}

export function copyEvent(event: CalendarEvent) {
  clipboard = snapshotEvent(event);
}

export function getCopiedEvent(): CopiedEvent | null {
  return clipboard;
}
