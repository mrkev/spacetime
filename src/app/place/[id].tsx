import { Stack, router, useLocalSearchParams } from 'expo-router';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';

import { Row, Section, Separator } from '../../components/Form';
import { HeaderButton } from '../../components/HeaderButton';
import { formatMediumDate } from '../../lib/dates';
import { openDirections } from '../../lib/geo';
import { useTheme } from '../../lib/theme';
import {
  PlaceFormFields,
  ensureReminderPermissions,
  toPlaceInput,
  usePlaceForm,
} from '../../space/PlaceForm';
import { deletePlace, updatePlace, useSpaceState, type Place } from '../../space/store';

export default function PlaceScreen() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { places } = useSpaceState();
  const place = places.find((p) => p.id === id);

  if (!place) {
    return (
      <View style={[styles.missing, { backgroundColor: theme.groupedBackground }]}>
        <Stack.Screen options={{ title: '' }} />
        <Text style={{ color: theme.secondaryText }}>This place was deleted.</Text>
      </View>
    );
  }
  // Keyed so the form resets if another place is opened into the same screen.
  return <PlaceEditor key={place.id} place={place} />;
}

function PlaceEditor({ place }: { place: Place }) {
  const theme = useTheme();
  const { collections } = useSpaceState();
  const form = usePlaceForm({
    coordinate: { latitude: place.latitude, longitude: place.longitude },
    name: place.name,
    address: place.address ?? '',
    notes: place.notes ?? '',
    collectionId: place.collectionId,
    reminder: place.reminder,
  });

  const save = async () => {
    if (!form.canSave) return;
    const input = toPlaceInput(form.state);
    const becameActiveReminder = !!input.reminder?.enabled && !place.reminder?.enabled;
    updatePlace(place.id, input);
    router.back();
    if (becameActiveReminder) await ensureReminderPermissions();
  };

  const confirmDelete = () => {
    Alert.alert(`Delete “${place.name}”?`, undefined, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          router.back();
          deletePlace(place.id);
        },
      },
    ]);
  };

  const reminder = place.reminder;

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
          title: place.name,
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (
            <HeaderButton label="Done" bold disabled={!form.canSave} onPress={save} />
          ),
        }}
      />
      <PlaceFormFields
        form={form}
        collections={collections}
        footer={
          <>
            {reminder && form.isReminder ? (
              <Section
                footer={
                  reminder.lastFiredAt
                    ? `Last reminded ${formatMediumDate(new Date(reminder.lastFiredAt))}.`
                    : undefined
                }
              >
                <Row
                  label={reminder.enabled ? 'Mark as Completed' : 'Turn Reminder Back On'}
                  onPress={() => {
                    // Applies immediately, like checking off a reminder in a list.
                    const enabled = !reminder.enabled;
                    form.updateReminder({ enabled });
                    updatePlace(place.id, { reminder: { ...reminder, enabled } });
                    if (enabled) ensureReminderPermissions();
                  }}
                />
              </Section>
            ) : null}
            <Section>
              <Row
                label="Directions"
                onPress={() => openDirections(place, place.name)}
              />
              <Separator />
              <Row label="Delete Place" destructive onPress={confirmDelete} />
            </Section>
          </>
        }
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  missing: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
