import { Linking, Pressable, StyleSheet, Text, View } from 'react-native';

import { useTheme } from '../lib/theme';
import { useCalendar } from './CalendarProvider';

/** Explains why the calendar is empty and offers to fix it. */
export function AccessBanner() {
  const theme = useTheme();
  const { status, requestAccess } = useCalendar();
  if (status === 'granted' || status === 'loading') return null;

  const denied = status === 'denied';
  return (
    <View style={[styles.banner, { backgroundColor: theme.card, borderColor: theme.separator }]}>
      <Text style={[styles.title, { color: theme.text }]}>See your events and reminders</Text>
      <Text style={[styles.body, { color: theme.secondaryText }]}>
        {denied
          ? 'Calendar access is turned off. Allow it in Settings to show your events here.'
          : 'Spacetime reads the calendars and reminders already on your phone.'}
      </Text>
      <Pressable
        onPress={() => (denied ? Linking.openSettings() : requestAccess())}
        style={({ pressed }) => [
          styles.button,
          { backgroundColor: theme.tint },
          pressed && { opacity: 0.7 },
        ]}
      >
        <Text style={styles.buttonLabel}>{denied ? 'Open Settings' : 'Allow Access'}</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  banner: {
    margin: 12,
    padding: 14,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 6,
  },
  title: { fontSize: 15, fontWeight: '600' },
  body: { fontSize: 13, lineHeight: 18 },
  button: {
    alignSelf: 'flex-start',
    marginTop: 4,
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 16,
  },
  buttonLabel: { color: '#fff', fontWeight: '600', fontSize: 14 },
});
