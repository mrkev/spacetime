import { GlassView, isLiquidGlassAvailable } from 'expo-glass-effect';
import * as Location from 'expo-location';
import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
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
import {
  searchPlaces,
  searchSuggestion,
  suggestPlaces,
  type Coordinate,
  type PlaceResult,
  type SearchRegion,
  type SearchSuggestion,
} from '../../../lib/geo';
import { useNowAction } from '../../../lib/nowAction';
import { useTheme, withAlpha, type Theme } from '../../../lib/theme';
import { useLocationReminders } from '../../../space/locationReminders';
import { loadMapRegion, saveMapRegion } from '../../../space/mapRegion';
import { REMINDERS_COLLECTION_ID, useSpaceState, type Collection } from '../../../space/store';

const ALL = 'all';
const USER_DELTA = 0.03;
const SEARCH_HEIGHT = 46;
const liquidGlass = isLiquidGlassAvailable();

export default function SpaceScreen() {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const mapRef = useRef<MapView>(null);
  const { collections, places } = useSpaceState();
  const reminders = useLocationReminders();

  const [filter, setFilter] = useState<string>(ALL);
  const [query, setQuery] = useState('');
  const [editing, setEditing] = useState(false);
  const [suggestions, setSuggestions] = useState<SearchSuggestion[]>([]);
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState<PlaceResult[]>([]);
  const [selected, setSelected] = useState(0);
  const [notFound, setNotFound] = useState(false);
  const [locationGranted, setLocationGranted] = useState(false);
  const [initialRegion] = useState(loadMapRegion);
  // Searches prefer places in view.
  const visibleRegion = useRef<SearchRegion | undefined>(initialRegion);
  const latestQuery = useRef('');
  const [mapReady, setMapReady] = useState(false);
  const [userRegion, setUserRegion] = useState<Region | null>(null);
  const centeredOnUser = useRef(false);
  const [keyboardHeight, setKeyboardHeight] = useState(0);

  const collectionsById = new Map(collections.map((c) => [c.id, c] as const));
  const counts = new Map<string, number>([[REMINDERS_COLLECTION_ID, reminders.length]]);
  for (const p of places) counts.set(p.collectionId, (counts.get(p.collectionId) ?? 0) + 1);
  const visiblePlaces = filter === ALL ? places : places.filter((p) => p.collectionId === filter);
  const showReminders = filter === ALL || filter === REMINDERS_COLLECTION_ID;
  const visibleReminders = showReminders ? reminders : [];
  const total = places.length + reminders.length;
  const reminderColor = collectionsById.get(REMINDERS_COLLECTION_ID)?.color ?? theme.tint;

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

  // Keep the search bar above the keyboard, moving with it.
  useEffect(() => {
    const show = Keyboard.addListener('keyboardWillShow', (e) => {
      Keyboard.scheduleLayoutAnimation(e);
      setKeyboardHeight(e.endCoordinates.height);
    });
    const hide = Keyboard.addListener('keyboardWillHide', (e) => {
      Keyboard.scheduleLayoutAnimation(e);
      setKeyboardHeight(0);
    });
    return () => {
      show.remove();
      hide.remove();
    };
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
      edgePadding: { top: insets.top + 90, right: 60, bottom: insets.bottom + 110, left: 60 },
      animated: true,
    });
  };

  const selectFilter = (id: string) => {
    setFilter(id);
    focusOn(
      [
        ...(id === ALL ? places : places.filter((p) => p.collectionId === id)),
        ...(id === ALL || id === REMINDERS_COLLECTION_ID ? reminders : []),
      ].map(toCoordinate),
    );
  };

  const goToMyLocation = async () => {
    const position = await Location.getCurrentPositionAsync({
      accuracy: Location.Accuracy.Balanced,
    }).catch(() => null);
    if (position) focusOn([position.coords]);
  };

  // The tab bar's floating "Here" button.
  useNowAction('space', goToMyLocation);

  const result = results[selected] ?? null;

  const changeQuery = (text: string) => {
    setQuery(text);
    setNotFound(false);
    latestQuery.current = text;
    suggestPlaces(text, visibleRegion.current).then((next) => {
      // Typing outpaces MapKit, so only keep suggestions for what's in the field now.
      if (latestQuery.current === text) setSuggestions(next);
    });
  };

  const showResults = async (search: Promise<PlaceResult[]>) => {
    Keyboard.dismiss();
    setSearching(true);
    const found = await search;
    setSearching(false);
    setResults(found);
    setSelected(0);
    setNotFound(found.length === 0);
    focusOn(found.map(toCoordinate));
  };

  const runSearch = () => showResults(searchPlaces(query, visibleRegion.current));

  const pickSuggestion = (suggestion: SearchSuggestion) => {
    setQuery(suggestion.title);
    latestQuery.current = suggestion.title;
    showResults(searchSuggestion(suggestion));
  };

  const clearSearch = () => {
    latestQuery.current = '';
    setQuery('');
    setSuggestions([]);
    setResults([]);
    setNotFound(false);
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
        onRegionChangeComplete={(region) => {
          visibleRegion.current = region;
          saveMapRegion(region);
        }}
        onPress={Keyboard.dismiss}
        showsUserLocation={locationGranted}
        showsMyLocationButton={false}
        showsCompass={false}
        onLongPress={onLongPress}
        mapPadding={{ top: insets.top + 56, right: 0, bottom: SEARCH_HEIGHT + 8, left: 0 }}
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
              description={collection?.name}
              onCalloutPress={() =>
                router.push({ pathname: '/place/[id]', params: { id: place.id } })
              }
            />
          );
        })}
        {visibleReminders.map((reminder) => (
          <Marker
            key={`reminder:${reminder.id}:${reminderColor}`}
            coordinate={toCoordinate(reminder)}
            pinColor={reminderColor}
            title={reminder.title}
            description={reminder.placeName}
            onCalloutPress={() =>
              router.push({ pathname: '/place/reminder/[id]', params: { id: reminder.id } })
            }
          />
        ))}
        {visibleReminders.map((reminder) => (
          <Circle
            key={`radius:${reminder.id}:${reminderColor}:${reminder.radius}`}
            center={toCoordinate(reminder)}
            radius={reminder.radius}
            strokeColor={withAlpha(reminderColor, 0.8)}
            fillColor={withAlpha(reminderColor, 0.15)}
            strokeWidth={1.5}
          />
        ))}
        {results.map((found, i) => (
          <Marker
            key={`result:${i}:${found.latitude},${found.longitude}`}
            coordinate={toCoordinate(found)}
            pinColor={theme.blue}
            title={found.name}
            description="Tap to save"
            onPress={() => setSelected(i)}
            onCalloutPress={() => addPlaceAt(found, { name: found.name, address: found.address })}
          />
        ))}
      </MapView>

      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.top}
        contentContainerStyle={[styles.chips, { paddingTop: insets.top + 8 }]}
        keyboardShouldPersistTaps="handled"
      >
        <Chip
          label="All"
          count={total}
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

      <View
        style={[styles.bottom, { bottom: Math.max(insets.bottom, keyboardHeight) + 8 }]}
        pointerEvents="box-none"
      >
        {editing && suggestions.length > 0 ? (
          <Surface style={styles.suggestions}>
            <ScrollView style={styles.suggestionList} keyboardShouldPersistTaps="handled">
              {suggestions.map((suggestion, i) => (
                <Pressable
                  key={suggestion.id}
                  onPress={() => pickSuggestion(suggestion)}
                  style={({ pressed }) => [
                    styles.suggestion,
                    i > 0 && {
                      borderTopColor: theme.separator,
                      borderTopWidth: StyleSheet.hairlineWidth,
                    },
                    pressed && { backgroundColor: theme.fill },
                  ]}
                >
                  <Text style={[styles.suggestionTitle, { color: theme.text }]} numberOfLines={1}>
                    {suggestion.title}
                  </Text>
                  {suggestion.subtitle ? (
                    <Text
                      style={[styles.suggestionSubtitle, { color: theme.secondaryText }]}
                      numberOfLines={1}
                    >
                      {suggestion.subtitle}
                    </Text>
                  ) : null}
                </Pressable>
              ))}
            </ScrollView>
          </Surface>
        ) : result ? (
          <Surface style={styles.resultCard}>
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
          </Surface>
        ) : notFound || total === 0 ? (
          <Surface style={styles.hint} pointerEvents="none">
            <Text style={[styles.hintText, { color: theme.secondaryText }]}>
              {notFound ? `No results for “${query.trim()}”` : 'Long-press the map to save a place'}
            </Text>
          </Surface>
        ) : null}

        <Surface style={styles.search}>
          <Icon name={icons.search} color={theme.secondaryText} size={17} />
          <TextInput
            style={[styles.searchInput, { color: theme.text }]}
            placeholder="Search for a place or address"
            placeholderTextColor={theme.secondaryText}
            value={query}
            onChangeText={changeQuery}
            onFocus={() => {
              setEditing(true);
              changeQuery(query);
            }}
            onBlur={() => setEditing(false)}
            onSubmitEditing={runSearch}
            returnKeyType="search"
            autoCorrect={false}
          />
          {searching ? <ActivityIndicator size="small" /> : null}
          {query && !searching ? (
            <Pressable hitSlop={8} onPress={clearSearch}>
              <Icon name={icons.close} color={theme.tertiaryText} size={17} />
            </Pressable>
          ) : null}
        </Surface>
      </View>
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

