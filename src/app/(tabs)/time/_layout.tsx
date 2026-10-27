import { Stack } from 'expo-router';

import { useTheme } from '../../../lib/theme';

// The year view is the base of the calendar: the month view opens on top of it (see
// `openTimeTab`), so back and swipe-back go up to the year, like Calendar.
export const unstable_settings = { initialRouteName: 'year' };

export default function TimeLayout() {
  const theme = useTheme();
  return (
    <Stack
      screenOptions={{
        headerTintColor: theme.tint,
        headerShadowVisible: false,
        headerStyle: { backgroundColor: theme.background },
        headerTitleStyle: { color: theme.text },
      }}
    >
      {/* If the month view (index) ever ends up at the bottom of the stack, it opens the year view
          by replacing itself, so that animates like going back. */}
      <Stack.Screen name="year" options={{ title: '', animationTypeForReplace: 'pop' }} />
      <Stack.Screen name="index" options={{ title: '' }} />
      <Stack.Screen name="day" options={{ title: '' }} />
      <Stack.Screen
        name="reminders"
        options={{
          title: 'Reminders',
          headerLargeTitle: true,
          headerStyle: { backgroundColor: theme.groupedBackground },
        }}
      />
    </Stack>
  );
}
