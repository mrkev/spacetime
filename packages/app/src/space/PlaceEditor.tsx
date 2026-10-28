import { Stack, router } from 'expo-router';
import { useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';

import { Row, Section, Separator } from '../components/Form';
import { HeaderButton } from '../components/HeaderButton';
import { openDirections } from '../lib/geo';
import { useTheme } from '../lib/theme';
import { useCalendar } from '../time/CalendarProvider';
import { showInReminders } from '../time/actions';
import {
  PlaceFormFields,
  usePlaceForm,
  useSavePlaceForm,
  type PlaceFormOriginal,
} from './PlaceForm';
import { REMINDERS_COLLECTION_ID, deletePlace, useSpaceState } from './store';

/** Edits a saved place or a location reminder (which can be moved between the two). */
export function PlaceEditor({ original }: { original: PlaceFormOriginal }) {
  const theme = useTheme();
  const { collections } = useSpaceState();
  const { toggleReminder, refresh } = useCalendar();
  const savePlaceForm = useSavePlaceForm();
  const [saving, setSaving] = useState(false);

  const place =
    original.kind === 'place'
      ? original.place
      : {
          name: original.reminder.placeName,
          address: original.reminder.address,
          notes: original.reminder.notes,
          latitude: original.reminder.latitude,
          longitude: original.reminder.longitude,
          collectionId: REMINDERS_COLLECTION_ID,
        };
  const form = usePlaceForm({
    coordinate: { latitude: place.latitude, longitude: place.longitude },
    name: place.name,
    address: place.address ?? '',
    notes: place.notes ?? '',
    collectionId: place.collectionId,
    reminder:
      original.kind === 'reminder'
        ? {
            title: original.reminder.title,
            trigger: original.reminder.trigger,
            radius: original.reminder.radius,
          }
        : undefined,
  });

  const save = async () => {
    if (!form.canSave || saving) return;
    setSaving(true);
    if (await savePlaceForm(form.state, original)) router.back();
    else setSaving(false);
  };

  const remove = () => {
    if (original.kind === 'place') {
      router.back();
      deletePlace(original.place.id);
      return;
    }
    original.reminder.reminder.source
      .delete()
      .then(() => {
        refresh();
        router.back();
      })
      .catch((error) => Alert.alert('Couldn’t Delete Reminder', String(error)));
  };

  const confirmDelete = () => {
    const name = original.kind === 'place' ? original.place.name : original.reminder.title;
    Alert.alert(`Delete “${name}”?`, undefined, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Delete', style: 'destructive', onPress: remove },
    ]);
  };

  const reminder = original.kind === 'reminder' ? original.reminder : null;
  // Checking it off applies right away, like in a list. It then drops out of the open reminders,
  // so keep track of it here.
  const [completed, setCompleted] = useState(reminder?.completed ?? false);
  const toggleCompleted = () => {
    if (!reminder) return;
    setCompleted(!completed);
    toggleReminder({ ...reminder.reminder, completed }).catch((error) => {
      setCompleted(completed);
      Alert.alert('Couldn’t Update Reminder', String(error));
    });
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
          title: reminder ? reminder.title : place.name,
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (
            <HeaderButton label="Done" bold disabled={!form.canSave || saving} onPress={save} />
          ),
        }}
      />
      <PlaceFormFields
        form={form}
        collections={collections}
        footer={
          <>
            {reminder ? (
              <Section>
                <Row
                  label={completed ? 'Mark as Incomplete' : 'Mark as Completed'}
                  onPress={toggleCompleted}
                />
                <Separator />
                <Row label="Show in Reminders" onPress={() => showInReminders(reminder.id)} />
              </Section>
            ) : null}
            <Section>
              <Row label="Directions" onPress={() => openDirections(place, place.name)} />
              <Separator />
              <Row
                label={reminder ? 'Delete Reminder' : 'Delete Place'}
                destructive
                onPress={confirmDelete}
              />
            </Section>
          </>
        }
      />
    </ScrollView>
  );
}

export function MissingPlace({ message }: { message: string }) {
  const theme = useTheme();
  return (
    <View style={[styles.missing, { backgroundColor: theme.groupedBackground }]}>
      <Stack.Screen options={{ title: '' }} />
      <Text style={{ color: theme.secondaryText }}>{message}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  missing: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
