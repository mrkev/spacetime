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

## Rules

- If `ios/` and `android/` directories do not exist, they are generated (Continuous Native Generation). Never create or edit them by hand — configure native behavior in `app.json` and config plugins.
- Expo Go only includes its bundled native modules, and this app needs native code it doesn't have, so it doesn't run in Expo Go. After adding a library with native code, prebuild and rebuild as described above.
- Prefer recommended Expo modules over third-party libraries, and check your available skills before adding dependencies. Docs: https://docs.expo.dev/versions/latest/index.md
