import type { ReactNode } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
  type TextInputProps,
} from 'react-native';

import { useTheme } from '../lib/theme';
import { Icon, icons } from './Icon';

/** An inset grouped section, like iOS Settings. */
export function Section({
  title,
  footer,
  children,
}: {
  title?: string;
  footer?: string;
  children: ReactNode;
}) {
  const theme = useTheme();
  return (
    <View style={styles.section}>
      {title ? (
        <Text style={[styles.sectionTitle, { color: theme.secondaryText }]}>
          {title.toUpperCase()}
        </Text>
      ) : null}
      <View style={[styles.card, { backgroundColor: theme.card }]}>{children}</View>
      {footer ? (
        <Text style={[styles.sectionFooter, { color: theme.secondaryText }]}>{footer}</Text>
      ) : null}
    </View>
  );
}

export function Separator() {
  const theme = useTheme();
  return <View style={[styles.separator, { backgroundColor: theme.separator }]} />;
}

export function Field(props: TextInputProps) {
  const theme = useTheme();
  return (
    <TextInput
      placeholderTextColor={theme.secondaryText}
      {...props}
      style={[
        styles.field,
        { color: theme.text },
        props.multiline && styles.multiline,
        props.style,
      ]}
    />
  );
}

export function Row({
  label,
  value,
  onPress,
  children,
  destructive,
}: {
  label: string;
  value?: string;
  onPress?: () => void;
  children?: ReactNode;
  destructive?: boolean;
}) {
  const theme = useTheme();
  return (
    <Pressable
      onPress={onPress}
      disabled={!onPress}
      style={({ pressed }) => [styles.row, pressed && onPress && { backgroundColor: theme.fill }]}
    >
      <Text
        style={[styles.rowLabel, { color: destructive ? theme.tint : theme.text }]}
        numberOfLines={1}
      >
        {label}
      </Text>
      {value ? (
        <Text style={[styles.rowValue, { color: theme.secondaryText }]} numberOfLines={1}>
          {value}
        </Text>
      ) : children ? (
        <View style={styles.spacer} />
      ) : null}
      {children}
    </Pressable>
  );
}

/** A search field for the top of a section, with a spinner while `searching`. */
export function SearchRow({
  searching = false,
  ...props
}: TextInputProps & { searching?: boolean }) {
  const theme = useTheme();
  return (
    <View style={styles.searchRow}>
      <Icon name={icons.search} color={theme.secondaryText} size={16} />
      <Field
        style={styles.searchField}
        returnKeyType="search"
        autoCorrect={false}
        clearButtonMode="while-editing"
        {...props}
      />
      {searching ? <ActivityIndicator /> : null}
    </View>
  );
}

/** A row to pick from a list: a colored dot, a title and subtitle, and a check if `checked`. */
export function PickRow({
  title,
  subtitle,
  color,
  checked = false,
  onPress,
}: {
  title: string;
  subtitle?: string;
  color?: string;
  checked?: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.pickRow, pressed && { backgroundColor: theme.fill }]}
      accessibilityRole="button"
      accessibilityState={{ selected: checked }}
    >
      {color ? <View style={[styles.dot, { backgroundColor: color }]} /> : null}
      <View style={styles.pickText}>
        <Text style={[styles.pickTitle, { color: theme.text }]} numberOfLines={2}>
          {title}
        </Text>
        {subtitle ? (
          <Text style={[styles.pickSubtitle, { color: theme.secondaryText }]} numberOfLines={1}>
            {subtitle}
          </Text>
        ) : null}
      </View>
      {checked ? <Icon name={icons.check} color={theme.blue} size={16} weight="semibold" /> : null}
    </Pressable>
  );
}

export function SwitchRow({
  label,
  value,
  onValueChange,
}: {
  label: string;
  value: boolean;
  onValueChange: (value: boolean) => void;
}) {
  return (
    <Row label={label}>
      <Switch value={value} onValueChange={onValueChange} />
    </Row>
  );
}

/** A compact segmented control built from plain views so it matches on both platforms. */
export function Segmented<T extends string | number>({
  options,
  value,
  onChange,
}: {
  options: { label: string; value: T }[];
  value: T;
  onChange: (value: T) => void;
}) {
  const theme = useTheme();
  return (
    <View style={[styles.segmented, { backgroundColor: theme.fill }]}>
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <Pressable
            key={String(option.value)}
            onPress={() => onChange(option.value)}
            style={[
              styles.segment,
              selected && [styles.segmentSelected, { backgroundColor: theme.card }],
            ]}
            accessibilityRole="button"
            accessibilityState={{ selected }}
          >
            <Text style={[styles.segmentLabel, { color: theme.text }, selected && styles.bold]}>
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  section: { marginHorizontal: 16, marginTop: 24 },
  sectionTitle: { fontSize: 13, marginLeft: 16, marginBottom: 6 },
  sectionFooter: { fontSize: 13, marginHorizontal: 16, marginTop: 6, lineHeight: 18 },
  card: { borderRadius: 10, overflow: 'hidden' },
  separator: { height: StyleSheet.hairlineWidth, marginLeft: 16 },
  field: { fontSize: 17, paddingHorizontal: 16, paddingVertical: 12, minHeight: 44 },
  multiline: { minHeight: 88, textAlignVertical: 'top', paddingTop: 12 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    minHeight: 44,
    paddingHorizontal: 16,
    paddingVertical: 8,
    gap: 8,
  },
  rowLabel: { fontSize: 17, flexShrink: 0 },
  rowValue: { fontSize: 17, flex: 1, textAlign: 'right' },
  spacer: { flex: 1 },
  searchRow: { flexDirection: 'row', alignItems: 'center', paddingLeft: 14, paddingRight: 12 },
  searchField: { flex: 1, paddingHorizontal: 8 },
  pickRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    minHeight: 44,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  dot: { width: 12, height: 12, borderRadius: 6 },
  pickText: { flex: 1 },
  pickTitle: { fontSize: 17 },
  pickSubtitle: { fontSize: 13, marginTop: 1 },
  segmented: { flexDirection: 'row', borderRadius: 8, padding: 2, margin: 8 },
  segment: { flex: 1, paddingVertical: 6, alignItems: 'center', borderRadius: 7 },
  segmentSelected: {
    shadowColor: '#000',
    shadowOpacity: 0.12,
    shadowRadius: 3,
    shadowOffset: { width: 0, height: 1 },
    elevation: 1,
  },
  segmentLabel: { fontSize: 13 },
  bold: { fontWeight: '600' },
});
