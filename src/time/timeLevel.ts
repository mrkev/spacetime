import { router, useFocusEffect } from 'expo-router';
import Storage from 'expo-sqlite/kv-store';
import { useCallback } from 'react';

/** Which level of the calendar the Time tab was last left on. */
export type TimeLevel = 'year' | 'month';

const LEVEL_KEY = 'spacetime.time.level';

function lastLevel(): TimeLevel {
  try {
    return Storage.getItemSync(LEVEL_KEY) === 'year' ? 'year' : 'month';
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
 * Runs as the Time tab is first selected. Its stack starts at the year view (the anchor), so to
 * reopen on the month view, navigate there *with* the anchor before the stack mounts: it then
 * starts out as year → month, and back (or a swipe) returns to the year.
 */
export function openTimeTab() {
  if (opened) return;
  opened = true;
  if (lastLevel() === 'month') router.navigate('/time', { withAnchor: true });
}