/** A floating panel: Liquid Glass where available, otherwise an opaque card. */
function Surface({ style, ...props }: React.ComponentProps<typeof View>) {
  const theme = useTheme();
  if (liquidGlass) return <GlassView style={style} {...props} />;
  return <View style={[style, cardStyle(theme)]} {...props} />;
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
  top: { position: 'absolute', top: 0, left: 0, right: 0, flexGrow: 0 },
  bottom: { position: 'absolute', left: 20, right: 20, gap: 8 },
  search: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 16,
    height: SEARCH_HEIGHT,
    borderRadius: SEARCH_HEIGHT / 2,
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
  suggestions: { maxHeight: 320, borderRadius: 22 },
  suggestionList: { borderRadius: 22 },
  suggestion: { paddingHorizontal: 16, paddingVertical: 10 },
  suggestionTitle: { fontSize: 16, fontWeight: '500' },
  suggestionSubtitle: { fontSize: 13, marginTop: 2 },
  resultCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 14,
    borderRadius: 22,
  },
  resultName: { fontSize: 17, fontWeight: '600' },
  resultAddress: { fontSize: 13, marginTop: 2 },
  saveButton: { paddingHorizontal: 18, paddingVertical: 9, borderRadius: 18 },
  saveLabel: { color: '#fff', fontWeight: '600', fontSize: 15 },
  hint: {
    alignSelf: 'center',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 16,
  },
  hintText: { fontSize: 13, fontWeight: '500' },
});
