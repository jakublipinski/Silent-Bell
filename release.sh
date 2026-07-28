#!/bin/bash
# Build a signed .ipa ready for upload to App Store Connect.
#
# Usage:
#   ./release.sh
#
# Output: build-export/SilentBell.ipa
#
# Archive the CONTAINER (an iOS target), not the watch app. A watch-only app is
# watch-only at runtime; at delivery it ships as an iOS app with the watch app
# embedded under Watch/. Archiving the watch target alone yields an archive that
# Xcode will not distribute to the App Store — see project.yml for the full
# story and the symptoms, which are thoroughly unhelpful.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# shellcheck source=/dev/null
[ -f ./secrets.env ] && . ./secrets.env
: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM in secrets.env}"

ARCHIVE="./build-archive-dist/SilentBell.xcarchive"
OUT="./build-export"
APP="$ARCHIVE/Products/Applications/SilentBell.app"

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Archiving container (iOS) with the watch app embedded"
rm -rf "$ARCHIVE"
xcodebuild -project SilentBell.xcodeproj -scheme SilentBell \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  archive >/dev/null

# An archive whose container failed to embed the watch app still builds, still
# signs, and produces an .ipa containing no app at all.
[ -d "$APP/Watch" ] || { echo "ERROR: no Watch/ inside the container" >&2; exit 1; }
echo "    embedded: $(basename "$APP"/Watch/*.app)"

echo "==> Exporting for the App Store"
rm -rf "$OUT"
cat > /tmp/SilentBellExport.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist /tmp/SilentBellExport.plist \
  -exportPath "$OUT" -allowProvisioningUpdates >/dev/null

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")

cat <<NOTE

==> $OUT/SilentBell.ipa  —  version $VERSION ($BUILD)

    Upload with Transporter (Mac App Store): drag the .ipa in, then Deliver.
    Or from Xcode: Organizer -> Distribute App -> App Store Connect.

    Bump CURRENT_PROJECT_VERSION in project.yml (BOTH targets) before every
    re-upload — App Store Connect rejects a build number it has already seen.

NOTE
