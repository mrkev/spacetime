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
import MapView, {
  Circle,
  Marker,
  type LongPressEvent,
  type MapPressEvent,
  type Region,
} from 'react-native-maps';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon, icons, type IconName } from '../../../components/Icon';
import { formatRelativeDay } from '../../../lib/dates';
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
import { PIN_OFFSET, useTheme, withAlpha, type Theme } from '../../../lib/theme';
import { loadMapRegion, saveMapRegion } from '../../../space/mapRegion';
import {
  isInCollection,
  pinColor,
  placeCollections,
  useMapPlaces,
  type MapPlace,
} from '../../../space/places';
import { REMINDERS_COLLECTION_ID, useSpaceState, type Collection } from '../../../space/store';

const ALL = 'all';
/** The filter for places with upcoming events. */
const UPCOMING = 'upcoming';
const USER_DELTA = 0.03;
const SEARCH_HEIGHT = 46;
/**
 * Where a selected pin's balloon is drawn, around its tip. MapKit draws it larger than the pin's
 * view, which only takes taps at the base.
 */
const SELECTED_PIN = { halfWidth: 28, above: 72, below: 8 };
/** A tap within this long (ms) of a pin being selected is the tap that selected it. */
const SELECT_GRACE = 500;
const liquidGlass = isLiquidGlassAvailable();

