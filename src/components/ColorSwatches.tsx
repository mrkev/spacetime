import { Pressable, StyleSheet, View } from 'react-native';

import { PIN_COLORS, useTheme } from '../lib/theme';
import { Icon, icons } from './Icon';

export function ColorSwatches({
  value,
  onChange,
}: {
  value: string;
  onChange: (color: string) => void;
}) {
  const theme = useTheme();
  return (
    <View style={styles.grid}>
      {PIN_COLORS.map((color) => {
        const selected = color.toLowerCase() === value.toLowerCase();
        return (
          <Pressable
            key={color}
            onPress={() => onChange(color)}
            accessibilityRole="button"
            accessibilityLabel={`Color ${color}`}
            accessibilityState={{ selected }}
            style={[styles.ring, { borderColor: selected ? theme.tertiaryText : 'transparent' }]}
          >
            <View style={[styles.swatch, { backgroundColor: color }]}>
              {selected ? <Icon name={icons.check} size={16} color="#fff" weight="bold" /> : null}
            </View>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    padding: 12,
    gap: 6,
  },
  ring: { padding: 3, borderRadius: 24, borderWidth: 3 },
  swatch: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
