import { Stack, useLocalSearchParams } from 'expo-router';
import { useCallback, useMemo, useRef, useState } from 'react';
import {
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
} from 'react-native';

import { HeaderButton } from '../../../components/HeaderButton';
import { icons } from '../../../components/Icon';
import {
  addDays,
  differenceInDays,
  formatFullDate,
  formatMonth,
  isSameDay,
  minutesIntoDay,
  parseDayKey,
  startOfDay,
  startOfWeek,
  weekdayLabels,
} from '../../../lib/dates';
import { useTheme, type Theme } from '../../../lib/theme';
import { AccessBanner } from '../../../time/AccessBanner';
import { useCalendar } from '../../../time/CalendarProvider';
import { DayPage, HOUR_HEIGHT } from '../../../time/DayPage';
import { useTimeActions } from '../../../time/actions';

const DAYS_EACH_WAY = 730;
const WEEK_STARTS_ON = 0;

export default function DayScreen() {
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const params = useLocalSearchParams<{ date?: string }>();
  const { toggleReminder } = useCalendar();
  const { createEvent, openEvent, showAddMenu } = useTimeActions();

  // Pages are indexed relative to a fixed anchor so indices stay stable while swiping.
  const anchor = useMemo(() => startOfDay(parseDayKey(params.date) ?? new Date()), [params.date]);
  const [selected, setSelected] = useState(anchor);

  const dayPager = useRef<FlatList<number>>(null);
  const weekPager = useRef<FlatList<number>>(null);

  // Start the timeline around the current hour (or 7 AM on other days), shared across pages.
  const scrollOffsetRef = useRef(
    Math.max(
      0,
      ((isSameDay(anchor, new Date()) ? minutesIntoDay(new Date()) / 60 : 8) - 1) * HOUR_HEIGHT,
    ),
  );

  const onScrollY = useCallback((y: number) => {
    scrollOffsetRef.current = y;
  }, []);

  const dayIndices = useMemo(
    () => Array.from({ length: DAYS_EACH_WAY * 2 + 1 }, (_, i) => i),
    [],
  );
  const anchorWeek = useMemo(() => startOfWeek(anchor, WEEK_STARTS_ON), [anchor]);
  const weekIndices = useMemo(
    () => Array.from({ length: Math.ceil((DAYS_EACH_WAY * 2) / 7) + 3 }, (_, i) => i),
    [],
  );
  const weeksBefore = Math.ceil(DAYS_EACH_WAY / 7) + 1;

  const dayForIndex = useCallback((i: number) => addDays(anchor, i - DAYS_EACH_WAY), [anchor]);
  const indexForDay = useCallback(
    (d: Date) => differenceInDays(anchor, d) + DAYS_EACH_WAY,
    [anchor],
  );
  const weekForIndex = useCallback(
    (i: number) => addDays(anchorWeek, (i - weeksBefore) * 7),
    [anchorWeek, weeksBefore],
  );
  const indexForWeek = useCallback(
    (d: Date) =>
      Math.round(differenceInDays(anchorWeek, startOfWeek(d, WEEK_STARTS_ON)) / 7) + weeksBefore,
    [anchorWeek, weeksBefore],
  );

  const select = useCallback(
    (day: Date, { syncDays = true, syncWeeks = true } = {}) => {
      const index = indexForDay(day);
      if (index < 0 || index >= dayIndices.length) return;
      setSelected(startOfDay(day));
      if (syncDays) dayPager.current?.scrollToIndex({ index, animated: false });
      if (syncWeeks) weekPager.current?.scrollToIndex({ index: indexForWeek(day), animated: true });
    },
    [indexForDay, indexForWeek, dayIndices.length],
  );

  const onDayPageEnd = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const index = Math.round(e.nativeEvent.contentOffset.x / width);
    const day = dayForIndex(index);
    if (!isSameDay(day, selected)) select(day, { syncDays: false });
  };

  const onWeekPageEnd = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const week = weekForIndex(Math.round(e.nativeEvent.contentOffset.x / width));
    // Keep the same weekday selected when swiping between weeks, like Calendar.
    const day = addDays(week, (selected.getDay() - WEEK_STARTS_ON + 7) % 7);
    if (!isSameDay(day, selected)) select(day, { syncWeeks: false });
  };

  const pageLayout = useCallback(
    (_: unknown, index: number) => ({ index, length: width, offset: width * index }),
    [width],
  );

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <Stack.Screen
        options={{
          title: formatMonth(selected),
          headerRight: () => (
            <View style={styles.headerRight}>
              <HeaderButton label="Today" onPress={() => select(new Date())} />
              <HeaderButton
                icon={icons.plus}
                accessibilityLabel="Add"
                onPress={() => showAddMenu(selected)}
              />
            </View>
          ),
        }}
      />

      <View style={[styles.weekHeader, { borderBottomColor: theme.separator }]}>
        <View style={styles.weekdayRow}>
          {weekdayLabels(WEEK_STARTS_ON).map((label, i) => (
            <Text key={i} style={[styles.weekdayLabel, { color: theme.secondaryText }]}>
              {label}
            </Text>
          ))}
        </View>
        <FlatList
          ref={weekPager}
          data={weekIndices}
          keyExtractor={String}
          horizontal
          pagingEnabled
          showsHorizontalScrollIndicator={false}
          initialScrollIndex={weeksBefore}
          getItemLayout={pageLayout}
          windowSize={3}
          initialNumToRender={1}
          onMomentumScrollEnd={onWeekPageEnd}
          extraData={selected}
          renderItem={({ item }) => (
            <WeekRow
              start={weekForIndex(item)}
              selected={selected}
              width={width}
              theme={theme}
              onSelect={(day) => select(day, { syncWeeks: false })}
            />
          )}
        />
        <Text style={[styles.fullDate, { color: theme.text }]}>{formatFullDate(selected)}</Text>
      </View>

      <AccessBanner />

      <FlatList
        ref={dayPager}
        data={dayIndices}
        keyExtractor={String}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        initialScrollIndex={DAYS_EACH_WAY}
        getItemLayout={pageLayout}
        windowSize={3}
        initialNumToRender={1}
        maxToRenderPerBatch={1}
        onMomentumScrollEnd={onDayPageEnd}
        style={styles.pager}
        renderItem={({ item }) => (
          <DayPage
            date={dayForIndex(item)}
            width={width}
            initialScrollY={scrollOffsetRef.current}
            onScrollY={onScrollY}
            onPressEvent={openEvent}
            onToggleReminder={toggleReminder}
            onCreateAt={createEvent}
          />
        )}
      />
    </View>
  );
}

