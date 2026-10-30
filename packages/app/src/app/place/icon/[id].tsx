import { Stack, router, useLocalSearchParams } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { HeaderButton } from '../../../components/HeaderButton';
import { useTheme } from '../../../lib/theme';
import { ICON_GROUPS, PlaceBadge, badgeColor, symbolIcon } from '../../../space/PlaceIcon';
import { MissingPlace } from '../../../space/PlaceSheet';
import { findMapPlace, useMapPlaces } from '../../../space/places';
import { updatePlace, useSpaceState } from '../../../space/store';

const CELL = 52;

/** Picks a saved place's icon, or goes back to its own (from Apple's map, or a plain pin). */
export default function PlaceIconScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const theme = useTheme();
  const { collections } = useSpaceState();
  const place = findMapPlace(useMapPlaces(), id);
  if (!place?.saved) return <MissingPlace message="This place was deleted." />;

  const color = badgeColor(place, collections, theme);
  const choose = (icon: string | undefined) => {
    updatePlace(place.saved!.id, { icon });
    router.back();
  };

  const cell = (key: string, icon: string | undefined, selected: boolean, label: string) => (
    <Pressable
      key={key}
      onPress={() => choose(icon)}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ selected }}
      style={[styles.cell, selected && { borderColor: color }]}
    >
      <PlaceBadge icon={icon ?? place.mapIcon} color={color} size={40} />
    </Pressable>
  );

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: theme.groupedBackground }}
      contentContainerStyle={styles.content}
    >
      <Stack.Screen
        options={{
          title: 'Icon',
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
        }}
      />
      <Text style={[styles.groupTitle, { color: theme.secondaryText }]}>
        {place.mapIcon ? 'FROM APPLE MAPS' : 'DEFAULT'}
      </Text>
      <View style={styles.grid}>
        {cell('default', undefined, !place.saved.icon, place.mapIcon ? 'Apple Maps icon' : 'Pin')}
      </View>
      {ICON_GROUPS.map((group) => (
        <View key={group.title}>
          <Text style={[styles.groupTitle, { color: theme.secondaryText }]}>
            {group.title.toUpperCase()}
          </Text>
          <View style={styles.grid}>
            {group.symbols.map((symbol) => {
              const icon = symbolIcon(symbol);
              return cell(symbol, icon, place.saved!.icon === icon, symbol);
            })}
          </View>
        </View>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { paddingHorizontal: 16, paddingBottom: 40 },
  groupTitle: { fontSize: 13, marginTop: 20, marginBottom: 8, marginLeft: 4 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  cell: {
    width: CELL,
    height: CELL,
    borderRadius: CELL / 2,
    borderWidth: 2.5,
    borderColor: 'transparent',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
