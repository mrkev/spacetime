import * as Notifications from 'expo-notifications';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider, router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { StyleSheet, useColorScheme } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

import { useTheme } from '../lib/theme';
import { startGeofenceSync } from '../space/geofence';
import { CalendarProvider } from '../time/CalendarProvider';

// Deep links into a modal (e.g. tapping a reminder notification) still get the tabs beneath them.
export const unstable_settings = { anchor: '(tabs)' };

export default function RootLayout() {
  const scheme = useColorScheme();
  const theme = useTheme();
  const navigationTheme = scheme === 'dark' ? DarkTheme : DefaultTheme;

  useEffect(() => {
    startGeofenceSync();
  }, []);

  useOpenPlaceFromNotification();

  return (
    <GestureHandlerRootView style={StyleSheet.absoluteFill}>
      <ThemeProvider
        value={{
          ...navigationTheme,
          colors: { ...navigationTheme.colors, primary: theme.tint, background: theme.background },
        }}
      >
        <CalendarProvider>
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
            <Stack.Screen name="place/[id]" options={{ presentation: 'modal', title: '' }} />
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

/** Tapping a location reminder notification opens that place. */
function useOpenPlaceFromNotification() {
  const response = Notifications.useLastNotificationResponse();
  useEffect(() => {
    const placeId = response?.notification.request.content.data?.placeId;
    if (typeof placeId === 'string') {
      router.push({ pathname: '/place/[id]', params: { id: placeId } });
    }
  }, [response]);
}
