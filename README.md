# Spacetime

A React Native (Expo SDK 58) app with two tabs:

- **Space** — a map of your saved places. Places live in collections ("maps"), each with its own pin color. The built-in **Reminders** collection is special: its places are the reminders in Apple Reminders that have a location, and Reminders notifies you when you arrive at or leave them.
- **Time** — a calendar modeled on Apple Calendar. It shows the events and reminders already on your phone (via EventKit).

## Running

The app uses native modules that Expo Go doesn't include (such as a patched expo-calendar), so it has to be built with Xcode. It's meant to run on an iPhone: build it in Release, which bundles the JavaScript so the app works without Metro running, and install it with `devicectl`. The steps are in [AGENTS.md](AGENTS.md#building-and-installing-on-the-phone).

For quick iteration in the Simulator, there's also a development build that loads its JavaScript from Metro:

```sh
pnpm install
pnpm ios           # builds a Debug build and launches it in the iOS Simulator
pnpm start         # start Metro for an already-installed Debug build
```

Other scripts: `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm format`.

Calendar and Reminders access work best on a real device.

## How it's organized

The repo is a pnpm workspace. The app lives in `packages/app`; other packages can go alongside it in `packages/`. Inside `packages/app`:

```
src/app/                     Routes (Expo Router)
  (tabs)/_layout.tsx         Native tab bar: Space, Time
  (tabs)/space/index.tsx     Map, search, collection filters
  (tabs)/time/index.tsx      Scrolling month view
  (tabs)/time/day.tsx        Week strip + swipeable hour timeline
  (tabs)/time/reminders.tsx  Location, scheduled, and undated reminders
  place/                     Add / edit a place or location reminder
  collections/               Create, rename, recolor, delete collections
  reminder/new.tsx           New Apple Reminders reminder (iOS)
src/space/                   Place store (SQLite key-value), location reminders, place form
src/time/                    Calendar data provider, reminder metadata, timeline layout, day page
src/components/, src/lib/    Shared UI and helpers
```

## Notes

- **Events** are created and edited with the system event editor, so every Calendar field (invitees, alerts, recurrence) is available. In the day view, touch and hold an event to drag it to a new time (in 15-minute steps), drag its handles to change the start or end, or use the Cut / Copy / Delete / Duplicate menu. After copying, touch and hold an empty slot to paste. Changes to repeating events ask whether they apply to this event only or all future ones. Pinch the day view to zoom; it remembers the zoom level.
- **Reminders**, dated or located, live in Apple Reminders, so they sync and show up in Reminders, on the Mac, and on the Watch. A location reminder is a reminder with a location alarm; Reminders (not Spacetime) watches the location and notifies you, so Spacetime only needs location access while it's open. Location reminders made in the Reminders app show up on the map too.
- **Reminder metadata** Reminders has no field for (for now, a location reminder's address) is kept on-device in `src/time/reminderMeta.ts`, keyed by the reminder's external ID (the same on every device) with its local ID as a fallback, and dropped once the reminder is deleted.
- Places are stored on-device only. iOS is the only supported platform.
