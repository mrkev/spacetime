import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';

import { toLocationReminder } from '../../../space/locationReminders';
import { MissingPlace, PlaceEditor } from '../../../space/PlaceEditor';
import { useCalendar } from '../../../time/CalendarProvider';

/** A location reminder, edited like a place. */
export default function LocationReminderScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const found = useCalendar().getReminder(id);
  // Completed reminders drop out of the loaded data, so keep editing the copy we opened.
  const located = found ? toLocationReminder(found) : null;
  const [opened, setOpened] = useState(located);
  if (!opened && located) setOpened(located);
  if (!opened) return <MissingPlace message="This reminder is no longer available." />;
  return <PlaceEditor key={opened.id} original={{ kind: 'reminder', reminder: opened }} />;
}
