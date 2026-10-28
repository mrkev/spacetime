import { useFocusEffect } from 'expo-router';
import { useEffect, useRef } from 'react';

export type TabName = 'space' | 'time';

/** What the tab bar's floating button does on each tab ("Here" on Space, "Today" on Time). */
const handlers = new Map<TabName, () => void>();

export function runNowAction(tab: TabName) {
  handlers.get(tab)?.();
}

/**
 * Makes `action` the floating button's action for `tab` while this screen is focused, so the
 * screen on top of a tab's stack (e.g. the day view over the month view) handles it.
 */
export function useNowAction(tab: TabName, action: () => void) {
  const latest = useRef(action);
  useEffect(() => {
    latest.current = action;
  });
  useFocusEffect(() => {
    const run = () => latest.current();
    handlers.set(tab, run);
    return () => {
      if (handlers.get(tab) === run) handlers.delete(tab);
    };
  });
}
