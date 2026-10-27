import { Stack, router } from 'expo-router';
import { memo, useCallback, useMemo, useRef } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View, useWindowDimensions } from 'react-native';

import { HeaderButton } from '../../../components/HeaderButton';
import { icons } from '../../../components/Icon';
import { daysInMonth, formatShortMonth, monthKey } from '../../../lib/dates';
import { useNowAction } from '../../../lib/nowAction';
import { useTheme, type Theme } from '../../../lib/theme';
import { useRememberTimeLevel } from '../../../time/timeLevel';
import { useTimeActions } from '../../../time/actions';

const YEARS_BEFORE = 10;
const YEARS_AFTER = 10;
const WEEK_STARTS_ON = 0;
const PADDING = 16;
const GAP = 12;
const YEAR_TITLE_HEIGHT = 64;
const MONTH_TITLE_HEIGHT = 30;
const DAY_HEIGHT = 18;
const MONTH_HEIGHT = MONTH_TITLE_HEIGHT + 6 * DAY_HEIGHT;
const ROW_GAP = 18;
const YEAR_HEIGHT = YEAR_TITLE_HEIGHT + 4 * (MONTH_HEIGHT + ROW_GAP);

/** The top of the calendar: a scrolling list of years, each a grid of tiny months. */
export default function YearScreen() {
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const { showAddMenu } = useTimeActions();
  const listRef = useRef<FlatList<number>>(null);
  const today = useMemo(() => new Date(), []);

  // Each item is a year's offset from this one. The year view only opens from a tap, with the tab
  // on screen, so it can start scrolled to this year directly.
  const offsets = useMemo(
    () => Array.from({ length: YEARS_BEFORE + YEARS_AFTER + 1 }, (_, i) => i - YEARS_BEFORE),
    [],
  );

  useRememberTimeLevel('year');

  useNowAction('time', () =>
    listRef.current?.scrollToIndex({ index: YEARS_BEFORE, animated: true }),
  );

  const openMonth = useCallback((month: Date) => {
    router.push({ pathname: '/time', params: { month: monthKey(month) } });
  }, []);

  const getItemLayout = useCallback(
    (_: unknown, index: number) => ({ index, length: YEAR_HEIGHT, offset: index * YEAR_HEIGHT }),
    [],
  );

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <Stack.Screen
        options={{
          title: '',
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
      <FlatList
        ref={listRef}
        data={offsets}
        keyExtractor={String}
        getItemLayout={getItemLayout}
        initialScrollIndex={YEARS_BEFORE}
        windowSize={3}
        initialNumToRender={1}
        maxToRenderPerBatch={1}
        showsVerticalScrollIndicator={false}
        renderItem={({ item }) => (
          <YearItem
            year={today.getFullYear() + item}
            today={today}
            width={width}
            theme={theme}
            onPressMonth={openMonth}
          />
        )}
      />
    </View>
  );
}

const YearItem = memo(function YearItem({
  year,
  today,
  width,
  theme,
  onPressMonth,
}: {
  year: number;
  today: Date;
  width: number;
  theme: Theme;
  onPressMonth: (month: Date) => void;
}) {
  const monthWidth = (width - PADDING * 2 - GAP * 2) / 3;
  const isThisYear = year === today.getFullYear();
  return (
    <View style={{ height: YEAR_HEIGHT, paddingHorizontal: PADDING }}>
      <View style={[styles.yearTitleRow, { borderBottomColor: theme.separator }]}>
        <Text
          style={[styles.yearTitle, { color: isThisYear ? theme.tint : theme.text }]}
          accessibilityRole="header"
        >
          {year}
        </Text>
      </View>
      <View style={styles.grid}>
        {Array.from({ length: 12 }, (_, m) => (
          <MiniMonth
            key={m}
            month={new Date(year, m, 1)}
            today={today}
            width={monthWidth}
            theme={theme}
            onPress={onPressMonth}
          />
        ))}
      </View>
    </View>
  );
});

function MiniMonth({
  month,
  today,
  width,
  theme,
  onPress,
}: {
  month: Date;
  today: Date;
  width: number;
  theme: Theme;
  onPress: (month: Date) => void;
}) {
  const dayWidth = width / 7;
  const leading = (month.getDay() - WEEK_STARTS_ON + 7) % 7;
  const total = daysInMonth(month);
  const isThisMonth =
    month.getFullYear() === today.getFullYear() && month.getMonth() === today.getMonth();

  return (
    <Pressable
      onPress={() => onPress(month)}
      accessibilityRole="button"
      accessibilityLabel={`${formatShortMonth(month)} ${month.getFullYear()}`}
      style={({ pressed }) => [{ width, height: MONTH_HEIGHT }, pressed && styles.pressed]}
    >
      <Text style={[styles.monthTitle, { color: isThisMonth ? theme.tint : theme.text }]}>
        {formatShortMonth(month)}
      </Text>
      <View style={styles.days}>
        {Array.from({ length: leading }, (_, i) => (
          <View key={`blank-${i}`} style={{ width: dayWidth, height: DAY_HEIGHT }} />
        ))}
        {Array.from({ length: total }, (_, i) => {
          const isToday = isThisMonth && i + 1 === today.getDate();
          return (
            <View key={i} style={[styles.day, { width: dayWidth }]}>
              <View style={[styles.dayCircle, isToday && { backgroundColor: theme.tint }]}>
                <Text
                  style={[styles.dayNumber, { color: isToday ? '#FFFFFF' : theme.text }]}
                  allowFontScaling={false}
                >
                  {i + 1}
                </Text>
              </View>
            </View>
          );
        })}
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  headerRight: { flexDirection: 'row', gap: 8 },
  yearTitleRow: {
    height: YEAR_TITLE_HEIGHT,
    justifyContent: 'flex-end',
    paddingBottom: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  yearTitle: { fontSize: 34, fontWeight: '700' },
  grid: { flexDirection: 'row', flexWrap: 'wrap', columnGap: GAP, rowGap: ROW_GAP, paddingTop: 12 },
  pressed: { opacity: 0.5 },
  monthTitle: { height: MONTH_TITLE_HEIGHT, fontSize: 20, fontWeight: '700' },
  days: { flexDirection: 'row', flexWrap: 'wrap' },
  day: { height: DAY_HEIGHT, alignItems: 'center', justifyContent: 'center' },
  dayCircle: {
    width: DAY_HEIGHT,
    height: DAY_HEIGHT,
    borderRadius: DAY_HEIGHT / 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dayNumber: { fontSize: 10, fontWeight: '500' },
});
