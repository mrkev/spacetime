import {
  Button,
  Divider,
  HStack,
  Host,
  Image,
  Label,
  List,
  Menu,
  Section,
  Spacer,
  Text,
  VStack,
} from '@expo/ui/swift-ui';
import {
  buttonStyle,
  deleteDisabled,
  font,
  foregroundStyle,
  lineLimit,
  listStyle,
} from '@expo/ui/swift-ui/modifiers';
import { Stack, router } from 'expo-router';
import { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text as RNText, View } from 'react-native';

import { Icon, icons } from '../components/Icon';
import { openDirections } from '../lib/geo';
import { useTheme } from '../lib/theme';
import { useTimeActions } from '../time/actions';
import { UPCOMING_DAYS, useCalendar } from '../time/CalendarProvider';
import { describeTrigger, type LocationReminder } from './locationReminders';
import {
  addToCollection,
  describeEventTime,
  eventLocation,
  findMapPlace,
  placeCollections,
  setCollections,
  useMapPlaces,
  type MapPlace,
} from './places';
import { REMINDERS_COLLECTION_ID, deletePlace, useSpaceState } from './store';

const secondary = foregroundStyle({ type: 'hierarchical', style: 'secondary' });

/**
 * A place's details, in a sheet over the map: its collections (sorted, since the first colors its
 * pin), its todos, and its upcoming events.
 */
