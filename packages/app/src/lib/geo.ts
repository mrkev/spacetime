import * as Location from 'expo-location';
import { Linking, Platform } from 'react-native';

import PlaceSearch, { type SearchSuggestion } from '../../modules/place-search';

export type Coordinate = { latitude: number; longitude: number };

/** Great-circle distance in meters. */
export function distanceMeters(a: Coordinate, b: Coordinate): number {
  const R = 6_371_000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

export function formatDistance(meters: number): string {
  if (meters < 1000) return `${Math.round(meters)} m`;
  return `${(meters / 1000).toFixed(meters < 10_000 ? 1 : 0)} km`;
}

export type ResolvedAddress = { name: string; address: string };

/** Best-effort reverse geocode into a short name and a one-line address. */
export async function describeCoordinate(coord: Coordinate): Promise<ResolvedAddress | null> {
  try {
    const [result] = await Location.reverseGeocodeAsync(coord);
    if (!result) return null;
    const street = [result.streetNumber, result.street].filter(Boolean).join(' ');
    const address =
      result.formattedAddress ??
      [street, result.city, result.region, result.postalCode].filter(Boolean).join(', ');
    const name = result.name ?? (street || result.city || 'Dropped Pin');
    return { name, address };
  } catch {
    return null;
  }
}

export type SearchRegion = Coordinate & { latitudeDelta: number; longitudeDelta: number };

/** A place found by search, with its name and one-line address. */
export type PlaceResult = Coordinate & ResolvedAddress;

export type { SearchSuggestion };

/**
 * Searches for places and addresses, preferring ones in `near`. iOS searches Apple Maps; elsewhere
 * this falls back to the system geocoder, which only understands addresses.
 */
export async function searchPlaces(
  query: string,
  near?: SearchRegion | null,
): Promise<PlaceResult[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];
  try {
    if (PlaceSearch) return await PlaceSearch.searchAsync(trimmed, near ?? null);
    const [result] = await Location.geocodeAsync(trimmed);
    if (!result) return [];
    const coord = { latitude: result.latitude, longitude: result.longitude };
    const described = await describeCoordinate(coord);
    return [{ ...coord, name: described?.name ?? trimmed, address: described?.address ?? '' }];
  } catch (error) {
    console.warn('[geo] search failed', error);
    return [];
  }
}

/** Autocomplete suggestions for a partially typed query. Always empty off iOS. */
export async function suggestPlaces(
  query: string,
  near?: SearchRegion | null,
): Promise<SearchSuggestion[]> {
  if (!PlaceSearch) return [];
  try {
    return await PlaceSearch.completeAsync(query.trim(), near ?? null);
  } catch {
    return [];
  }
}

/** Places for a suggestion from `suggestPlaces`: several for a query like "Coffee". */
export async function searchSuggestion(suggestion: SearchSuggestion): Promise<PlaceResult[]> {
  if (!PlaceSearch) return [];
  try {
    return await PlaceSearch.searchSuggestionAsync(suggestion.id);
  } catch (error) {
    console.warn('[geo] suggestion search failed', error);
    return [];
  }
}

export function openDirections(coord: Coordinate, label: string) {
  const { latitude, longitude } = coord;
  const encoded = encodeURIComponent(label);
  const url =
    Platform.OS === 'ios'
      ? `maps://?daddr=${latitude},${longitude}&q=${encoded}`
      : `geo:${latitude},${longitude}?q=${latitude},${longitude}(${encoded})`;
  Linking.openURL(url).catch(() => {});
}
