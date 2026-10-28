#!/bin/bash
# Builds the Debug app and the UI tests, installs them in the iOS Simulator, and runs the tests.
# Only for when the user asks for testing in the Simulator; see "Testing in the Simulator" in
# AGENTS.md.
#
# Usage, from packages/app:
#   scripts/uitests/run.sh                    # every test
#   scripts/uitests/run.sh testSmoke ...      # only these tests (or Class/testName)
#
# Environment:
#   SHOTS          folder for screenshots, notes, and logs (default: $TMPDIR/spacetime-uitests).
#                  It's emptied first.
#   SIMULATOR_ID   simulator to use (default: the booted iPhone, or else the newest available one)
#   KEEP_APP_DATA  set to 1 to keep the app's saved data (places, the Time tab's last level, and so
#                  on). Otherwise the app is reinstalled, so every run starts from the same state.
#                  Calendar and Reminders data belong to the simulator and are kept either way.
set -u

cd "$(dirname "$0")/../.."
SHOTS=${SHOTS:-${TMPDIR:-/tmp}/spacetime-uitests}
SHOTS=${SHOTS%/}
BUNDLE_ID=com.mrkev.spacetime
DERIVED=ios/build-uitests

rm -rf "$SHOTS"
mkdir -p "$SHOTS"

# 1. The native project. ios/ is generated; make it if it's missing.
if [ ! -d ios/Spacetime.xcworkspace ]; then
  echo "Generating ios/..."
  CI=1 pnpm expo prebuild --platform ios > "$SHOTS/prebuild.log" 2>&1 ||
    { echo "prebuild failed; see $SHOTS/prebuild.log"; exit 1; }
fi

# 2. The UI test target. The xcodeproj gem comes with Homebrew's CocoaPods.
if ruby -e 'require "xcodeproj"' 2>/dev/null; then
  ruby scripts/uitests/add-target.rb ios/Spacetime.xcodeproj || exit 1
else
  GEM_HOME="$(brew --prefix cocoapods)/libexec" "$(brew --prefix ruby)/bin/ruby" \
    scripts/uitests/add-target.rb ios/Spacetime.xcodeproj || exit 1
fi

# 3. A simulator.
SIM=${SIMULATOR_ID:-}
if [ -z "$SIM" ]; then
  SIM=$(xcrun simctl list devices booted | grep -m1 -E '^ +iPhone' | grep -oE '[0-9A-F-]{36}')
fi
if [ -z "$SIM" ]; then
  SIM=$(xcrun simctl list devices available | grep -E '^ +iPhone' | tail -1 | grep -oE '[0-9A-F-]{36}')
fi
[ -n "$SIM" ] || { echo "no iPhone simulator found"; exit 1; }
xcrun simctl bootstatus "$SIM" -b > /dev/null || exit 1
echo "Simulator: $(xcrun simctl list devices | grep "$SIM" | sed -E 's/^ +//')"

# 4. Metro. A Debug build loads its JavaScript from it. Reuse one on :8081 if it's running (it has
#    to be serving this checkout), otherwise start one and stop it when done.
if lsof -iTCP:8081 -sTCP:LISTEN > /dev/null 2>&1; then
  echo "Using the Metro already on :8081"
else
  CI=1 pnpm expo start --dev-client --port 8081 > "$SHOTS/metro.log" 2>&1 &
  METRO_PID=$!
  trap 'pkill -P $METRO_PID 2>/dev/null; kill $METRO_PID 2>/dev/null' EXIT
  until grep -q "Waiting on" "$SHOTS/metro.log"; do
    kill -0 $METRO_PID 2>/dev/null || { echo "Metro exited; see $SHOTS/metro.log"; exit 1; }
    sleep 1
  done
fi
# Bundle once up front, so the app doesn't time out waiting for the first bundle.
curl -s -o /dev/null "http://localhost:8081/index.ts.bundle?platform=ios&dev=true&minify=false&transform.engine=hermes&transform.routerRoot=src%2Fapp&unstable_transformProfile=hermes-stable" &
CURL_PID=$!

# 5. Build, install, and grant access up front so permission prompts don't block the tests.
echo "Building (the first build takes several minutes)..."
xcodebuild build-for-testing -workspace ios/Spacetime.xcworkspace -scheme Spacetime \
  -configuration Debug -destination "id=$SIM" -derivedDataPath "$DERIVED" \
  > "$SHOTS/build.log" 2>&1 || { grep -E "error:" "$SHOTS/build.log" | head -20; echo "build failed; see $SHOTS/build.log"; exit 1; }
[ "${KEEP_APP_DATA:-}" = 1 ] || xcrun simctl uninstall "$SIM" "$BUNDLE_ID"
xcrun simctl install "$SIM" "$DERIVED/Build/Products/Debug-iphonesimulator/Spacetime.app" || exit 1
for service in calendar reminders location; do
  xcrun simctl privacy "$SIM" grant "$service" "$BUNDLE_ID"
done
wait $CURL_PID

# 6. Test.
only=()
for t in "$@"; do
  case $t in
    */*) only+=("-only-testing:SpacetimeUITests/$t") ;;
    *) only+=("-only-testing:SpacetimeUITests/SpacetimeUITests/$t") ;;
  esac
done
echo "Testing..."
TEST_RUNNER_SHOTS=$SHOTS xcodebuild test-without-building -workspace ios/Spacetime.xcworkspace \
  -scheme Spacetime -configuration Debug -destination "id=$SIM" -derivedDataPath "$DERIVED" \
  ${only[@]+"${only[@]}"} > "$SHOTS/test.log" 2>&1
status=$?

grep -E "\.swift:[0-9]+: error|Test Case .*(passed|failed)" "$SHOTS/test.log" | cut -c1-300
echo "exit $status; log: $SHOTS/test.log"
echo "Output in $SHOTS:"
ls "$SHOTS" | grep -vE '^(prebuild|metro|build|test)\.log$' | sed 's/^/  /'
exit $status
