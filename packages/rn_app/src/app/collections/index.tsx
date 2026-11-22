import { Stack, router } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { Section, Separator } from '../../components/Form';
import { HeaderButton } from '../../components/HeaderButton';
import { Icon, icons } from '../../components/Icon';
import { useTheme } from '../../lib/theme';
import { isInCollection, useMapPlaces } from '../../space/places';
import { REMINDERS_COLLECTION_ID, useSpaceState } from '../../space/store';

export default function CollectionsScreen() {
  const theme = useTheme();
  const { collections } = useSpaceState();
  const mapPlaces = useMapPlaces();
  const count = (id: string) => mapPlaces.filter((p) => isInCollection(p, id)).length;

  const reminders = collections.filter((c) => c.id === REMINDERS_COLLECTION_ID);
  const others = collections.filter((c) => c.id !== REMINDERS_COLLECTION_ID);

  const renderRows = (list: typeof collections) =>
    list.map((collection, i) => (
      <View key={collection.id}>
        {i > 0 ? <Separator /> : null}
        <Pressable
          style={({ pressed }) => [styles.row, pressed && { backgroundColor: theme.fill }]}
          onPress={() =>
            router.push({ pathname: '/collections/[id]', params: { id: collection.id } })
          }
        >
          <View style={[styles.badge, { backgroundColor: collection.color }]}>
            <Icon
              name={collection.id === REMINDERS_COLLECTION_ID ? icons.bell : icons.mappin}
              color="#fff"
              size={16}
            />
          </View>
          <Text style={[styles.name, { color: theme.text }]} numberOfLines={1}>
            {collection.name}
          </Text>
          <Text style={[styles.count, { color: theme.secondaryText }]}>{count(collection.id)}</Text>
          <Icon name={icons.chevronRight} color={theme.tertiaryText} size={14} />
        </Pressable>
      </View>
    ));

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: theme.groupedBackground }}
      contentContainerStyle={{ paddingBottom: 40 }}
    >
      <Stack.Screen
        options={{
          headerLeft: () => (
            <HeaderButton label="Done" bold color={theme.blue} onPress={() => router.back()} />
          ),
          headerRight: () => (
            <HeaderButton
              icon={icons.plus}
              color={theme.blue}
              accessibilityLabel="New collection"
              onPress={() => router.push({ pathname: '/collections/[id]', params: { id: 'new' } })}
            />
          ),
        }}
      />
      <Section footer="Places with todos: reminders with a location, from any list in the Reminders app. Reminders notifies you when you arrive at or leave them.">
        {renderRows(reminders)}
      </Section>
      <Section title="My Maps">
        {others.length > 0 ? (
          renderRows(others)
        ) : (
          <Text style={[styles.empty, { color: theme.secondaryText }]}>No collections yet.</Text>
        )}
      </Section>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 16,
    minHeight: 52,
  },
  badge: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
  },
  name: { flex: 1, fontSize: 17 },
  count: { fontSize: 17 },
  empty: { padding: 16, fontSize: 15 },
});
