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

# Read the version from the EXPORTED ipa, not from the archive. Xcode's export
# defaults to manageAppVersionAndBuildNumber=true: it asks App Store Connect what
# build numbers already exist and rewrites CFBundleVersion past them, unifying
# container and watch app on the way. So the archive can say 2 while the shipped
# binary says 3, and only the latter is the truth worth printing or filing under.
rm -rf /tmp/SilentBellVersionPeek && mkdir -p /tmp/SilentBellVersionPeek
unzip -qo "$OUT/SilentBell.ipa" "Payload/SilentBell.app/Info.plist" -d /tmp/SilentBellVersionPeek
SHIPPED_PLIST=/tmp/SilentBellVersionPeek/Payload/SilentBell.app/Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SHIPPED_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SHIPPED_PLIST")

# Keep every delivered artifact. release.sh wipes build-export/ on each run, so an
# uploaded build used to be unrecoverable the moment the next one was made — which
# is exactly when you most want to inspect what App Review actually received.
KEEP="./releases/SilentBell-${VERSION}-${BUILD}.ipa"
mkdir -p ./releases
cp "$OUT/SilentBell.ipa" "$KEEP"

cat <<NOTE

==> $KEEP  —  version $VERSION ($BUILD)
    (also at $OUT/SilentBell.ipa, which the next run overwrites)

    Upload with Transporter (Mac App Store): drag the .ipa in, then Deliver.
    Or from Xcode: Organizer -> Distribute App -> App Store Connect.

    The build number above is assigned at export time by App Store Connect, not
    by CURRENT_PROJECT_VERSION in project.yml — no need to bump it by hand.

NOTE
