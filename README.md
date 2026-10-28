# Spacetime

A React Native (Expo SDK 58) app with two tabs:

- **Space** — a map of your saved places. Places live in collections ("maps"), each with its own pin color. The built-in **Reminders** collection is special: each place in it is a location reminder that notifies you when you arrive at or leave it.
- **Time** — a calendar modeled on Apple Calendar. It shows the events and reminders already on your phone (via EventKit / the Android calendar provider), plus your location reminders.

## Running

The app uses native modules that Expo Go doesn't include (calendar, background geofencing), so it runs as a development build:

```sh
npm install
npm run ios        # builds and launches in the iOS Simulator (needs Xcode)
npm run android    # needs Android Studio
npm start          # start Metro for an already-installed dev build
```

Other scripts: `npm run typecheck`, `npm run lint`, `npm test`.

Background geofencing and calendar access work best on a real device. In the Simulator you can test location reminders with **Features → Location → Custom Location…**.

## How it's organized

```
index.ts                     Entry: defines the geofence task before the app renders
src/app/                     Routes (Expo Router)
  (tabs)/_layout.tsx         Native tab bar: Space, Time
  (tabs)/space/index.tsx     Map, search, collection filters
  (tabs)/time/index.tsx      Scrolling month view
  (tabs)/time/day.tsx        Week strip + swipeable hour timeline
  (tabs)/time/reminders.tsx  Location, scheduled, and undated reminders
  place/new.tsx, [id].tsx    Add / edit a place (and its reminder settings)
  collections/               Create, rename, recolor, delete collections
  reminder/new.tsx           New Apple Reminders reminder (iOS)
src/space/                   Place store (SQLite key-value), geofencing, place form
src/time/                    Calendar data provider, timeline layout, day page
src/components/, src/lib/    Shared UI and helpers
```

## Notes

- **Events** are created and edited with the system event editor, so every Calendar field (invitees, alerts, recurrence) is available. In the day view, touch and hold an event to drag it to a new time (in 15-minute steps), drag its handles to change the start or end, or use the Cut / Copy / Delete / Duplicate menu. After copying, touch and hold an empty slot to paste. Changes to repeating events ask whether they apply to this event only or all future ones. Pinch the day view to zoom; it remembers the zoom level.
- **Dated reminders** use Apple Reminders and are iOS-only; Android has no system reminders API. Location reminders work on both.
- **Location reminders** need location access set to _Always_ plus notification permission. iOS monitors at most 20 regions per app, so Spacetime registers the 20 closest to you and re-picks them whenever the app opens.
- Geofence events only notify on a real transition (outside → inside for "arriving"), so creating a reminder where you're standing doesn't fire immediately. One-off reminders complete after they fire; repeating ones have a 10-minute cooldown to avoid GPS jitter at the edge.
- Places are stored on-device only.
- Android maps need a Google Maps API key; see the [react-native-maps docs](https://docs.expo.dev/versions/v58.0.0/sdk/map-view/).