function WeekRow({
  start,
  selected,
  width,
  theme,
  onSelect,
}: {
  start: Date;
  selected: Date;
  width: number;
  theme: Theme;
  onSelect: (day: Date) => void;
}) {
  const today = new Date();
  return (
    <View style={[styles.weekRow, { width }]}>
      {Array.from({ length: 7 }, (_, i) => {
        const day = addDays(start, i);
        const isSelected = isSameDay(day, selected);
        const isToday = isSameDay(day, today);
        const background = isSelected ? (isToday ? theme.tint : theme.text) : 'transparent';
        const color = isSelected ? theme.background : isToday ? theme.tint : theme.text;
        return (
          <Pressable
            key={i}
            style={styles.weekDay}
            onPress={() => onSelect(day)}
            accessibilityRole="button"
            accessibilityState={{ selected: isSelected }}
            accessibilityLabel={formatFullDate(day)}
          >
            <View style={[styles.weekDayCircle, { backgroundColor: background }]}>
              <Text style={[styles.weekDayNumber, { color }, (isSelected || isToday) && styles.bold]}>
                {day.getDate()}
              </Text>
            </View>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  weekHeader: { borderBottomWidth: StyleSheet.hairlineWidth, paddingBottom: 8 },
  weekdayRow: { flexDirection: 'row', paddingTop: 4 },
  weekdayLabel: { flex: 1, textAlign: 'center', fontSize: 11, fontWeight: '500' },
  weekRow: { flexDirection: 'row', paddingVertical: 4 },
  weekDay: { flex: 1, alignItems: 'center' },
  weekDayCircle: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
  },
  weekDayNumber: { fontSize: 18 },
  bold: { fontWeight: '600' },
  fullDate: { textAlign: 'center', fontSize: 15, fontWeight: '500', marginTop: 4 },
  pager: { flex: 1 },
});
