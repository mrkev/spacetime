import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';

import { MissingPlace } from '../../space/PlaceSheet';
import { findMapPlace, useMapPlaces } from '../../space/places';
import { TodoEditor } from '../../space/TodoEditor';

/** A new todo at a place. */
export default function NewTodoScreen() {
  const { placeId } = useLocalSearchParams<{ placeId: string }>();
  const found = findMapPlace(useMapPlaces(), placeId);
  const [place] = useState(found);
  if (!place) return <MissingPlace message="This place was deleted." />;
  return <TodoEditor place={place} />;
}
