jest.mock('expo-sqlite/kv-store', () => ({
  __esModule: true,
  default: { getItemSync: () => null, setItemSync: () => {} },
}));
jest.mock('expo-calendar', () => ({}));
jest.mock('../../time/CalendarProvider', () => ({}));

import type { CalendarReminder } from '../../time/CalendarProvider';
import { DEFAULT_RADIUS, moveReminderTo, toLocationReminder } from '../locationReminders';

function reminder(alarms: unknown[]): CalendarReminder {
  return {
    key: 'r1',
    title: 'Buy milk',
    due: null,
    allDay: false,
    completed: false,
    color: '#FF9500',
    listTitle: 'Reminders',
    source: { alarms } as CalendarReminder['source'],
  };
}

const coords = { latitude: 37.78, longitude: -122.41 };

describe('toLocationReminder', () => {
  it('reads the place and trigger from the location alarm', () => {
    const location = toLocationReminder(
      reminder([
        { relativeOffset: 0 },
        { structuredLocation: { title: 'Market', proximity: 'leave', radius: 500, coords } },
      ]),
    );
    expect(location).toMatchObject({
      id: 'r1',
      title: 'Buy milk',
      placeName: 'Market',
      trigger: 'leave',
      radius: 500,
      ...coords,
    });
  });

  it('uses Reminders’ defaults for a missing radius or proximity', () => {
    const location = toLocationReminder(
      reminder([{ structuredLocation: { title: 'Home', proximity: 'None', radius: 0, coords } }]),
    );
    expect(location).toMatchObject({ trigger: 'arrive', radius: DEFAULT_RADIUS });
  });

  it('ignores reminders without a located alarm', () => {
    expect(toLocationReminder(reminder([{ relativeOffset: 0 }]))).toBeNull();
    expect(
      toLocationReminder(reminder([{ structuredLocation: { title: 'Nowhere', coords: {} } }])),
    ).toBeNull();
  });
});

describe('moveReminderTo', () => {
  const bakery = { latitude: 19.43, longitude: -99.13, name: 'Bakery', address: 'Calle 1' };

  function updated(alarms: unknown[]) {
    const r = reminder(alarms);
    const update = jest.fn(() => Promise.resolve());
    r.source.update = update as CalendarReminder['source']['update'];
    return { r, update };
  }

  it('adds a location alarm with the defaults, keeping other alarms', async () => {
    const { r, update } = updated([{ relativeOffset: 0 }]);
    await moveReminderTo(r, bakery, { trigger: 'arrive', radius: 250 });
    expect(update).toHaveBeenCalledWith({
      alarms: [
        { relativeOffset: 0 },
        {
          structuredLocation: {
            title: 'Bakery',
            proximity: 'enter',
            radius: 250,
            coords: { latitude: 19.43, longitude: -99.13 },
          },
        },
      ],
    });
  });

  it('replaces a location, keeping its trigger and radius', async () => {
    const { r, update } = updated([
      { structuredLocation: { title: 'Market', proximity: 'leave', radius: 500, coords } },
    ]);
    await moveReminderTo(r, bakery, { trigger: 'arrive', radius: 250 });
    expect(update).toHaveBeenCalledWith({
      alarms: [
        {
          structuredLocation: {
            title: 'Bakery',
            proximity: 'leave',
            radius: 500,
            coords: { latitude: 19.43, longitude: -99.13 },
          },
        },
      ],
    });
  });
});
