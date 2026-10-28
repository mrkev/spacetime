import { Stack, useLocalSearchParams } from 'expo-router';
import { Text, View } from 'react-native';

import { useTheme } from '../../lib/theme';
import { useCalendar } from '../../time/CalendarProvider';
import { ReminderEditor } from '../../time/ReminderEditor';

/** Edits a reminder in the system Reminders app. */
export default function EditReminderScreen() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const reminder = useCalendar().getReminder(id);
  if (!reminder) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <Stack.Screen options={{ title: 'Edit Reminder' }} />
        <Text style={{ color: theme.secondaryText }}>This reminder is no longer available.</Text>
      </View>
    );
  }
  return <ReminderEditor reminder={reminder} />;
}
