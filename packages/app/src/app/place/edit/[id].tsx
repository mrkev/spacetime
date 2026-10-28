import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Alert, ScrollView } from 'react-native';

import { Field, Section } from '../../../components/Form';
import { HeaderButton } from '../../../components/HeaderButton';
import { useTheme } from '../../../lib/theme';
import { LocationFields, placeName, type LocationState } from '../../../space/PlaceForm';
import { MissingPlace } from '../../../space/PlaceSheet';
import {
  findMapPlace,
  pinColor,
  syncTodos,
  useMapPlaces,
  type MapPlace,
} from '../../../space/places';
import { updatePlace, useSpaceState } from '../../../space/store';
import { useCalendar } from '../../../time/CalendarProvider';

export default function EditPlaceScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const place = findMapPlace(useMapPlaces(), id);
  if (!place?.saved) return <MissingPlace message="This place was deleted." />;
  // Keyed so the form resets if another place is opened into the same screen.
  return <PlaceEditor key={place.id} place={place} />;
}

/** Edits where a saved place is, its name, and its notes. Its todos move with it. */
function PlaceEditor({ place }: { place: MapPlace }) {
  const theme = useTheme();
  const { collections } = useSpaceState();
  const { refresh } = useCalendar();
  const [location, setLocation] = useState<LocationState>({
    coordinate: { latitude: place.latitude, longitude: place.longitude },
    name: place.name,
    address: place.address ?? '',
  });
  const [notes, setNotes] = useState(place.saved?.notes ?? '');
  const [saving, setSaving] = useState(false);

  const save = async () => {
    if (!location.coordinate || saving) return;
    const changes = {
      name: placeName(location),
      address: location.address || undefined,
      ...location.coordinate,
    };
    updatePlace(place.id, { ...changes, notes: notes.trim() || undefined });
    const moved =
      changes.name !== place.name ||
      changes.address !== place.address ||
      changes.latitude !== place.latitude ||
      changes.longitude !== place.longitude;
    if (moved && place.todos.length > 0) {
      setSaving(true);
      try {
        await syncTodos(place.todos, changes);
        refresh();
      } catch (error) {
        Alert.alert('Couldn’t Update Todos', String(error));
      }
    }
    router.back();
  };

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: theme.groupedBackground }}
      contentContainerStyle={{ paddingBottom: 40 }}
      keyboardShouldPersistTaps="handled"
      automaticallyAdjustKeyboardInsets
    >
      <Stack.Screen
        options={{
          title: 'Edit Place',
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (
            <HeaderButton
              label="Done"
              bold
              disabled={!location.coordinate || saving}
              onPress={save}
            />
          ),
        }}
      />
      <LocationFields
        state={location}
        update={(changes) => setLocation((l) => ({ ...l, ...changes }))}
        color={pinColor(place, collections, theme.tint)}
      />
      <Section title="Notes">
        <Field placeholder="Notes" value={notes} onChangeText={setNotes} multiline />
      </Section>
    </ScrollView>
  );
}
