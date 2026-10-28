This is an Expo/React Native mobile application. Prioritize mobile-first patterns, performance, and cross-platform compatibility.

## Expo has changed — do not trust your training data

Expo ships breaking changes every SDK release. APIs you remember are likely renamed, moved, or removed. Before writing any code that touches an Expo, EAS, or React Native API:

1. Read the major version of the `expo` package in `packages/app/package.json`.
2. Fetch the matching versioned docs: `https://docs.expo.dev/versions/v<major>.0.0/`
3. For anything else, fetch https://docs.expo.dev/llms.txt — an index of all Expo docs with corrections to common LLM misconceptions. Follow its links to the specific page you need; never answer from memory.

## Commands

This is a pnpm workspace (see `pnpm-workspace.yaml`). The Expo app is in `packages/app/`; run app commands from that directory.

```bash
pnpm expo install <package>  # ALWAYS use instead of pnpm add — resolves SDK-compatible versions
pnpm expo start              # start the dev server
pnpm expo lint               # lint
pnpm tsc --noEmit            # typecheck
pnpm dlx expo-doctor         # diagnose dependency and config issues
pnpm expo install --fix      # fix incompatible package versions
```

From the repo root, `pnpm lint`, `pnpm typecheck`, and `pnpm test` run across all packages, and `pnpm format` formats everything with Prettier.

Run lint and typecheck before declaring any task done.

## Navigation & Routing

- Use **Expo Router** for all navigation. Routes live in `packages/app/src/app/` — every file there is a screen, `_layout.tsx` files define navigators. Keep non-route code (components, hooks, utils) outside `src/app/`.
- Import `Link`, `router`, and `useLocalSearchParams` from `expo-router`.
- Docs: https://docs.expo.dev/router/introduction.md

## Building and installing on the phone

