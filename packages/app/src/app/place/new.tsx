import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { ScrollView } from 'react-native';

import { HeaderButton } from '../../components/HeaderButton';
import { useTheme } from '../../lib/theme';
import { PlaceFormFields, usePlaceForm, useSavePlaceForm } from '../../space/PlaceForm';
import { REMINDERS_COLLECTION_ID, useSpaceState } from '../../space/store';

type Params = {
  latitude?: string;
  longitude?: string;
  collectionId?: string;
  name?: string;
  address?: string;
};

export default function NewPlaceScreen() {
  const theme = useTheme();
  const params = useLocalSearchParams<Params>();
  const { collections } = useSpaceState();

  const latitude = Number(params.latitude);
  const longitude = Number(params.longitude);
  const hasCoordinate = Number.isFinite(latitude) && Number.isFinite(longitude);
  const defaultCollection =
    collections.find((c) => c.id === params.collectionId) ??
    collections.find((c) => c.id !== REMINDERS_COLLECTION_ID) ??
    collections[0];

  const form = usePlaceForm({
    coordinate: hasCoordinate ? { latitude, longitude } : null,
    name: params.name ?? '',
    address: params.address ?? '',
    collectionId: defaultCollection.id,
  });

  const savePlaceForm = useSavePlaceForm();
  const [saving, setSaving] = useState(false);
  const save = async () => {
    if (!form.canSave || saving) return;
    setSaving(true);
    if (await savePlaceForm(form.state)) router.back();
    else setSaving(false);
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
          title: form.isReminder ? 'New Reminder' : 'New Place',
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (
            <HeaderButton label="Save" bold disabled={!form.canSave || saving} onPress={save} />
          ),
        }}
      />
      <PlaceFormFields form={form} collections={collections} />
    </ScrollView>
  );
}
