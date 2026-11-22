import { useLocalSearchParams } from 'expo-router';

import { ReminderEditor } from '../../time/ReminderEditor';

/** Creates a reminder in the system Reminders app. */
export default function NewReminderScreen() {
  const params = useLocalSearchParams<{ date?: string }>();
  const date = params.date ? new Date(params.date) : undefined;
  return <ReminderEditor date={date} />;
}
