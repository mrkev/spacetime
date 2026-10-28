import { useLocalSearchParams } from 'expo-router';

import { MissingPlace, PlaceEditor } from '../../space/PlaceEditor';
import { useSpaceState } from '../../space/store';

export default function PlaceScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const place = useSpaceState().places.find((p) => p.id === id);
  if (!place) return <MissingPlace message="This place was deleted." />;
  // Keyed so the form resets if another place is opened into the same screen.
  return <PlaceEditor key={place.id} original={{ kind: 'place', place }} />;
}
