import * as Location from 'expo-location';
import { router } from 'expo-router';
import Storage from 'expo-sqlite/kv-store';
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Keyboard,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import MapView, { Circle, Marker, type LongPressEvent, type Region } from 'react-native-maps';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon, icons } from '../../../components/Icon';
import { describeCoordinate, searchAddress, type Coordinate } from '../../../lib/geo';
import { useNowAction } from '../../../lib/nowAction';
import { useTheme, withAlpha, type Theme } from '../../../lib/theme';
import {
  REMINDERS_COLLECTION_ID,
  isActiveReminder,
  useSpaceState,
  type Collection,
} from '../../../space/store';

const ALL = 'all';
const REGION_KEY = 'spacetime.space.region.v1';
const USER_DELTA = 0.03;

/** Where the map was last left, so it opens near the user even before we have a location fix. */
function loadRegion(): Region | undefined {
  try {
    const saved = Storage.getItemSync(REGION_KEY);
    return saved ? (JSON.parse(saved) as Region) : undefined;
  } catch {
    return undefined;
  }
}

function saveRegion(region: Region) {
  Storage.setItemSync(REGION_KEY, JSON.stringify(region));
}

type SearchResult = Coordinate & { name: string; address: string };

export default function SpaceScreen() {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const mapRef = useRef<MapView>(null);
  const { collections, places } = useSpaceState();

  const [filter, setFilter] = useState<string>(ALL);
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const [result, setResult] = useState<SearchResult | null>(null);
  const [locationGranted, setLocationGranted] = useState(false);
  const [initialRegion] = useState(loadRegion);
  const [mapReady, setMapReady] = useState(false);
  const [userRegion, setUserRegion] = useState<Region | null>(null);
  const centeredOnUser = useRef(false);

  const collectionsById = useMemo(
    () => new Map(collections.map((c) => [c.id, c] as const)),
    [collections],
  );
  const counts = useMemo(() => {
    const map = new Map<string, number>();
    for (const p of places) map.set(p.collectionId, (map.get(p.collectionId) ?? 0) + 1);
    return map;
  }, [places]);
  const visiblePlaces = useMemo(
    () => (filter === ALL ? places : places.filter((p) => p.collectionId === filter)),
    [places, filter],
  );

  // Find the user once we have permission.
  useEffect(() => {
    (async () => {
      const { granted } = await Location.requestForegroundPermissionsAsync();
      setLocationGranted(granted);
      if (!granted) return;
      const position =
        (await Location.getLastKnownPositionAsync({ maxAge: 10 * 60_000 })) ??
        (await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced }));
      const { latitude, longitude } = position.coords;
      setUserRegion({ latitude, longitude, latitudeDelta: USER_DELTA, longitudeDelta: USER_DELTA });
    })().catch((error) => console.warn('[space] location failed', error));
  }, []);

  // The map ignores camera changes until it's ready, so center on the user once both are in.
  useEffect(() => {
    if (!mapReady || !userRegion || centeredOnUser.current) return;
    centeredOnUser.current = true;
    mapRef.current?.animateToRegion(userRegion, 0);
  }, [mapReady, userRegion]);

  const focusOn = (coords: Coordinate[]) => {
    if (coords.length === 0) return;
    if (coords.length === 1) {
      mapRef.current?.animateToRegion({ ...coords[0], latitudeDelta: 0.02, longitudeDelta: 0.02 });
      return;
    }
    mapRef.current?.fitToCoordinates(coords, {
      edgePadding: { top: insets.top + 140, right: 60, bottom: insets.bottom + 80, left: 60 },
      animated: true,
    });
  };

  const selectFilter = (id: string) => {
    setFilter(id);
    focusOn((id === ALL ? places : places.filter((p) => p.collectionId === id)).map(toCoordinate));
  };

  const goToMyLocation = async () => {
    const position = await Location.getCurrentPositionAsync({
      accuracy: Location.Accuracy.Balanced,
    }).catch(() => null);
    if (position) focusOn([position.coords]);
  };

  // The tab bar's floating "Here" button.
  useNowAction('space', goToMyLocation);

  const runSearch = async () => {
    Keyboard.dismiss();
    setSearching(true);
    const coord = await searchAddress(query);
    if (coord) {
      const described = await describeCoordinate(coord);
      setResult({
        ...coord,
        name: described?.name ?? query.trim(),
        address: described?.address ?? '',
      });
      focusOn([coord]);
    } else {
      setResult(null);
    }
    setSearching(false);
  };

  const addPlaceAt = (coord: Coordinate, prefill?: { name: string; address: string }) => {
    router.push({
      pathname: '/place/new',
      params: {
        latitude: String(coord.latitude),
        longitude: String(coord.longitude),
        ...(filter !== ALL ? { collectionId: filter } : {}),
        ...(prefill ?? {}),
      },
    });
  };

  const onLongPress = (e: LongPressEvent) => {
    addPlaceAt(e.nativeEvent.coordinate);
  };

  return (
    <View style={styles.container}>
      <MapView
        ref={mapRef}
        style={StyleSheet.absoluteFill}
        initialRegion={initialRegion}
        onMapReady={() => setMapReady(true)}
        onRegionChangeComplete={saveRegion}
        showsUserLocation={locationGranted}
        showsMyLocationButton={false}
        showsCompass={false}
        onLongPress={onLongPress}
        mapPadding={{ top: insets.top + 110, right: 0, bottom: 0, left: 0 }}
      >
        {visiblePlaces.map((place) => {
          const collection = collectionsById.get(place.collectionId);
          const color = collection?.color ?? theme.tint;
          return (
            <Marker
              // Including the color forces a re-render when the collection's color changes.
              key={`${place.id}:${color}`}
              coordinate={toCoordinate(place)}
              pinColor={color}
              title={place.name}
              description={place.reminder?.title || collection?.name}
              onCalloutPress={() =>
                router.push({ pathname: '/place/[id]', params: { id: place.id } })
              }
            />
          );
        })}
        {visiblePlaces.filter(isActiveReminder).map((place) => {
          const color = collectionsById.get(REMINDERS_COLLECTION_ID)?.color ?? theme.tint;
          return (
            <Circle
              key={`radius:${place.id}:${color}:${place.reminder?.radius}`}
              center={toCoordinate(place)}
              radius={place.reminder?.radius ?? 200}
              strokeColor={withAlpha(color, 0.8)}
              fillColor={withAlpha(color, 0.15)}
              strokeWidth={1.5}
            />
          );
        })}
        {result ? (
          <Marker
            coordinate={toCoordinate(result)}
            pinColor={theme.blue}
            title={result.name}
            description="Tap to save"
            onCalloutPress={() =>
              addPlaceAt(result, { name: result.name, address: result.address })
            }
          />
        ) : null}
      </MapView>

      <View style={[styles.top, { paddingTop: insets.top + 8 }]} pointerEvents="box-none">
        <View style={[styles.search, cardStyle(theme)]}>
          <Icon name={icons.search} color={theme.secondaryText} size={17} />
          <TextInput
            style={[styles.searchInput, { color: theme.text }]}
            placeholder="Search for an address"
            placeholderTextColor={theme.secondaryText}
            value={query}
            onChangeText={setQuery}
            onSubmitEditing={runSearch}
            returnKeyType="search"
            autoCorrect={false}
          />
          {searching ? <ActivityIndicator size="small" /> : null}
          {query && !searching ? (
            <Pressable
              hitSlop={8}
              onPress={() => {
                setQuery('');
                setResult(null);
              }}
            >
              <Icon name={icons.close} color={theme.tertiaryText} size={17} />
            </Pressable>
          ) : null}
        </View>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chips}
          keyboardShouldPersistTaps="handled"
        >
          <Chip
            label="All"
            count={places.length}
            selected={filter === ALL}
            onPress={() => selectFilter(ALL)}
            theme={theme}
          />
          {collections.map((collection) => (
            <Chip
              key={collection.id}
              label={collection.name}
              collection={collection}
              count={counts.get(collection.id) ?? 0}
              selected={filter === collection.id}
              onPress={() => selectFilter(collection.id)}
              theme={theme}
            />
          ))}
          <Pressable
            onPress={() => router.push('/collections')}
            style={[styles.chip, cardStyle(theme)]}
            accessibilityLabel="Manage collections"
          >
            <Icon name={icons.folder} color={theme.blue} size={15} />
            <Text style={[styles.chipLabel, { color: theme.blue }]}>Edit</Text>
          </Pressable>
        </ScrollView>
      </View>

      {result ? (
        <View style={[styles.resultCard, cardStyle(theme), { bottom: insets.bottom + 16 }]}>
          <View style={{ flex: 1 }}>
            <Text style={[styles.resultName, { color: theme.text }]} numberOfLines={1}>
              {result.name}
            </Text>
            {result.address ? (
              <Text
                style={[styles.resultAddress, { color: theme.secondaryText }]}
                numberOfLines={1}
              >
                {result.address}
              </Text>
            ) : null}
          </View>
          <Pressable
            onPress={() => addPlaceAt(result, { name: result.name, address: result.address })}
            style={[styles.saveButton, { backgroundColor: theme.blue }]}
          >
            <Text style={styles.saveLabel}>Save</Text>
          </Pressable>
        </View>
      ) : (
        <View
          style={[styles.hint, cardStyle(theme), { bottom: insets.bottom + 16 }]}
          pointerEvents="none"
        >
          <Text style={[styles.hintText, { color: theme.secondaryText }]}>
            {places.length === 0
              ? 'Long-press the map to save a place'
              : `${visiblePlaces.length} places`}
          </Text>
        </View>
      )}
    </View>
  );
}

