import { Stack, router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, ScrollView, View } from 'react-native';

import { PickRow, SearchRow, Section, Separator } from '../components/Form';
import { HeaderButton } from '../components/HeaderButton';
import { useTheme } from '../lib/theme';
import { chooseSpan, occurrence } from '../time/actions';
import { UPCOMING_DAYS, useCalendar, type CalendarEvent } from '../time/CalendarProvider';
import { describeEventTime, eventLocation, parseLocationTitle, type MapPlace } from './places';

/**
 * Picks an upcoming event to be at a place. It lists the ones without a location; search finds ones
 * with a location too, which then move here.
 */
export function EventPicker({ place }: { place: MapPlace }) {
  const theme = useTheme();
  const { listUpcomingEvents, refresh } = useCalendar();
  const [events, setEvents] = useState<CalendarEvent[] | null>(null);
  const [query, setQuery] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    listUpcomingEvents()
      .then(setEvents)
      .catch((error) => {
        console.warn('[space] failed to list events', error);
        setEvents([]);
      });
  }, [listUpcomingEvents]);

  const term = query.trim().toLocaleLowerCase();
  const shown = (events ?? []).filter(
    (e) =>
      e.editable &&
      !place.events.some((here) => here.source.id === e.source.id) &&
      (term ? e.title.toLocaleLowerCase().includes(term) : !e.location),
  );

  const pick = async (event: CalendarEvent) => {
    if (saving) return;
    if (event.location && !(await confirmReplace(event))) return;
    const span = await chooseSpan(event, 'Save');
    if (!span) return;
    setSaving(true);
    try {
      await occurrence(event, span).setStructuredLocation(eventLocation(place));
      refresh();
      router.back();
    } catch (error) {
      setSaving(false);
      Alert.alert('Couldn’t Save Event', String(error));
    }
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
          title: 'Add to Event',
          headerLeft: () => <HeaderButton label="Cancel" onPress={() => router.back()} />,
          headerRight: () => (saving ? <ActivityIndicator /> : null),
        }}
      />
      <Section
        footer={
          !events
            ? undefined
            : term
              ? shown.length === 0
                ? `No upcoming events match “${query.trim()}”.`
                : undefined
              : shown.length === 0
                ? `No events in the next ${UPCOMING_DAYS} days without a location. Search to find ones with a location.`
                : `Events in the next ${UPCOMING_DAYS} days without a location. Search to find ones with a location too.`
        }
      >
        <SearchRow placeholder="Search events" value={query} onChangeText={setQuery} />
        {!events ? (
          <View style={{ padding: 16 }}>
            <ActivityIndicator />
          </View>
        ) : null}
        {shown.map((event) => (
          <View key={event.key}>
            <Separator />
            <PickRow
              title={event.title}
              subtitle={[
                describeEventTime(event),
                event.location ? parseLocationTitle(event.location).name : null,
              ]
                .filter(Boolean)
                .join(' · ')}
              color={event.color}
              onPress={() => pick(event)}
            />
          </View>
        ))}
      </Section>
    </ScrollView>
  );
}

function confirmReplace(event: CalendarEvent): Promise<boolean> {
  return new Promise((resolve) =>
    Alert.alert(
      `Move “${event.title}” Here?`,
      `Its location is ${parseLocationTitle(event.location ?? '').name} now.`,
      [
        { text: 'Cancel', style: 'cancel', onPress: () => resolve(false) },
        { text: 'Move', onPress: () => resolve(true) },
      ],
      { cancelable: true, onDismiss: () => resolve(false) },
    ),
  );
}
