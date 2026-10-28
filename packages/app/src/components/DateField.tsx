import DateTimePicker, { DateTimePickerAndroid } from '@react-native-community/datetimepicker';
import { Platform, Pressable, StyleSheet, Text } from 'react-native';

import { formatMediumDate, formatTime } from '../lib/dates';
import { useTheme } from '../lib/theme';

/** Compact inline picker on iOS; a tappable value that opens the system dialog on Android. */
export function DateField({
  value,
  mode,
  onChange,
}: {
  value: Date;
  mode: 'date' | 'time';
  onChange: (date: Date) => void;
}) {
  const theme = useTheme();

  if (Platform.OS === 'ios') {
    return (
      <DateTimePicker
        value={value}
        mode={mode}
        display="compact"
        accentColor={theme.tint}
        onChange={(_, date) => date && onChange(date)}
      />
    );
  }

  return (
    <Pressable
      style={[styles.android, { backgroundColor: theme.fill }]}
      onPress={() =>
        DateTimePickerAndroid.open({
          value,
          mode,
          onChange: (event, date) => {
            if (event.type === 'set' && date) onChange(date);
          },
        })
      }
    >
      <Text style={{ color: theme.text, fontSize: 15 }}>
        {mode === 'date' ? formatMediumDate(value) : formatTime(value)}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  android: { paddingHorizontal: 10, paddingVertical: 6, borderRadius: 6 },
});
