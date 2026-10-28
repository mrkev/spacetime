import * as Location from 'expo-location';
import { Linking, Platform } from 'react-native';

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

export async function searchAddress(query: string): Promise<Coordinate | null> {
  const trimmed = query.trim();
  if (!trimmed) return null;
  try {
    const [result] = await Location.geocodeAsync(trimmed);
    return result ? { latitude: result.latitude, longitude: result.longitude } : null;
  } catch {
    return null;
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
