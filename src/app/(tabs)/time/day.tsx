import { Stack, useLocalSearchParams } from 'expo-router';
import Storage from 'expo-sqlite/kv-store';
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
  dayKey,
  differenceInDays,
  formatFullDate,
  formatMonth,
  isSameDay,
  parseDayKey,
  startOfDay,
  startOfWeek,
  weekdayLabels,
} from '../../../lib/dates';
import { useNowAction } from '../../../lib/nowAction';
import { useTheme, type Theme } from '../../../lib/theme';
import { AccessBanner } from '../../../time/AccessBanner';
import { useCalendar } from '../../../time/CalendarProvider';
import {
  DayPage,
  HOUR_HEIGHT,
  MAX_HOUR_HEIGHT,
  MIN_HOUR_HEIGHT,
  nowOffset,
} from '../../../time/DayPage';
import { useTimeActions } from '../../../time/actions';
import { useRememberTimeLevel } from '../../../time/timeLevel';

const DAYS_EACH_WAY = 730;
const WEEK_STARTS_ON = 0;
const ZOOM_KEY = 'spacetime.time.hourHeight';

/** The pinch zoom you last left the day view at. */
function loadHourHeight(): number {
  try {
    const saved = Number(Storage.getItemSync(ZOOM_KEY));
    return saved >= MIN_HOUR_HEIGHT && saved <= MAX_HOUR_HEIGHT ? saved : HOUR_HEIGHT;
  } catch {
    return HOUR_HEIGHT;
  }
}

export default function DayScreen() {
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const params = useLocalSearchParams<{ date?: string }>();
  const { toggleReminder } = useCalendar();
  const { createEvent, openEvent, openReminder, showAddMenu } = useTimeActions();

  // Pages are indexed relative to a fixed anchor so indices stay stable while swiping.
  const anchor = useMemo(() => startOfDay(parseDayKey(params.date) ?? new Date()), [params.date]);
  const [selected, setSelected] = useState(anchor);
  // The event being edited (long-pressed), and whether it's mid-drag.
  const [selection, setSelection] = useState<{ key: string; day: string } | null>(null);
  // Whether an event is being dragged or the day pinched, so the pager holds still.
  const [gestureActive, setGestureActive] = useState(false);
  const [hourHeight, setHourHeight] = useState(loadHourHeight);
  const hourHeightRef = useRef(hourHeight);
  const zoomTo = useCallback((height: number) => {
    hourHeightRef.current = height;
    setHourHeight(height);
  }, []);
  // Pages re-render when the selection or zoom changes.
  const pagerState = useMemo(() => ({ selection, hourHeight }), [selection, hourHeight]);
  const saveZoom = useCallback(() => {
    Storage.setItemSync(ZOOM_KEY, String(hourHeightRef.current));
  }, []);

  const dayPager = useRef<FlatList<number>>(null);
  const weekPager = useRef<FlatList<number>>(null);

  // Start the timeline around the current hour (or 7 AM on other days), shared across pages.
  const scrollOffsetRef = useRef(
    Math.max(0, isSameDay(anchor, new Date()) ? nowOffset(hourHeight) : (8 - 1) * hourHeight),
  );

  const onScrollY = useCallback((y: number) => {
    scrollOffsetRef.current = y;
  }, []);

  const dayIndices = useMemo(() => Array.from({ length: DAYS_EACH_WAY * 2 + 1 }, (_, i) => i), []);
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
      setSelection(null);
      if (syncDays) dayPager.current?.scrollToIndex({ index, animated: false });
      if (syncWeeks) weekPager.current?.scrollToIndex({ index: indexForWeek(day), animated: true });
    },
    [indexForDay, indexForWeek, dayIndices.length],
  );

  useRememberTimeLevel('day');

  // Today: go to today's page and bring the current-time indicator into view. Pages that mount on
  // the way start there; today's page, if already showing, scrolls to it (`scrollToNow`).
  const [scrollToNow, setScrollToNow] = useState(0);
  useNowAction('time', () => {
    scrollOffsetRef.current = nowOffset(hourHeightRef.current);
    select(new Date());
    setScrollToNow((n) => n + 1);
  });

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
          // Like Calendar, the back button to the month view names the month you're in.
          title: '',
          headerBackTitle: formatMonth(selected),
          headerRight: () => (
            <View style={styles.headerRight}>
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
        scrollEnabled={!gestureActive}
        extraData={pagerState}
        style={styles.pager}
        renderItem={({ item }) => {
          const date = dayForIndex(item);
          const day = dayKey(date);
          return (
            <DayPage
              date={date}
              width={width}
              initialScrollY={scrollOffsetRef.current}
              onScrollY={onScrollY}
              onPressEvent={openEvent}
              onToggleReminder={toggleReminder}
              onPressReminder={openReminder}
              onCreateAt={createEvent}
              selectedKey={selection?.day === day ? selection.key : null}
              onSelect={(key) => setSelection(key ? { key, day } : null)}
              onGestureActive={setGestureActive}
              scrollToNow={scrollToNow}
              hourHeight={hourHeight}
              onZoom={zoomTo}
              onZoomEnd={saveZoom}
            />
          );
        }}
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
              <Text
                style={[styles.weekDayNumber, { color }, (isSelected || isToday) && styles.bold]}
              >
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
