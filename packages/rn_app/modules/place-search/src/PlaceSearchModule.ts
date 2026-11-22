import { NativeModule, requireOptionalNativeModule } from 'expo';

export type SearchRegion = {
  latitude: number;
  longitude: number;
  latitudeDelta: number;
  longitudeDelta: number;
};

export type MapItem = { name: string; address: string; latitude: number; longitude: number };

/** An autocomplete suggestion. Pass its `id` to `searchSuggestionAsync` to get places for it. */
export type SearchSuggestion = { id: string; title: string; subtitle: string };

declare class PlaceSearchModule extends NativeModule {
  /** Searches MapKit for places and addresses, preferring ones in `region`. */
  searchAsync(query: string, region: SearchRegion | null): Promise<MapItem[]>;
  /**
   * Suggestions for a partially typed query. A call that's superseded by a newer one resolves with
   * no suggestions.
   */
  completeAsync(query: string, region: SearchRegion | null): Promise<SearchSuggestion[]>;
  /** Places for a suggestion: one for a place or address, several for a query like "Coffee". */
  searchSuggestionAsync(id: string): Promise<MapItem[]>;
}

/** MapKit only exists on iOS, so this is null on other platforms. */
export default requireOptionalNativeModule<PlaceSearchModule>('PlaceSearch');
