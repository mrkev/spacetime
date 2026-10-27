import { Fragment } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useTheme } from '../lib/theme';

export type EditMenuItem = { label: string; destructive?: boolean; onPress: () => void };

export const EDIT_MENU_HEIGHT = 44;

/** A horizontal action bar like iOS's edit menu (Cut · Copy · Delete · Duplicate). */
export function EditMenu({ items, top }: { items: EditMenuItem[]; top: number }) {
  const theme = useTheme();
  return (
    <View pointerEvents="box-none" style={[styles.row, { top }]}>
      <View
        style={[
          styles.menu,
          {
            backgroundColor: theme.overlay,
            borderColor: theme.separator,
            shadowColor: theme.shadow,
          },
        ]}
      >
        {items.map((item, i) => (
          <Fragment key={item.label}>
            {i > 0 ? <View style={[styles.divider, { backgroundColor: theme.separator }]} /> : null}
            <Pressable
              onPress={item.onPress}
              accessibilityRole="button"
              style={({ pressed }) => [styles.item, pressed && { backgroundColor: theme.fill }]}
            >
              <Text style={[styles.label, { color: item.destructive ? theme.tint : theme.text }]}>
                {item.label}
              </Text>
            </Pressable>
          </Fragment>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { position: 'absolute', left: 8, right: 8, alignItems: 'center', zIndex: 10 },
  menu: {
    flexDirection: 'row',
    alignItems: 'center',
    height: EDIT_MENU_HEIGHT,
    borderRadius: EDIT_MENU_HEIGHT / 2,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'visible',
    shadowOpacity: 0.25,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 8,
    paddingHorizontal: 4,
  },
  item: {
    height: EDIT_MENU_HEIGHT - 8,
    justifyContent: 'center',
    paddingHorizontal: 14,
    borderRadius: (EDIT_MENU_HEIGHT - 8) / 2,
  },
  label: { fontSize: 15, fontWeight: '500' },
  divider: { width: StyleSheet.hairlineWidth, height: 18 },
});
