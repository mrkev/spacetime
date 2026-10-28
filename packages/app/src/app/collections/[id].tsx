import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Alert, ScrollView } from 'react-native';

import { ColorSwatches } from '../../components/ColorSwatches';
import { Field, Row, Section } from '../../components/Form';
import { HeaderButton } from '../../components/HeaderButton';
import { PIN_COLORS, useTheme } from '../../lib/theme';
import { addToCollection, findMapPlace, useMapPlaces } from '../../space/places';
import {
  REMINDERS_COLLECTION_ID,
  addCollection,
  deleteCollection,
  placesOnlyIn,
  updateCollection,
  useSpaceState,
} from '../../space/store';

export default function EditCollectionScreen() {
  const theme = useTheme();
  // `placeId` is a place to add a new collection to.
  const { id, placeId } = useLocalSearchParams<{ id: string; placeId?: string }>();
  const { collections } = useSpaceState();
  const mapPlaces = useMapPlaces();
  const existing = collections.find((c) => c.id === id);
  const isNew = !existing;
  const isReminders = id === REMINDERS_COLLECTION_ID;

  const [name, setName] = useState(existing?.name ?? '');
  const [color, setColor] = useState(
    existing?.color ?? PIN_COLORS[collections.length % PIN_COLORS.length],
  );

  const save = () => {
    const trimmed = name.trim();
    if (!trimmed) return;
    if (existing) updateCollection(existing.id, { name: trimmed, color });
    else {
      const added = addCollection(trimmed, color);
      const place = placeId ? findMapPlace(mapPlaces, placeId) : null;
      if (place) addToCollection(place, added.id);
    }
    router.back();
  };

  const confirmDelete = () => {
    if (!existing) return;
    const count = placesOnlyIn(existing.id).length;
    Alert.alert(
      `Delete “${existing.name}”?`,
      count > 0
        ? `This also deletes ${count === 1 ? 'a place' : `${count} places`} that ${count === 1 ? 'isn’t' : 'aren’t'} in any other collection.`
        : undefined,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            router.back();
            deleteCollection(existing.id);
          },
        },
      ],
    );
  };

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: theme.groupedBackground }}
      contentContainerStyle={{ paddingBottom: 40 }}
      keyboardShouldPersistTaps="handled"
    >
      <Stack.Screen
        options={{
          title: isNew ? 'New Collection' : existing.name,
          // Opened straight from a place, with nothing to go back to.
          headerLeft: placeId
            ? () => <HeaderButton label="Cancel" color={theme.blue} onPress={() => router.back()} />
            : undefined,
          headerRight: () => (
            <HeaderButton
              label={isNew ? 'Add' : 'Save'}
              bold
              color={theme.blue}
              disabled={!name.trim()}
              onPress={save}
            />
          ),
        }}
      />
      <Section
        footer={
          isReminders ? 'The Reminders collection can be renamed but not deleted.' : undefined
        }
      >
        <Field placeholder="Name" value={name} onChangeText={setName} autoFocus={isNew} />
      </Section>
      <Section title="Pin Color">
        <ColorSwatches value={color} onChange={setColor} />
      </Section>
      {existing && !isReminders ? (
        <Section>
          <Row label="Delete Collection" destructive onPress={confirmDelete} />
        </Section>
      ) : null}
    </ScrollView>
  );
}
