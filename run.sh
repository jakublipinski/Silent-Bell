#!/bin/bash
# Regenerate → build → install Silent Bell onto the paired Apple Watch.
# One command per development iteration.
#
# The build targets a generic watchOS destination so it never waits on the Watch;
# only the install step needs the Watch awake, unlocked, on Wi-Fi and near the Mac.
set -euo pipefail
cd "$(dirname "$0")"

export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Machine-specific values live in an untracked file so this script can be public.
# shellcheck source=/dev/null
if [ -f ./secrets.env ]; then . ./secrets.env; else
  echo "ERROR: secrets.env missing — copy secrets.env.example and fill it in." >&2; exit 1
fi

APP="./build/Build/Products/Debug-watchos/SilentBell.app"
LOG="./run.log"

exec > >(tee -a "$LOG") 2>&1
echo "===== $(date '+%Y-%m-%d %H:%M:%S') run.sh ====="

xcodegen generate

xcodebuild -project SilentBell.xcodeproj -scheme SilentBell \
  -destination "generic/platform=watchOS" \
  -allowProvisioningUpdates \
  -derivedDataPath ./build \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  build

# Retry a few times so a briefly-dozing Watch doesn't fail the run outright.
for attempt in 1 2 3 4 5; do
  if xcrun devicectl device install app --device "$WATCH_UDID" "$APP"; then
    echo "installed OK"
    exit 0
  fi
  echo "install attempt $attempt failed; wake the Watch and keep it near the Mac… retrying in 10s"
  sleep 10
done
echo "ERROR: install failed after 5 attempts — is the Watch awake, unlocked, on Wi-Fi?" >&2
exit 1