The app is only built for iOS, locally with Xcode, and installed on the user's iPhone. EAS isn't set up (there's no `eas.json`). Don't use `pnpm expo run:ios --device` or `eas build` for this: `expo run:ios` makes a Debug build that loads its JavaScript from Metro on this Mac, so it stops working as soon as Metro isn't running. Make a Release build, which has the JavaScript bundled in, and install it with `devicectl`.

The user tests on the phone. When it's connected, build and install after making changes; don't run simulator or UI tests unless asked.

From `packages/app/`:

```bash
# 1. Only if ios/ is missing, or after changing app.json, a dependency with native code, or a
#    patch in patches/ that touches native code. --clean deletes and regenerates ios/.
CI=1 pnpm expo prebuild --clean --platform ios

# 2. Release build for a device (takes a few minutes; signing is automatic).
xcodebuild -workspace ios/Spacetime.xcworkspace -scheme Spacetime -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath ios/build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# 3. Find the phone ("Change My Mind", an iPhone 13; its identifier is
#    765FE281-0AD8-57F9-B998-22816F0CD00A). It's connected if it's listed as available.
xcrun devicectl list devices

# 4. Install, then launch.
xcrun devicectl device install app --device 765FE281-0AD8-57F9-B998-22816F0CD00A \
  ios/build/Build/Products/Release-iphoneos/Spacetime.app
xcrun devicectl device process launch --terminate-existing \
  --device 765FE281-0AD8-57F9-B998-22816F0CD00A com.mrkev.spacetime
```

Launching fails with "Locked" if the phone is locked; the app is still installed, so just tell the user to open it.

## Testing in the Simulator (only when asked)

Only do this when the user asks you to test something yourself; otherwise they test on the phone. You can drive the app in the iOS Simulator: `xcrun simctl` runs the simulator (boot, launch, screenshots, fake location, permissions) but can't tap, swipe, or type, so the taps happen in an XCUITest. `scripts/uitests/` in `packages/app/` has everything:

- `run.sh [testName ...]` does the whole run:
  - generates `ios/` if it's missing and adds the UI test target;
  - boots a simulator and starts Metro if it isn't running;
  - builds a Debug build into `ios/build-uitests` and reinstalls it, so every run starts from a fresh install;
  - grants Calendar, Reminders, and location access;
  - runs the tests and prints the results and the files they wrote.

  The first build takes several minutes; later ones take about a minute. Set these to change it:
  - `SHOTS` chooses the output folder. It's emptied first, so use your scratchpad.
  - `SIMULATOR_ID` chooses the simulator.
  - `KEEP_APP_DATA=1` keeps the app's saved data between runs. Tests then start wherever the last run left the app; the Time tab, for example, reopens at the level it was last on.

- `SpacetimeUITests.swift` holds the tests and their helpers:
  - `shot(name)` saves a screenshot.
  - `note(name, text)` saves text, such as element frames.
  - `tree()` saves the accessibility tree.
  - `openToday()` opens today's day view.
  - A failing test saves `failure.png` and `failure.txt` (the tree) automatically.

  Add a test for what you're checking and run just that one. Remove one-off tests before committing; keep helpers and tests worth rerunning. Any other `.swift` file in the folder is compiled in too.

- `add-target.rb` adds the `SpacetimeUITests` target to the generated Xcode project, pointing at the Swift files in the repo. `expo prebuild --clean` drops the target, but `run.sh` adds it back each run. Never put test files in `ios/`; prebuild deletes them.
- The test opens the dev client with flags (`__expo_disable_onboarding`, `__expo_disable_auto_launch`, `__expo_disable_fab`) that keep the developer menu and the floating "Tools" button from covering the app. On a fresh install the menu otherwise opens over the tab bar, and the button covers the day view's "+". If you see either in a screenshot, check that `setUp` still passes those flags.

Look at the screenshots with your file-reading tool, which shows images. Things to know:

- **Finding elements:** an RN `accessibilityLabel` becomes the element's label and a `testID` its identifier, so query by those (`app.buttons["Add"]`, `app.tabBars.buttons["Time"]`, `app.textFields["Title"]`). When a query finds nothing, call `tree()` and search the saved text for the element. Prefer `waitForExistence(timeout:)` over `sleep`. If an element you need has no label, adding an `accessibilityLabel` (or `testID`) to the component is fine.
- **Navigate by tapping.** Opening `spacetime://` links in the dev client didn't reliably reach a screen.
- **The Debug build needs Metro.** The test's `setUp` points the dev client at `localhost:8081`. If another agent's Metro is already on :8081 for this checkout, `run.sh` uses it. If Metro is serving stale code (its watcher sometimes misses edits), stop it only if you started it; otherwise say so.
- **Don't take over a simulator someone else is using.** Another agent may be using the booted simulator. If it is, pass a different `SIMULATOR_ID` (`xcrun simctl list devices available`).
- **The Simulator has its own Calendar and Reminders**, which start empty. Create the events or reminders a test needs, in the test or through the app. Set a location with `xcrun simctl location <id> set <lat>,<lng>`.
- **Saved app state** (such as the day view's zoom) is in a SQLite key-value table: `sqlite3 "$(xcrun simctl get_app_container <id> com.mrkev.spacetime data)/Documents/SQLite/ExpoSQLiteStorage" "select key from storage"`. Terminate the app before changing it.
- **Keyboard-layout bugs often don't show up.** With a hardware keyboard connected, the Simulator hides the on-screen keyboard. Leave those to the phone unless asked.
- Don't install other tools, such as `idb`, for this, and don't run UI tests on the phone.

## Rules

- If `ios/` and `android/` directories do not exist, they are generated (Continuous Native Generation). Never create or edit them by hand — configure native behavior in `app.json` and config plugins.
- Expo Go only includes its bundled native modules, and this app needs native code it doesn't have, so it doesn't run in Expo Go. After adding a library with native code, prebuild and rebuild as described above.
- Prefer recommended Expo modules over third-party libraries, and check your available skills before adding dependencies. Docs: https://docs.expo.dev/versions/latest/index.md

## Working alongside other agents

- Other agents often work in this checkout at the same time, so the working tree may hold changes that aren't yours. Never revert, stash, `git checkout`, or `git restore` files you didn't change, and stage your own files by path rather than with `git add -A` or `git commit -a`.
- Commit (to `main`) only when the user says "commit", and push only when they say "commit and push".

## Gotchas

- **New routes fail the typecheck until Metro runs.** Typed routes in `.expo/types/router.d.ts` are only regenerated by the dev server, so after adding a route file, start `CI=1 pnpm expo start` in `packages/app/` until that file mentions the new route, then stop it.
- **Patching a dependency:** `pnpm patch <pkg>@<version> --edit-dir <dir>`, edit the files in `<dir>`, then `pnpm patch-commit <dir>`. Patches live in `patches/` and are listed under `patchedDependencies` in `pnpm-workspace.yaml`. A patch that changes native code needs a prebuild and rebuild.
- **expo-calendar reminders:** reminders from `list.listReminders()` are bare native objects that skip expo-calendar's JS wrapper, so `update` takes ISO date strings and a second argument naming the fields to clear. A reminder's `id` (`calendarItemIdentifier`) can change when Reminders resyncs; `externalId` (patched in) is stable across devices but can be missing. Key anything you store about a reminder on both, as `src/time/reminderMeta.ts` does.
- **Keyboards in modal sheets:** don't use `automaticallyAdjustKeyboardInsets`; inside a sheet with a header it scrolls the form up under the header. Pad the bottom of the scroll content with `useKeyboardHeight()` from `src/lib/keyboard.ts` instead.
- **Shell:** `ls` is aliased to `ls -l`, so don't capture its output in scripts; macOS has no `timeout` command; and zsh expands unquoted globs like `--include=*.tsx`, so quote them.
