import { router, useFocusEffect } from 'expo-router';
import Storage from 'expo-sqlite/kv-store';
import { useCallback } from 'react';

import { dayKey } from '../lib/dates';

/** Which level of the calendar the Time tab was last left on. */
export type TimeLevel = 'year' | 'month' | 'day';

const LEVEL_KEY = 'spacetime.time.level';

function lastLevel(): TimeLevel {
  try {
    const level = Storage.getItemSync(LEVEL_KEY);
    return level === 'year' || level === 'day' ? level : 'month';
  } catch {
    return 'month';
  }
}

/** Records `level` as where to reopen the Time tab while this screen is focused. */
export function useRememberTimeLevel(level: TimeLevel) {
  useFocusEffect(
    useCallback(() => {
      Storage.setItemSync(LEVEL_KEY, level);
    }, [level]),
  );
}

let opened = false;

/**
 * Runs as the Time tab is first selected, to reopen it at the level it was left on (showing
 * today, like Calendar). Its stack starts at the year view (the anchor); the levels above it are
 * added before the stack mounts, so it starts out as year → month (→ day) with no animation, and
 * back (or a swipe) goes up a level.
 */
export function openTimeTab() {
  if (opened) return;
  opened = true;
  const level = lastLevel();
  if (level === 'year') return;
  router.navigate('/time', { withAnchor: true });
  if (level === 'day') router.push({ pathname: '/time/day', params: { date: dayKey(new Date()) } });
}
