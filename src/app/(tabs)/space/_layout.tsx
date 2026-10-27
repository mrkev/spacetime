import { Stack } from 'expo-router';

export default function SpaceLayout() {
  return (
    <Stack>
      <Stack.Screen name="index" options={{ headerShown: false, title: 'Space' }} />
    </Stack>
  );
}
