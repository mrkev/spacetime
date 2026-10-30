import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { StyleSheet, useColorScheme } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

import { useTheme } from '../lib/theme';
import { LegacyReminderMigration } from '../space/LegacyReminderMigration';
import { CalendarProvider } from '../time/CalendarProvider';

// Deep links into a modal still get the tabs beneath them.
export const unstable_settings = { anchor: '(tabs)' };

export default function RootLayout() {
  const scheme = useColorScheme();
  const theme = useTheme();
  const navigationTheme = scheme === 'dark' ? DarkTheme : DefaultTheme;

  return (
    <GestureHandlerRootView style={StyleSheet.absoluteFill}>
      <ThemeProvider
        value={{
          ...navigationTheme,
          colors: { ...navigationTheme.colors, primary: theme.tint, background: theme.background },
        }}
      >
        <CalendarProvider>
          <LegacyReminderMigration />
          <StatusBar style="auto" />
          <Stack
            screenOptions={{ headerTintColor: theme.tint, headerTitleStyle: { color: theme.text } }}
          >
            <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
            <Stack.Screen name="index" options={{ headerShown: false }} />
            <Stack.Screen
              name="place/new"
              options={{ presentation: 'modal', title: 'New Place' }}
            />
            <Stack.Screen
              name="place/[id]"
              options={{
                presentation: 'formSheet',
                headerShown: false,
                sheetAllowedDetents: [0.5, 1],
                sheetGrabberVisible: true,
              }}
            />
            <Stack.Screen
              name="place/edit/[id]"
              options={{ presentation: 'modal', title: 'Edit Place' }}
            />
            <Stack.Screen
              name="place/todo"
              options={{ presentation: 'modal', title: 'Add to Reminder' }}
            />
            <Stack.Screen
              name="place/event"
              options={{ presentation: 'modal', title: 'Add to Event' }}
            />
            <Stack.Screen
              name="place/reminder/[id]"
              options={{ presentation: 'modal', title: '' }}
            />
            <Stack.Screen
              name="place/icon/[id]"
              options={{ presentation: 'modal', title: 'Icon' }}
            />
            <Stack.Screen name="event/place" options={{ presentation: 'modal', title: '' }} />
            <Stack.Screen
              name="collections"
              options={{ presentation: 'modal', headerShown: false }}
            />
            <Stack.Screen
              name="reminder/new"
              options={{ presentation: 'modal', title: 'New Reminder' }}
            />
            <Stack.Screen name="reminder/[id]" options={{ presentation: 'modal', title: '' }} />
            <Stack.Screen
              name="reminder/edit"
              options={{ presentation: 'modal', title: 'Edit Reminder' }}
            />
          </Stack>
        </CalendarProvider>
      </ThemeProvider>
    </GestureHandlerRootView>
  );
}
