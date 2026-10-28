import { useLocalSearchParams } from 'expo-router';

import { PlaceSheet } from '../../space/PlaceSheet';

export default function PlaceScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <PlaceSheet id={id} />;
}
