#!/bin/bash
# App Store screenshots: five screens per language, from a watch simulator.
#
# Two mechanisms, because neither alone is enough.
#
# 1. Launch arguments choose the language and the first-run state.
#    NSUserDefaults reads the argument domain at highest priority, so
#    -AppleLanguages "(de)" and -hasSeenIntro NO apply to exactly one launch and
#    leave nothing behind. Note the asymmetry: -hasSeenIntro NO is reliable
#    because it *forces* the intro, while relying on YES is not — if a launch
#    races a terminate the app can come up without our arguments and fall back
#    to the persisted value. So setup taps "Get started" once to persist it.
#
# 2. Synthesised taps and scrolls reach everything past those two screens:
#    Active, the settings list, About. This needs Accessibility permission for
#    the *responsible* app — the terminal or editor running this script, not
#    Claude.app and not Simulator. System Settings -> Privacy & Security ->
#    Accessibility. It does NOT need Automation permission, because we drive
#    the UI with CGEvent and NSRunningApplication rather than Apple events.
#
# Coordinates are given in screenshot pixels and converted against the watch
# screen's live rect, read from the Accessibility tree. The screenshot is
# exactly 2x that rect, and reading it each time means a moved window is
# harmless.
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
BIN=".build-tools"
LANGS="en de ja fr es"

# Screen-space Y of each thing we tap, in screenshot pixels.
Y_PRIMARY=313      # Start / Stop — the one big button
Y_ALLOW=386        # "Allow" in the notification permission alert
Y_GETSTARTED=367   # "Get started", once the intro is scrolled to its end
Y_ABOUT=283        # the About row, after scrolling the list by SCROLL_FULL
X_CENTRE=211
SCROLL_SETTINGS=-200
SCROLL_FULL=-260
SCROLL_INTRO=-400

echo "==> Building helper tools"
mkdir -p "$BIN"
swiftc -O tools/siminput.swift     -o "$BIN/siminput"
swiftc -O tools/simwatchrect.swift -o "$BIN/simwatchrect"
"$BIN/siminput" check 0 0 || { echo "ERROR: grant Accessibility to this terminal/editor" >&2; exit 1; }

echo "==> Generating project"
xcodegen generate >/dev/null
echo "==> Building Release for the simulator"
xcodebuild -project SilentBell.xcodeproj -scheme SilentBellWatch \
  -configuration Release -destination "generic/platform=watchOS Simulator" \
  -derivedDataPath "$DERIVED" DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" build >/dev/null
APP=$(find "$DERIVED/Build/Products" -name "SilentBellWatch.app" -path "*simulator*" | head -1)
[ -n "$APP" ] || { echo "ERROR: built app not found" >&2; exit 1; }

locale_for() { case "$1" in en) echo en_US;; de) echo de_DE;; ja) echo ja_JP;;
                            fr) echo fr_FR;; es) echo es_ES;; esac; }

UDID=""   # set per device below
launch() { # lang, extra args...
  local lang="$1"; shift
  # Terminate twice with a real pause. While an extended runtime session is
  # alive the app survives the first kill, and `simctl launch` then attaches to
  # the running instance and silently ignores our arguments — which shows up as
  # a perfectly plausible screenshot in the wrong language.
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  sleep 2
  xcrun simctl launch "$UDID" "$BID" \
    -AppleLanguages "($lang)" -AppleLocale "$(locale_for "$lang")" "$@" >/dev/null 2>&1
  sleep 4
}
tap()    { read -r rx ry _ _ <<< "$("$BIN/simwatchrect")"
           "$BIN/siminput" click "$((rx + X_CENTRE / 2))" "$((ry + $1 / 2))"; }
scroll() { read -r rx ry _ _ <<< "$("$BIN/simwatchrect")"
           "$BIN/siminput" scroll "$((rx + X_CENTRE / 2))" "$((ry + 200))" "$1"; }
snap()   { xcrun simctl io "$UDID" screenshot "$1" >/dev/null 2>&1; }

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

while IFS='|' read -r udid name; do
  [ -n "$udid" ] || continue
  UDID="$udid"
  slug=$(echo "$name" | sed 's/Apple Watch //; s/[() ]/-/g; s/--*/-/g; s/-$//')
  dir="$OUT/$slug"; mkdir -p "$dir"
  echo "==> $name"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP" >/dev/null
  open -a Simulator; sleep 3

  # --- Setup, idempotent. Forcing the intro makes this deterministic whatever
  # --- state the app was left in.
  echo "    setup: persisting first-run, granting notifications"
  launch en -hasSeenIntro NO
  scroll "$SCROLL_INTRO"; sleep 1; tap "$Y_GETSTARTED"; sleep 2
  tap "$Y_PRIMARY"; sleep 3            # start a session -> permission alert
  tap "$Y_ALLOW";   sleep 3            # harmless if already granted

  for lang in $LANGS; do
    # Order matters: everything reachable without starting a session comes
    # first, and the session-starting tap is last. Starting one early makes the
    # app outlive the next terminate and poisons every capture after it.
    launch "$lang" -hasSeenIntro NO
    snap "$dir/$lang-1-intro.png"

    launch "$lang"
    snap "$dir/$lang-2-stopped.png"

    scroll "$SCROLL_SETTINGS"; sleep 2
    snap "$dir/$lang-4-settings.png"

    scroll $((SCROLL_FULL - SCROLL_SETTINGS)); sleep 2
    tap "$Y_ABOUT"; sleep 3
    snap "$dir/$lang-5-about.png"

    launch "$lang"
    tap "$Y_PRIMARY"; sleep 5
    snap "$dir/$lang-3-active.png"
    echo "    $lang"
  done
  xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
  size=$(sips -g pixelWidth -g pixelHeight "$dir/en-2-stopped.png" \
         | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')
  echo "    -> $dir  ($size)"
done <<< "$DEVICES"

echo
echo "==> Done. Do not move or resize the Simulator window while this runs."
