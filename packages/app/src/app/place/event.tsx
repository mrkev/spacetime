import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';

import { EventPicker } from '../../space/EventPicker';
import { MissingPlace } from '../../space/PlaceSheet';
import { findMapPlace, useMapPlaces } from '../../space/places';

/** An existing event to be at a place. */
export default function AddToEventScreen() {
  const { placeId } = useLocalSearchParams<{ placeId: string }>();
  const found = findMapPlace(useMapPlaces(), placeId);
  const [place] = useState(found);
  if (!place) return <MissingPlace message="This place was deleted." />;
  return <EventPicker place={place} />;
}
