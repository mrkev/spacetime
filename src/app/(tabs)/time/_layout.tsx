import { Stack } from 'expo-router';

import { useTheme } from '../../../lib/theme';

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
