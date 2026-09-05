#!/bin/bash
# App Store screenshots, one set per language, from a watch simulator.
#
# The language and the app's first-run state are both set with *launch
# arguments* rather than by rewriting preferences: NSUserDefaults reads the
# argument domain at highest priority, so `-AppleLanguages "(de)"` and
# `-hasSeenIntro YES` take effect for exactly one launch and leave no state
# behind. That keeps every capture independent — no erase, no reboot.
#
# Only two screens are reachable this way: the first-run intro and the main
# Stopped screen. Anything past them (Active, the settings sub-screens, About)
# needs a tap or a scroll, and simctl cannot send either. Automating those
# needs Accessibility permission for whatever runs this script, or an XCUITest
# target — see the note at the end.
#
# Usage:
#   ./shots.sh              # Ultra 3 (49mm)
#   ./shots.sh all          # every available watch simulator size
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
# shellcheck source=/dev/null
[ -f ./secrets.env ] && . ./secrets.env

BID="app.silentbell.watch.watchkitapp"
DERIVED="./build-sim-release"
OUT="./screenshots"
LANGS="en de ja fr es"

# Locale per language: the app has no locale-dependent formatting beyond the
# clock, but passing it keeps the simulator's own UI consistent with the app.
locale_for() { case "$1" in en) echo en_US;; de) echo de_DE;; ja) echo ja_JP;;
                            fr) echo fr_FR;; es) echo es_ES;; esac; }

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Building Release for the simulator"
xcodebuild -project SilentBell.xcodeproj -scheme SilentBellWatch \
  -configuration Release -destination "generic/platform=watchOS Simulator" \
  -derivedDataPath "$DERIVED" DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
  build >/dev/null
APP=$(find "$DERIVED/Build/Products" -name "SilentBellWatch.app" -path "*simulator*" | head -1)
[ -n "$APP" ] || { echo "ERROR: built app not found" >&2; exit 1; }

if [ "${1:-}" = "all" ]; then
  DEVICES=$(xcrun simctl list devices available \
    | awk '/-- watchOS/{f=1;next} /^-- /{f=0} f' \
    | sed -n 's/^ *\(.*\) (\([0-9A-Fa-f-]\{36\}\)) (.*/\2|\1/p')
else
  DEVICES=$(xcrun simctl list devices available \
    | awk '/-- watchOS/{f=1;next} /^-- /{f=0} f' \
    | sed -n 's/^ *\(.*Ultra.*\) (\([0-9A-Fa-f-]\{36\}\)) (.*/\2|\1/p' | head -1)
fi
[ -n "$DEVICES" ] || { echo "ERROR: no watchOS simulator found" >&2; exit 1; }

shot() {   # udid, outfile, lang, extra launch args...
  local udid="$1" out="$2" lang="$3"; shift 3
  xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BID" \
    -AppleLanguages "($lang)" -AppleLocale "$(locale_for "$lang")" "$@" >/dev/null 2>&1
  sleep 4                       # let SwiftUI lay out before the shutter
  xcrun simctl io "$udid" screenshot "$out" >/dev/null 2>&1
}

while IFS='|' read -r udid name; do
  [ -n "$udid" ] || continue
  # Directory name from the device: "Apple Watch Ultra 3 (49mm)" -> "Ultra-3-49mm"
  slug=$(echo "$name" | sed 's/Apple Watch //; s/[() ]/-/g; s/--*/-/g; s/-$//')
  dir="$OUT/$slug"; mkdir -p "$dir"
  echo "==> $name"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP" >/dev/null
  for lang in $LANGS; do
    shot "$udid" "$dir/$lang-1-intro.png"   "$lang" -hasSeenIntro NO
    shot "$udid" "$dir/$lang-2-stopped.png" "$lang" -hasSeenIntro YES
    echo "    $lang"
  done
  size=$(sips -g pixelWidth -g pixelHeight "$dir/en-2-stopped.png" \
         | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')
  echo "    -> $dir  ($size)"
done <<< "$DEVICES"

cat <<'NOTE'

==> Done. Two screens per language: the first-run intro and the Stopped screen.

    Not captured, because simctl cannot tap or scroll:
      Active state, the settings sub-screens, the About screen.
    To add them, grant Accessibility permission to your terminal
    (System Settings -> Privacy & Security -> Accessibility) and drive the
    Simulator with AppleScript, or take them by hand from ./check-ui.sh.
NOTE