function Chip({
  label,
  count,
  selected,
  onPress,
  theme,
  collection,
}: {
  label: string;
  count: number;
  selected: boolean;
  onPress: () => void;
  theme: Theme;
  collection?: Collection;
}) {
  const color = collection?.color ?? theme.text;
  const isReminders = collection?.id === REMINDERS_COLLECTION_ID;
  return (
    <Pressable
      onPress={onPress}
      style={[styles.chip, cardStyle(theme), selected && { backgroundColor: color }]}
      accessibilityRole="button"
      accessibilityState={{ selected }}
    >
      {collection ? (
        isReminders ? (
          <Icon name={icons.bell} color={selected ? '#fff' : color} size={13} />
        ) : (
          <View style={[styles.chipDot, { backgroundColor: selected ? '#fff' : color }]} />
        )
      ) : null}
      <Text
        style={[
          styles.chipLabel,
          { color: selected ? (collection ? '#fff' : theme.background) : theme.text },
        ]}
      >
        {label}
      </Text>
      <Text
        style={[
          styles.chipCount,
          { color: selected ? (collection ? '#fff' : theme.background) : theme.secondaryText },
        ]}
      >
        {count}
      </Text>
    </Pressable>
  );
}

function toCoordinate(p: Coordinate): Coordinate {
  return { latitude: p.latitude, longitude: p.longitude };
}

