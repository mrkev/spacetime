import { Stack, router, useFocusEffect, useLocalSearchParams, useNavigation } from 'expo-router';
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
  type ListViewToken,
} from 'react-native';

import { HeaderButton } from '../../../components/HeaderButton';
import { icons } from '../../../components/Icon';
import {
  addDays,
  addMonths,
  dayKey,
  daysInMonth,
  differenceInMonths,
  formatShortMonth,
  isSameDay,
  parseMonthKey,
  startOfMonth,
  weekdayLabels,
} from '../../../lib/dates';
import { useNowAction } from '../../../lib/nowAction';
import { useTheme, type Theme } from '../../../lib/theme';
import { AccessBanner } from '../../../time/AccessBanner';
import { useCalendar, type DayItems } from '../../../time/CalendarProvider';
import { useTimeActions } from '../../../time/actions';
import { useRememberTimeLevel } from '../../../time/timeLevel';

// Ten years either way, matching the year view.
const MONTHS_EACH_WAY = 120;
const TITLE_HEIGHT = 48;
const WEEK_HEIGHT = 64;
const WEEK_STARTS_ON = 0;

function weeksInMonth(month: Date): number {
  const leading = (month.getDay() - WEEK_STARTS_ON + 7) % 7;
  return Math.ceil((leading + daysInMonth(month)) / 7);
}

export default function MonthScreen() {
  const theme = useTheme();
  const params = useLocalSearchParams<{ month?: string }>();
  const { ensureMonths, getDay, version } = useCalendar();
  const { showAddMenu } = useTimeActions();
  const listRef = useRef<FlatList<number>>(null);
  useRememberTimeLevel('month');

  // Normally the year view is beneath this one. If it isn't (this view ended up at the bottom of
  // the stack), the back button swaps this view for one instead.
  const navigation = useNavigation();
  const isRoot = navigation.getState()?.routes[0]?.name === 'index';

  const today = useMemo(() => new Date(), []);
  const baseMonth = useMemo(
    () => parseMonthKey(params.month) ?? startOfMonth(today),
    [params.month, today],
  );
  const [visibleYear, setVisibleYear] = useState(baseMonth.getFullYear());

  // Each item is a month's offset from this month.
  const thisMonth = useMemo(() => startOfMonth(today), [today]);
  const monthOffsets = useMemo(
    () => Array.from({ length: MONTHS_EACH_WAY * 2 + 1 }, (_, i) => i - MONTHS_EACH_WAY),
    [],
  );
  const indexOf = (month: Date) =>
    Math.max(
      0,
      Math.min(MONTHS_EACH_WAY * 2, MONTHS_EACH_WAY + differenceInMonths(thisMonth, month)),
    );
  const initialIndex = indexOf(baseMonth);

  // Month heights vary (4–6 weeks), so precompute offsets for getItemLayout.
  const layout = useMemo(() => {
    const offsets: number[] = [];
    const heights: number[] = [];
    let offset = 0;
    for (const i of monthOffsets) {
      const height = TITLE_HEIGHT + weeksInMonth(addMonths(thisMonth, i)) * WEEK_HEIGHT;
      offsets.push(offset);
      heights.push(height);
      offset += height;
    }
    return { offsets, heights };
  }, [monthOffsets, thisMonth]);

  const getItemLayout = useCallback(
    (_: unknown, index: number) => ({
      index,
      length: layout.heights[index],
      offset: layout.offsets[index],
    }),
    [layout],
  );

  // FlatList doesn't allow swapping the viewability callback, so keep one stable function and
  // read the latest loader from a ref.
  const ensureMonthsRef = useRef(ensureMonths);
  const visibleMonthRef = useRef(baseMonth);
  useEffect(() => {
    ensureMonthsRef.current = ensureMonths;
  }, [ensureMonths]);

  const [onViewableItemsChanged] = useState(
    () =>
      ({ viewableItems }: { viewableItems: ListViewToken[] }) => {
        const first = viewableItems.find((v) => v.isViewable);
        if (first?.item == null) return;
        const month = addMonths(thisMonth, first.item as number);
        visibleMonthRef.current = month;
        setVisibleYear(month.getFullYear());
        ensureMonthsRef.current(month, 2);
      },
  );

  // Load what's on screen once access is granted or calendars change.
  useEffect(() => {
    ensureMonths(visibleMonthRef.current, 2);
  }, [ensureMonths]);

  // Open on the month asked for (this one by default). Until people scroll it themselves, keep it
  // there whenever the list lays out or comes back into view, in case something resets the offset
  // while it's offscreen (it once opened on 2016 on a phone).
  const userScrolled = useRef(false);
  const holdInitialMonth = useCallback(() => {
    if (userScrolled.current) return;
    listRef.current?.scrollToIndex({ index: initialIndex, animated: false });
  }, [initialIndex]);
  useFocusEffect(holdInitialMonth);

  const scrollToToday = () => {
    userScrolled.current = true;
    listRef.current?.scrollToIndex({ index: MONTHS_EACH_WAY, animated: true });
  };
  useNowAction('time', scrollToToday);

  const openDay = useCallback((date: Date) => {
    router.push({ pathname: '/time/day', params: { date: dayKey(date) } });
  }, []);

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <Stack.Screen
        options={{
          // Like Calendar, the back button to the year view shows the year you're looking at.
          title: '',
          headerBackTitle: String(visibleYear),
          headerLeft: isRoot
            ? () => (
                <HeaderButton
                  icon={icons.chevronLeft}
                  label={String(visibleYear)}
                  onPress={() => router.replace('/time/year')}
                />
              )
            : undefined,
          headerRight: () => (
            <View style={styles.headerRight}>
              <HeaderButton
                icon={icons.checklist}
                accessibilityLabel="Reminders"
                onPress={() => router.push('/time/reminders')}
              />
              <HeaderButton
                icon={icons.plus}
                accessibilityLabel="Add"
                onPress={() => showAddMenu()}
              />
            </View>
          ),
        }}
      />
      <WeekdayHeader theme={theme} />
      <AccessBanner />
      <FlatList
        ref={listRef}
        data={monthOffsets}
        keyExtractor={(i) => String(i)}
        extraData={version}
        getItemLayout={getItemLayout}
        initialScrollIndex={initialIndex}
        onLayout={holdInitialMonth}
        onScrollBeginDrag={() => {
          userScrolled.current = true;
        }}
        onViewableItemsChanged={onViewableItemsChanged}
        viewabilityConfig={{ itemVisiblePercentThreshold: 30 }}
        windowSize={5}
        initialNumToRender={3}
        maxToRenderPerBatch={3}
        showsVerticalScrollIndicator={false}
        renderItem={({ item }) => (
          <MonthItem
            month={addMonths(thisMonth, item)}
            today={today}
            getDay={getDay}
            onPressDay={openDay}
            theme={theme}
          />
        )}
      />
    </View>
  );
}