export default function SpaceScreen() {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const mapRef = useRef<MapView>(null);
  const { collections } = useSpaceState();
  const mapPlaces = useMapPlaces();

  const [filter, setFilter] = useState<string>(ALL);
  const [query, setQuery] = useState('');
  const [editing, setEditing] = useState(false);
  const [suggestions, setSuggestions] = useState<SearchSuggestion[]>([]);
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState<PlaceResult[]>([]);
  const [selected, setSelected] = useState(0);
  // The place whose pin was tapped once. Tapping it again opens it.
  const [selectedPlaceId, setSelectedPlaceId] = useState<string | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [locationGranted, setLocationGranted] = useState(false);
  const [initialRegion] = useState(loadMapRegion);
  // Searches prefer places in view.
  const visibleRegion = useRef<SearchRegion | undefined>(initialRegion);
  const latestQuery = useRef('');
  const [mapReady, setMapReady] = useState(false);
  const [userRegion, setUserRegion] = useState<Region | null>(null);
  const centeredOnUser = useRef(false);
  const selectedAt = useRef(0);
  const [keyboardHeight, setKeyboardHeight] = useState(0);

  const inFilter = (id: string) =>
    id === ALL
      ? mapPlaces
      : id === UPCOMING
        ? mapPlaces.filter((p) => p.events.length > 0)
        : mapPlaces.filter((p) => isInCollection(p, id));
  const visiblePlaces = inFilter(filter);
  const total = mapPlaces.length;
  const reminderColor =
    collections.find((c) => c.id === REMINDERS_COLLECTION_ID)?.color ?? theme.tint;
  const selectedPlace = visiblePlaces.find((p) => p.id === selectedPlaceId) ?? null;
  // Todos' geofences, for the selected place or when looking at all of them.
  const fences = (
    filter === REMINDERS_COLLECTION_ID ? visiblePlaces : selectedPlace ? [selectedPlace] : []
  ).flatMap((p) => p.todos);

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
    focusOn(inFilter(id).map(toCoordinate));
  };

  const openPlace = (place: MapPlace) => {
    // Keep the pin in view above the sheet, which covers the bottom half.
    const region = visibleRegion.current;
    if (region) {
      mapRef.current?.animateToRegion({
        ...region,
        latitude: place.latitude - region.latitudeDelta / 4,
        longitude: place.longitude,
      });
    }
    router.push({ pathname: '/place/[id]', params: { id: place.id } });
  };

  // MapKit selects a pin on the first tap. It doesn't report taps on a pin that's already
  // selected, so check whether a tap on the map landed on the selected one.
  const pressMap = async (e: MapPressEvent) => {
    Keyboard.dismiss();
    const place = selectedPlace;
    if (!place || e.timeStamp - selectedAt.current < SELECT_GRACE) return;
    const { x, y } = e.nativeEvent.position;
    const tip = await mapRef.current?.pointForCoordinate(place);
    if (
      tip &&
      Math.abs(x - tip.x) <= SELECTED_PIN.halfWidth &&
      y >= tip.y - SELECTED_PIN.above &&
      y <= tip.y + SELECTED_PIN.below
    ) {
      openPlace(place);
    }
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
        ...(filter !== ALL && filter !== UPCOMING ? { collectionId: filter } : {}),
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
        onPress={pressMap}
        showsUserLocation={locationGranted}
        showsMyLocationButton={false}
        showsCompass={false}
        onLongPress={onLongPress}
        mapPadding={{ top: insets.top + 56, right: 0, bottom: SEARCH_HEIGHT + 8, left: 0 }}
      >
        {visiblePlaces.map((place) => {
          const color = pinColor(place, collections, theme.tint);
          return (
            <Marker
              // Including the color forces a re-render when the collection's color changes.
              key={`${place.id}:${color}`}
              coordinate={toCoordinate(place)}
              pinColor={color}
              centerOffset={PIN_OFFSET}
              accessibilityLabel={place.name}
              // Without a title, selecting it doesn't open a callout.
              onSelect={(e) => {
                selectedAt.current = e.timeStamp;
                setSelectedPlaceId(place.id);
              }}
              onDeselect={() => setSelectedPlaceId((id) => (id === place.id ? null : id))}
            />
          );
        })}
        {fences.map((todo) => (
          <Circle
            key={`radius:${todo.id}:${reminderColor}:${todo.radius}`}
            center={toCoordinate(todo)}
            radius={todo.radius}
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
            centerOffset={PIN_OFFSET}
            title={found.name}
            description="Tap to save"
            onSelect={() => {
              setSelected(i);
              setSelectedPlaceId(null);
            }}
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
        <Chip
          label="Upcoming"
          icon={icons.calendar}
          color={theme.tint}
          count={inFilter(UPCOMING).length}
          selected={filter === UPCOMING}
          onPress={() => selectFilter(UPCOMING)}
          theme={theme}
        />
        {collections.map((collection) => (
          <Chip
            key={collection.id}
            label={collection.name}
            collection={collection}
            count={inFilter(collection.id).length}
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
        ) : selectedPlace ? (
          <Pressable onPress={() => openPlace(selectedPlace)}>
            <Surface style={styles.resultCard}>
              <View style={{ flex: 1 }}>
                <Text style={[styles.resultName, { color: theme.text }]} numberOfLines={1}>
                  {selectedPlace.name}
                </Text>
                <Text
                  style={[styles.resultAddress, { color: theme.secondaryText }]}
                  numberOfLines={1}
                >
                  {describePlace(selectedPlace, collections)}
                </Text>
              </View>
              <Icon name={icons.chevronRight} color={theme.tertiaryText} size={14} />
            </Surface>
          </Pressable>
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
  ...props
}: {
  label: string;
  count: number;
  selected: boolean;
  onPress: () => void;
  theme: Theme;
  collection?: Collection;
  /** For a filter that isn't a collection. */
  color?: string;
  icon?: IconName;
}) {
  const color = collection?.color ?? props.color ?? theme.text;
  const icon = collection?.id === REMINDERS_COLLECTION_ID ? icons.bell : props.icon;
  const colored = !!collection || !!props.color;
  return (
    <Pressable
      onPress={onPress}
      style={[styles.chip, cardStyle(theme), selected && { backgroundColor: color }]}
      accessibilityRole="button"
      accessibilityState={{ selected }}
    >
      {icon ? (
        <Icon name={icon} color={selected ? '#fff' : color} size={13} />
      ) : collection ? (
        <View style={[styles.chipDot, { backgroundColor: selected ? '#fff' : color }]} />
      ) : null}
      <Text
        style={[
          styles.chipLabel,
          { color: selected ? (colored ? '#fff' : theme.background) : theme.text },
        ]}
      >
        {label}
      </Text>
      <Text
        style={[
          styles.chipCount,
          { color: selected ? (colored ? '#fff' : theme.background) : theme.secondaryText },
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

/**
 * Its collections, its next event, and how many todos it has, e.g.
 * "Favorites, Food · Dinner, Tomorrow · 2 todos".
 */
function describePlace(place: MapPlace, collections: Collection[]): string {
  const names = placeCollections(place, collections).map((c) => c.name);
  const todos = place.todos.length;
  const [next] = place.events;
  return [
    names.length > 0 ? names.join(', ') : 'Not saved',
    next ? `${next.title}, ${formatRelativeDay(next.start)}` : null,
    todos > 0 ? `${todos} ${todos === 1 ? 'todo' : 'todos'}` : null,
  ]
    .filter(Boolean)
    .join(' · ');
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
