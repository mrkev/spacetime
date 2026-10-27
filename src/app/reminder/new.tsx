import { useLocalSearchParams } from 'expo-router';
import { useMemo } from 'react';

import { ReminderEditor } from '../../time/ReminderEditor';

/** Creates a reminder in the system Reminders app. */
export default function NewReminderScreen() {
  const params = useLocalSearchParams<{ date?: string }>();
  const date = useMemo(() => (params.date ? new Date(params.date) : undefined), [params.date]);
  return <ReminderEditor date={date} />;
}
