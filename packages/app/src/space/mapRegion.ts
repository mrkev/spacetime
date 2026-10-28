import Storage from 'expo-sqlite/kv-store';

import type { SearchRegion } from '../lib/geo';

const REGION_KEY = 'spacetime.space.region.v1';

/**
 * Where the Space map was last left, so it opens near the user even before we have a location fix,
 * and so searches elsewhere prefer nearby places.
 */
export function loadMapRegion(): SearchRegion | undefined {
  try {
    const saved = Storage.getItemSync(REGION_KEY);
    return saved ? (JSON.parse(saved) as SearchRegion) : undefined;
  } catch {
    return undefined;
  }
}

export function saveMapRegion(region: SearchRegion) {
  Storage.setItemSync(REGION_KEY, JSON.stringify(region));
}
