import * as Calendar from 'expo-calendar';
import Storage from 'expo-sqlite/kv-store';
import { useSyncExternalStore } from 'react';

/**
 * What Spacetime keeps about a reminder that Apple Reminders has no field for. Reminders made in
 * other apps have none of it, so every field is optional.
 */
export type ReminderMeta = {
  /** A location reminder's address (Reminders only keeps the place's name and coordinates). */
  address?: string;
};

/**
 * Identifies a reminder. `id` is this device's ID for it, which a full resync can change;
 * `externalId` is the server's, the same on every device, but not every reminder has one.
 */
export type ReminderRef = { id: string; externalId?: string | null };

type Entry = ReminderMeta & { id: string; externalId?: string };

const STORAGE_KEY = 'spacetime.reminderMeta.v1';

function load(): Entry[] {
  try {
    const raw = Storage.getItemSync(STORAGE_KEY);
    if (raw) return JSON.parse(raw) as Entry[];
  } catch (error) {
    console.warn('[reminderMeta] failed to load', error);
  }
  return [];
}

let entries: Entry[] = load();
const listeners = new Set<() => void>();

function setEntries(next: Entry[]) {
  entries = next;
  try {
    Storage.setItemSync(STORAGE_KEY, JSON.stringify(next));
  } catch (error) {
    console.warn('[reminderMeta] failed to save', error);
  }
  listeners.forEach((listener) => listener());
}

function matches(entry: Entry, ref: ReminderRef) {
  return (!!ref.externalId && entry.externalId === ref.externalId) || entry.id === ref.id;
}

function withoutIds({ id: _id, externalId: _externalId, ...meta }: Entry): ReminderMeta {
  return meta;
}

export function getReminderMeta(ref: ReminderRef): ReminderMeta {
  const entry = entries.find((e) => matches(e, ref));
  return entry ? withoutIds(entry) : {};
}

/** Replaces what's kept for a reminder (and forgets it when `meta` is empty). */
export function setReminderMeta(ref: ReminderRef, meta: ReminderMeta) {
  const rest = entries.filter((e) => !matches(e, ref));
  const empty = Object.values(meta).every((value) => value === undefined);
  setEntries(
    empty ? rest : [...rest, { ...meta, id: ref.id, externalId: ref.externalId ?? undefined }],
  );
}

export function subscribeReminderMeta(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** Re-renders when any reminder's metadata changes. */
export function useReminderMetaVersion(): unknown {
  return useSyncExternalStore(subscribeReminderMeta, () => entries);
}

async function reminderExists(id: string): Promise<boolean> {
  try {
    await Calendar.ExpoCalendarReminder.get(id);
    return true;
  } catch (error) {
    // Anything other than "not found" (e.g. lost access) isn't a reason to forget it.
    const { code, message } = error as { code?: string; message?: string };
    return code !== 'ERR_REMINDER_NOT_FOUND' && !message?.includes('could not be found');
  }
}

/**
 * Brings the metadata up to date with the reminders we can see: updates IDs that changed and
 * fills in external IDs that arrived after the reminder synced, then forgets reminders that were
 * deleted. Completed reminders aren't in `seen`, so those are looked up before being forgotten.
 */
export async function reconcileReminderMeta(
  seen: ReminderRef[],
  exists: (id: string) => Promise<boolean> = reminderExists,
) {
  let changed = false;
  const unseen: Entry[] = [];
  const next = entries.map((entry) => {
    const ref = seen.find((r) => matches(entry, r));
    if (!ref) {
      unseen.push(entry);
      return entry;
    }
    const externalId = ref.externalId ?? entry.externalId;
    if (ref.id === entry.id && externalId === entry.externalId) return entry;
    changed = true;
    return { ...entry, id: ref.id, externalId };
  });

  const gone = new Set<Entry>();
  for (const entry of unseen) {
    if (!(await exists(entry.id))) gone.add(entry);
  }
  if (!changed && gone.size === 0) return;
  // Entries may have changed while we were checking; only drop and update what we looked at.
  const updated = new Map(entries.map((e, i) => [e, next[i]] as const));
  setEntries(entries.filter((e) => !gone.has(e)).map((e) => updated.get(e) ?? e));
}
