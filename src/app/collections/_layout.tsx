import { Stack } from 'expo-router';

import { useTheme } from '../../lib/theme';

export default function CollectionsLayout() {
  const theme = useTheme();
  return (
    <Stack
      screenOptions={{ headerTintColor: theme.blue, headerTitleStyle: { color: theme.text } }}
    >
      <Stack.Screen name="index" options={{ title: 'Collections' }} />
      <Stack.Screen name="[id]" options={{ title: '' }} />
    </Stack>
  );
}