function WeekdayHeader({ theme }: { theme: Theme }) {
  const labels = useMemo(() => weekdayLabels(WEEK_STARTS_ON), []);
  return (
    <View style={[styles.weekdays, { borderBottomColor: theme.separator }]}>
      {labels.map((label, i) => (
        <Text key={i} style={[styles.weekday, { color: theme.secondaryText }]}>
          {label}
        </Text>
      ))}
    </View>
  );
}

const MonthItem = memo(function MonthItem({
  month,
  today,
  getDay,
  onPressDay,
  theme,
}: {
  month: Date;
  today: Date;
  getDay: (date: Date) => DayItems | undefined;
  onPressDay: (date: Date) => void;
  theme: Theme;
}) {
  const { width } = useWindowDimensions();
  const cellWidth = width / 7;
  const leading = (month.getDay() - WEEK_STARTS_ON + 7) % 7;
  const total = daysInMonth(month);
  const weeks = weeksInMonth(month);
  const isCurrentMonth =
    month.getFullYear() === today.getFullYear() && month.getMonth() === today.getMonth();

  return (
    <View>
      <View style={[styles.monthTitleRow, { height: TITLE_HEIGHT }]}>
        <Text
          style={[
            styles.monthTitle,
            {
              color: isCurrentMonth ? theme.tint : theme.text,
              width: cellWidth,
              left: leading * cellWidth,
            },
          ]}
        >
          {formatShortMonth(month)}
        </Text>
      </View>
      {Array.from({ length: weeks }, (_, week) => (
        <View key={week} style={[styles.week, { height: WEEK_HEIGHT }]}>
          {Array.from({ length: 7 }, (_, weekday) => {
            const dayNumber = week * 7 + weekday - leading + 1;
            if (dayNumber < 1 || dayNumber > total) {
              return <View key={weekday} style={{ width: cellWidth }} />;
            }
            const date = addDays(month, dayNumber - 1);
            const items = getDay(date);
            return (
              <DayCell
                key={weekday}
                date={date}
                width={cellWidth}
                isToday={isSameDay(date, today)}
                hasEvents={!!items && (items.events.length > 0 || items.reminders.length > 0)}
                onPress={onPressDay}
                theme={theme}
              />
            );
          })}
        </View>
      ))}
    </View>
  );
});

function DayCell({
  date,
  width,
  isToday,
  hasEvents,
  onPress,
  theme,
}: {
  date: Date;
  width: number;
  isToday: boolean;
  hasEvents: boolean;
  onPress: (date: Date) => void;
  theme: Theme;
}) {
  const weekend = date.getDay() === 0 || date.getDay() === 6;
  return (
    <Pressable
      onPress={() => onPress(date)}
      style={[styles.dayCell, { width, borderTopColor: theme.separator }]}
      accessibilityRole="button"
      accessibilityLabel={date.toDateString()}
    >
      <View style={[styles.dayNumberWrap, isToday && { backgroundColor: theme.tint }]}>
        <Text
          style={[
            styles.dayNumber,
            { color: isToday ? '#fff' : weekend ? theme.secondaryText : theme.text },
            isToday && styles.bold,
          ]}
        >
          {date.getDate()}
        </Text>
      </View>
      {hasEvents ? <View style={[styles.dot, { backgroundColor: theme.secondaryText }]} /> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  headerRight: { flexDirection: 'row', gap: 8 },
  weekdays: {
    flexDirection: 'row',
    paddingVertical: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  weekday: { flex: 1, textAlign: 'center', fontSize: 12, fontWeight: '500' },
  monthTitleRow: { justifyContent: 'flex-end', paddingBottom: 6 },
  monthTitle: {
    position: 'absolute',
    bottom: 6,
    textAlign: 'center',
    fontSize: 20,
    fontWeight: '700',
  },
  week: { flexDirection: 'row' },
  dayCell: {
    alignItems: 'center',
    paddingTop: 6,
    borderTopWidth: StyleSheet.hairlineWidth,
    gap: 4,
  },
  dayNumberWrap: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dayNumber: { fontSize: 18 },
  bold: { fontWeight: '600' },
  dot: { width: 6, height: 6, borderRadius: 3 },
});
