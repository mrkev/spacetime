import type { EventLocation } from 'expo-calendar';
import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { Field, Row, Section, Separator } from '../../components/Form';
import { HeaderButton } from '../../components/HeaderButton';
import { Icon, icons } from '../../components/Icon';
import {
  distanceMeters,
  searchPlaces,
  searchSuggestion,
  suggestPlaces,
  type PlaceResult,
  type SearchSuggestion,
} from '../../lib/geo';
import { useTheme } from '../../lib/theme';
import { loadMapRegion } from '../../space/mapRegion';
import {
  LINK_RADIUS,
  eventLocation,
  pinColor,
  placeCollections,
  useMapPlaces,
} from '../../space/places';
import { useSpaceState } from '../../space/store';
import { occurrence, type Span } from '../../time/actions';
import { useCalendar, type CalendarEvent } from '../../time/CalendarProvider';

/** Picks the place for an event: a saved one, or any place or address from search. */
export default function EventPlaceScreen() {
  const { key, start, span } = useLocalSearchParams<{ key: string; start: string; span: Span }>();
  const theme = useTheme();
  const { getDay, refresh } = useCalendar();
  const { collections } = useSpaceState();
  const mapPlaces = useMapPlaces();
  const found = getDay(new Date(start))?.events.find((e) => e.key === key) ?? null;
  // Saving reloads the calendar, so hold on to the event.
  const [event] = useState<CalendarEvent | null>(found);

  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<SearchSuggestion[]>([]);
  const [searching, setSearching] = useState(false);
  const [saving, setSaving] = useState(false);
  const latestQuery = useRef('');
  const [near] = useState(loadMapRegion);

  if (!event) {
    return (
      <View style={[styles.missing, { backgroundColor: theme.groupedBackground }]}>
        <Stack.Screen options={{ title: '' }} />
        <Text style={{ color: theme.secondaryText }}>This event was deleted.</Text>
      </View>
    );
  }

  const saved = mapPlaces.filter((p) => p.saved).sort((a, b) => a.name.localeCompare(b.name));
  const isCurrent = (p: { latitude: number; longitude: number }) =>
    !!event.place && distanceMeters(event.place, p) <= LINK_RADIUS;

  const save = async (location: EventLocation | null) => {
    if (saving) return;
    setSaving(true);
    try {
      await occurrence(event, span === 'future' ? 'future' : 'this').setStructuredLocation(
        location,
      );
      refresh();
      router.back();
    } catch (error) {
      setSaving(false);
      Alert.alert('Couldn’t Save Event', String(error));
    }
  };

  const changeQuery = (text: string) => {
    setQuery(text);
    latestQuery.current = text;
    suggestPlaces(text, near).then((next) => {
      if (latestQuery.current === text) setSuggestions(next);
    });
  };

  const pickResult = async (search: Promise<PlaceResult[]>) => {
    setSearching(true);
    const [result] = await search;
    setSearching(false);
    if (!result) {
      Alert.alert('Not Found', 'Try a different search.');
      return;
    }
    save(eventLocation(result));
  };

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      style={{ backgroundColor: theme.groupedBackground }}
      contentContainerStyle={{ paddingBottom: 40 }}
      keyboardShouldPersistTaps="handled"
      automaticallyAdjustKeyboardInsets
    >
      <Stack.Screen
        options={{
          title: event.title,
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (saving ? <ActivityIndicator /> : null),
        }}
      />

      <Section footer={event.location ? `Now: ${event.location.replace(/\n/g, ', ')}` : undefined}>
        <View style={styles.searchRow}>
          <Icon name={icons.search} color={theme.secondaryText} size={16} />
          <Field
            style={styles.searchField}
            placeholder="Search for a place or address"
            value={query}
            onChangeText={changeQuery}
            onSubmitEditing={() => pickResult(searchPlaces(query, near))}
            returnKeyType="search"
            autoCorrect={false}
            autoFocus={saved.length === 0}
          />
          {searching ? <ActivityIndicator /> : null}
        </View>
        {query
          ? suggestions.map((suggestion) => (
              <View key={suggestion.id}>
                <Separator />
                <PlaceRow
                  title={suggestion.title}
                  subtitle={suggestion.subtitle}
                  onPress={() => pickResult(searchSuggestion(suggestion))}
                />
              </View>
            ))
          : null}
      </Section>

      {!query && saved.length > 0 ? (
        <Section title="Saved Places">
          {saved.map((place, i) => (
            <View key={place.id}>
              {i > 0 ? <Separator /> : null}
              <PlaceRow
                title={place.name}
                subtitle={placeCollections(place, collections)
                  .map((c) => c.name)
                  .join(', ')}
                color={pinColor(place, collections, theme.tint)}
                checked={isCurrent(place)}
                onPress={() => save(eventLocation(place))}
              />
            </View>
          ))}
        </Section>
      ) : null}

      {!query && event.location ? (
        <Section>
          <Row label="Remove Location" destructive onPress={() => save(null)} />
        </Section>
      ) : null}
    </ScrollView>
  );
}

function PlaceRow({
  title,
  subtitle,
  color,
  checked = false,
  onPress,
}: {
  title: string;
  subtitle?: string;
  color?: string;
  checked?: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.placeRow, pressed && { backgroundColor: theme.fill }]}
      accessibilityRole="button"
      accessibilityState={{ selected: checked }}
    >
      {color ? <View style={[styles.dot, { backgroundColor: color }]} /> : null}
      <View style={styles.placeText}>
        <Text style={[styles.placeTitle, { color: theme.text }]} numberOfLines={1}>
          {title}
        </Text>
        {subtitle ? (
          <Text style={[styles.placeSubtitle, { color: theme.secondaryText }]} numberOfLines={1}>
            {subtitle}
          </Text>
        ) : null}
      </View>
      {checked ? <Icon name={icons.check} color={theme.blue} size={16} weight="semibold" /> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  missing: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  searchRow: { flexDirection: 'row', alignItems: 'center', paddingLeft: 14, paddingRight: 12 },
  searchField: { flex: 1, paddingHorizontal: 8 },
  placeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    minHeight: 44,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  dot: { width: 12, height: 12, borderRadius: 6 },
  placeText: { flex: 1 },
  placeTitle: { fontSize: 17 },
  placeSubtitle: { fontSize: 13, marginTop: 1 },
});
