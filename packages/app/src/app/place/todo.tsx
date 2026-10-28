import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { Segmented } from '../../components/Form';
import { MissingPlace } from '../../space/PlaceSheet';
import { findMapPlace, useMapPlaces } from '../../space/places';
import { ReminderPicker } from '../../space/ReminderPicker';
import { TodoEditor } from '../../space/TodoEditor';

type Mode = 'new' | 'existing';

const MODES: { label: string; value: Mode }[] = [
  { label: 'New Reminder', value: 'new' },
  { label: 'Existing Reminder', value: 'existing' },
];

/** A reminder at a place: a new one, or one that's already in Reminders. */
export default function AddToReminderScreen() {
  const { placeId } = useLocalSearchParams<{ placeId: string }>();
  const found = findMapPlace(useMapPlaces(), placeId);
  const [place] = useState(found);
  const [mode, setMode] = useState<Mode>('new');
  if (!place) return <MissingPlace message="This place was deleted." />;
  const header = (
    <View style={styles.modes}>
      <Segmented options={MODES} value={mode} onChange={setMode} />
    </View>
  );
  return mode === 'new' ? (
    <TodoEditor place={place} header={header} />
  ) : (
    <ReminderPicker place={place} header={header} />
  );
}

const styles = StyleSheet.create({
  modes: { marginHorizontal: 8, marginTop: 8 },
});
