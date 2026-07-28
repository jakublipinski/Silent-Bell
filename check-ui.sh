#!/bin/bash
# Build the RELEASE configuration and install it on every available watch
# simulator, for manual UI review across screen sizes.
#
# Release, not Debug, on purpose: Release is what App Review and customers get.
# Notably it has NO developer "Log" screen — that is compiled out by `#if DEBUG` —
# so this is also how you confirm the debug surface really is absent.
#
# Usage:
#   ./check-ui.sh            # build + install everywhere, leave apps fresh
#   ./check-ui.sh --erase    # wipe each simulator first, for a true first-run
#                            # (shows the intro screen and permission prompt)
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# shellcheck source=/dev/null
[ -f ./secrets.env ] && . ./secrets.env

BUNDLE_ID="app.silentbell.watch"
DERIVED="./build-sim-release"
ERASE=${1:-}

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Building Release for the simulator"
xcodebuild -project SilentBell.xcodeproj -scheme SilentBell \
  -configuration Release \
  -destination "generic/platform=watchOS Simulator" \
  -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
  build >/dev/null

APP=$(find "$DERIVED/Build/Products" -name "SilentBell.app" -path "*simulator*" | head -1)
[ -n "$APP" ] || { echo "ERROR: built app not found" >&2; exit 1; }
echo "    $APP"

# Every available watchOS simulator, in the order simctl lists them.
DEVICES=$(xcrun simctl list devices available \
  | awk '/-- watchOS/{f=1;next} /^-- /{f=0} f' \
  | sed -n 's/^ *\(.*\) (\([0-9A-Fa-f-]\{36\}\)) (.*/\2|\1/p')

[ -n "$DEVICES" ] || { echo "ERROR: no watchOS simulators available" >&2; exit 1; }

while IFS='|' read -r udid name; do
  [ -n "$udid" ] || continue
  echo "==> $name"
  if [ "$ERASE" = "--erase" ]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl erase "$udid" >/dev/null
  fi
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP" >/dev/null
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
done <<< "$DEVICES"

open -a Simulator
cat <<'NOTE'

==> Installed on every simulator size. Simulator.app is now open.

    Switch size:   Simulator menu → File → Open Simulator → (pick a watch)
    Scroll:        two-finger swipe on the trackpad = Digital Crown
    Home:          Simulator menu → Device → Home

    Check on EACH size, smallest first:
      • Intro screen — all text readable, "Get started" reachable by scrolling
      • Stopped      — mark, "Stopped", Start button, settings rows below
      • Settings     — no truncated labels ("Taps per hour", "Min. gap", "Tap Type")
      • Active       — tap Start; "Next tap around HH:MM" fits on one line
      • Paused/About — About text readable end to end
      • There must be NO "Log" row. If you see one, this is not a Release build.

NOTE
