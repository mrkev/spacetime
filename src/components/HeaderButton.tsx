import { Pressable, StyleSheet, Text } from 'react-native';

import { useTheme } from '../lib/theme';
import { Icon, type IconName } from './Icon';

type Props = {
  onPress: () => void;
  icon?: IconName;
  label?: string;
  bold?: boolean;
  disabled?: boolean;
  color?: string;
  accessibilityLabel?: string;
};

export function HeaderButton({
  onPress,
  icon,
  label,
  bold,
  disabled,
  color,
  accessibilityLabel,
}: Props) {
  const theme = useTheme();
  const tint = disabled ? theme.tertiaryText : (color ?? theme.tint);
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      hitSlop={8}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? label}
      style={({ pressed }) => [styles.button, pressed && styles.pressed]}
    >
      {icon ? <Icon name={icon} color={tint} size={22} /> : null}
      {label ? (
        <Text style={[styles.label, { color: tint }, bold && styles.bold]}>{label}</Text>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 6,
    minHeight: 32,
  },
  pressed: { opacity: 0.5 },
  label: { fontSize: 17 },
  bold: { fontWeight: '600' },
});