function cardStyle(theme: Theme) {
  return {
    backgroundColor: theme.overlay,
    shadowColor: theme.shadow,
    shadowOpacity: 0.15,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 2 },
    elevation: 3,
  };
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  top: { position: 'absolute', top: 0, left: 0, right: 0, gap: 10 },
  search: {
    marginHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 12,
    height: 44,
    borderRadius: 22,
  },
  searchInput: { flex: 1, fontSize: 17 },
  chips: { paddingHorizontal: 12, gap: 8, paddingBottom: 6 },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 12,
    height: 34,
    borderRadius: 17,
  },
  chipDot: { width: 10, height: 10, borderRadius: 5 },
  chipLabel: { fontSize: 15, fontWeight: '600' },
  chipCount: { fontSize: 13, fontWeight: '500' },
  resultCard: {
    position: 'absolute',
    left: 12,
    right: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 14,
    borderRadius: 16,
  },
  resultName: { fontSize: 17, fontWeight: '600' },
  resultAddress: { fontSize: 13, marginTop: 2 },
  saveButton: { paddingHorizontal: 18, paddingVertical: 9, borderRadius: 18 },
  saveLabel: { color: '#fff', fontWeight: '600', fontSize: 15 },
  hint: {
    position: 'absolute',
    alignSelf: 'center',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 16,
  },
  hintText: { fontSize: 13, fontWeight: '500' },
});