export function PlaceSheet({ id }: { id: string }) {
  const theme = useTheme();
  const { collections } = useSpaceState();
  const { toggleReminder, refresh } = useCalendar();
  const { openEvent, createEvent } = useTimeActions();
  const mapPlaces = useMapPlaces();

  // A place's ID changes when it's saved or unsaved, so keep track of where it was. And when its
  // last todo is checked off an unsaved place is gone, but keep showing it so that can be undone.
  const [last, setLast] = useState<MapPlace | null>(null);
  const live = findMapPlace(mapPlaces, id, last ?? undefined);
  if (live && (!last || describe(live) !== describe(last))) setLast(live);
  // Todos checked off here, which drop out of the open reminders.
  const [done, setDone] = useState<LocationReminder[]>([]);

  const place =
    live ?? (last && { ...last, saved: null, collectionIds: [], todos: [], events: [] });
  if (!place) return <MissingPlace message="This place was deleted." />;

  const inCollections = placeCollections(place, collections);
  const otherCollections = collections.filter(
    (c) => c.id !== REMINDERS_COLLECTION_ID && !place.collectionIds.includes(c.id),
  );
  const todos = [...place.todos, ...done.filter((d) => !place.todos.some((t) => t.id === d.id))];
  const collectionsFooter =
    inCollections.length > 1
      ? 'The first collection colors the pin. Hold and drag to reorder.'
      : inCollections.length === 0
        ? 'Not saved. Without a collection, this place is on the map only while it has todos or upcoming events.'
        : null;
  const isDone = (todo: LocationReminder) => !place.todos.some((t) => t.id === todo.id);

  const moveCollections = (from: number[], to: number) => {
    const ids = inCollections.map((c) => c.id);
    const moving = from.map((i) => ids[i]);
    const before = ids.slice(0, to).filter((c) => !moving.includes(c));
    const after = ids.slice(to).filter((c) => !moving.includes(c));
    setCollections(place, [...before, ...moving, ...after]);
  };

  const removeCollections = (indices: number[]) => {
    setCollections(
      place,
      inCollections.filter((_, i) => !indices.includes(i)).map((c) => c.id),
    );
  };

  const toggleTodo = (todo: LocationReminder) => {
    const completed = isDone(todo);
    if (!completed) setDone((d) => [...d.filter((t) => t.id !== todo.id), todo]);
    toggleReminder({ ...todo.reminder, completed }).catch((error) =>
      Alert.alert('Couldn’t Update Todo', String(error)),
    );
  };

  const deleteTodos = (indices: number[]) => {
    const removed = todos.filter((_, i) => indices.includes(i));
    setDone((d) => d.filter((t) => !removed.some((r) => r.id === t.id)));
    Promise.all(removed.map((todo) => todo.reminder.source.delete()))
      .catch((error) => Alert.alert('Couldn’t Delete Todo', String(error)))
      .finally(refresh);
  };

  const confirmDelete = () => {
    const openTodos = place.todos.length;
    Alert.alert(
      `Delete “${place.name}”?`,
      openTodos > 0
        ? `This also deletes its ${openTodos === 1 ? 'todo' : `${openTodos} todos`}.`
        : undefined,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            router.back();
            if (place.saved) deletePlace(place.saved.id);
            Promise.all(place.todos.map((todo) => todo.reminder.source.delete()))
              .catch((error) => Alert.alert('Couldn’t Delete Todos', String(error)))
              .finally(refresh);
          },
        },
      ],
    );
  };

  return (
    <View style={[styles.container, { backgroundColor: theme.groupedBackground }]}>
      <Stack.Screen options={{ headerShown: false }} />
      <View style={styles.header}>
        <View style={styles.titles}>
          <RNText style={[styles.name, { color: theme.text }]} numberOfLines={2}>
            {place.name}
          </RNText>
          {place.address ? (
            <RNText style={[styles.address, { color: theme.secondaryText }]} numberOfLines={2}>
              {place.address}
            </RNText>
          ) : null}
        </View>
        <Pressable
          onPress={() => router.back()}
          hitSlop={8}
          style={[styles.close, { backgroundColor: theme.fill }]}
          accessibilityRole="button"
          accessibilityLabel="Close"
        >
          <Icon name={icons.xmark} color={theme.secondaryText} size={14} weight="bold" />
        </Pressable>
      </View>

      <Host style={styles.list}>
        <List modifiers={[listStyle('insetGrouped')]}>
          <Section
            title="Collections"
            footer={collectionsFooter ? <Text>{collectionsFooter}</Text> : undefined}
          >
            <List.ForEach
              data={inCollections}
              keyExtractor={(collection) => collection.id}
              onMove={moveCollections}
              onDelete={removeCollections}
              recycling={false}
            >
              {({ item }) => (
                <Label
                  title={item.name}
                  icon={<Image systemName="circle.fill" color={item.color} size={14} />}
                  // Taking a place without todos out of its last collection would delete it.
                  modifiers={[
                    deleteDisabled(inCollections.length === 1 && place.todos.length === 0),
                  ]}
                />
              )}
            </List.ForEach>
            {otherCollections.length > 0 ? (
              <Menu label="Add to Collection" systemImage="plus.circle">
                {otherCollections.map((collection) => (
                  <Button
                    key={collection.id}
                    label={collection.name}
                    onPress={() => addToCollection(place, collection.id)}
                  />
                ))}
                <Divider />
                <Button
                  label="New Collection…"
                  systemImage="plus"
                  onPress={() =>
                    router.push({
                      pathname: '/collections/[id]',
                      params: { id: 'new', placeId: place.id },
                    })
                  }
                />
              </Menu>
            ) : (
              <Button
                label="New Collection…"
                systemImage="plus.circle"
                onPress={() =>
                  router.push({
                    pathname: '/collections/[id]',
                    params: { id: 'new', placeId: place.id },
                  })
                }
              />
            )}
          </Section>

          <Section title="Todos">
            <List.ForEach
              data={todos}
              keyExtractor={(todo) => todo.id}
              onDelete={deleteTodos}
              recycling={false}
            >
              {({ item }) => (
                <HStack spacing={12}>
                  <Button onPress={() => toggleTodo(item)} modifiers={[buttonStyle('plain')]}>
                    <Image
                      systemName={isDone(item) ? 'checkmark.circle.fill' : 'circle'}
                      color={isDone(item) ? theme.blue : theme.secondaryText}
                      size={22}
                    />
                  </Button>
                  <Button
                    onPress={() =>
                      router.push({ pathname: '/place/reminder/[id]', params: { id: item.id } })
                    }
                    modifiers={[buttonStyle('plain')]}
                  >
                    <HStack>
                      <VStack alignment="leading" spacing={2}>
                        <Text modifiers={[lineLimit(2), ...(isDone(item) ? [secondary] : [])]}>
                          {item.title}
                        </Text>
                        <Text modifiers={[font({ textStyle: 'subheadline' }), secondary]}>
                          {describeTrigger(item)}
                        </Text>
                      </VStack>
                      <Spacer />
                    </HStack>
                  </Button>
                </HStack>
              )}
            </List.ForEach>
            <Button
              label="Add to Reminder"
              systemImage="plus.circle"
              onPress={() =>
                router.push({ pathname: '/place/todo', params: { placeId: place.id } })
              }
            />
          </Section>

          <Section
            title="Events"
            footer={<Text>{`Events here in the next ${UPCOMING_DAYS} days.`}</Text>}
          >
            {place.events.map((event) => (
              <Button
                key={event.key}
                onPress={() => openEvent(event)}
                modifiers={[buttonStyle('plain')]}
              >
                <HStack spacing={12}>
                  <Image systemName="circle.fill" color={event.color} size={12} />
                  <VStack alignment="leading" spacing={2}>
                    <Text modifiers={[lineLimit(2)]}>{event.title}</Text>
                    <Text modifiers={[font({ textStyle: 'subheadline' }), secondary]}>
                      {describeEventTime(event)}
                    </Text>
                  </VStack>
                  <Spacer />
                </HStack>
              </Button>
            ))}
            <Menu label="Add to Event" systemImage="plus.circle">
              <Button
                label="New Event…"
                systemImage="plus"
                onPress={() => createEvent(undefined, eventLocation(place))}
              />
              <Button
                label="Existing Event…"
                systemImage="calendar"
                onPress={() =>
                  router.push({ pathname: '/place/event', params: { placeId: place.id } })
                }
              />
            </Menu>
          </Section>

          {place.saved?.notes ? (
            <Section title="Notes">
              <Text>{place.saved.notes}</Text>
            </Section>
          ) : null}

          <Section>
            <Button
              label="Directions"
              systemImage="arrow.triangle.turn.up.right.diamond"
              onPress={() => openDirections(place, place.name)}
            />
            {place.saved ? (
              <Button
                label="Edit Place"
                systemImage="pencil"
                onPress={() =>
                  router.push({ pathname: '/place/edit/[id]', params: { id: place.id } })
                }
              />
            ) : null}
            {place.saved || place.todos.length > 0 ? (
              <Button
                label="Delete Place"
                systemImage="trash"
                role="destructive"
                onPress={confirmDelete}
              />
            ) : null}
          </Section>
        </List>
      </Host>
    </View>
  );
}

function describe(place: MapPlace) {
  return [place.id, place.name, place.address, place.latitude, place.longitude].join('|');
}

export function MissingPlace({ message }: { message: string }) {
  const theme = useTheme();
  return (
    <View style={[styles.missing, { backgroundColor: theme.groupedBackground }]}>
      <Stack.Screen options={{ title: '' }} />
      <RNText style={{ color: theme.secondaryText }}>{message}</RNText>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
    paddingHorizontal: 20,
    paddingTop: 22,
    paddingBottom: 4,
  },
  titles: { flex: 1 },
  name: { fontSize: 24, fontWeight: '700' },
  address: { fontSize: 15, marginTop: 2 },
  close: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
  },
  list: { flex: 1 },
  missing: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
