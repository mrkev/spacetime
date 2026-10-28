import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';

import { toLocationReminder } from '../../../space/locationReminders';
import { MissingPlace } from '../../../space/PlaceSheet';
import { useMapPlaces } from '../../../space/places';
import { TodoEditor } from '../../../space/TodoEditor';
import { useCalendar } from '../../../time/CalendarProvider';

/** A todo: a location reminder. */
export default function TodoScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const found = useCalendar().getReminder(id);
  const mapPlaces = useMapPlaces();
  // Completed reminders drop out of the loaded data, so keep editing the copy we opened.
  const located = found ? toLocationReminder(found) : null;
  const [opened, setOpened] = useState(
    located && { todo: located, place: mapPlaces.find((p) => p.todos.some((t) => t.id === id)) },
  );
  if (!opened && located) {
    setOpened({ todo: located, place: mapPlaces.find((p) => p.todos.some((t) => t.id === id)) });
  }
  if (!opened) return <MissingPlace message="This todo is no longer available." />;
  return <TodoEditor key={opened.todo.id} existing={opened.todo} place={opened.place ?? null} />;
}
