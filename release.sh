#!/bin/bash
# Build a signed .ipa ready for upload to App Store Connect.
#
# Usage:
#   ./release.sh          # generate → archive → package → verify
#
# Output: build-export/SilentBell.ipa, to be uploaded with Transporter
# (free, Mac App Store) or `xcrun altool`.
#
# ---------------------------------------------------------------------------
# Why this does not use `xcodebuild -exportArchive`
#
# The documented path is to archive with automatic signing and then re-sign at
# export time with `-exportOptionsPlist` naming method `app-store-connect`.
# That path does not work for this app. Every attempt fails with:
#
#     error: exportArchive exportOptionsPlist error for key "method"
#            expected one {release-testing, enterprise, debugging}
#            but found app-store-connect
#
# App Store is simply absent from the methods xcodebuild considers available,
# and Xcode's own Distribute App window shows the same four choices. It is not
# the certificate, the provisioning profile, a stale archive or the account
# type — all were eliminated one at a time:
#
#   • an Apple Distribution certificate exists and is valid
#   • an explicit App Store profile exists (no device list, get-task-allow false)
#   • re-archiving after both existed changes nothing
#   • the team is not Enterprise, and has shipped App Store apps before
#
# The set is derived from the archive itself and appears to be wrong for
# watch-only archives. So this script sidesteps the re-signing step entirely:
# it archives with MANUAL distribution signing, so the app inside the archive
# is already signed exactly as the App Store requires, and then packages it.
#
# An .ipa is nothing more than a zip with the app under Payload/, so once the
# signature is right there is nothing left for exportArchive to contribute.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# shellcheck source=/dev/null
[ -f ./secrets.env ] && . ./secrets.env

: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM in secrets.env}"
: "${DIST_PROFILE:?set DIST_PROFILE in secrets.env (the App Store profile name)}"

ARCHIVE="./build-archive-dist/SilentBell.xcarchive"
OUT="./build-export"
APP="$ARCHIVE/Products/Applications/SilentBell.app"

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Archiving with distribution signing"
rm -rf "$ARCHIVE"
xcodebuild -project SilentBell.xcodeproj -scheme SilentBell \
  -configuration Release -destination 'generic/platform=watchOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$DIST_PROFILE" \
  archive >/dev/null

# Fail loudly rather than shipping something signed for development. An .ipa
# signed with a development certificate is accepted by the packager and
# rejected by App Store Connect minutes later, with a far vaguer message.
echo "==> Verifying signature"
AUTH=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
case "$AUTH" in
  "Apple Distribution:"*) echo "    $AUTH" ;;
  *) echo "ERROR: signed by '$AUTH', expected an Apple Distribution identity" >&2; exit 1 ;;
esac

# An App Store profile provisions no specific devices; a development or ad-hoc
# one lists them. This is the cheapest way to tell them apart.
security cms -D -i "$APP/embedded.mobileprovision" > /tmp/relprof.plist 2>/dev/null
if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' /tmp/relprof.plist >/dev/null 2>&1; then
  echo "ERROR: embedded profile lists devices — that is not an App Store profile" >&2
  exit 1
fi
echo "    profile: $(/usr/libexec/PlistBuddy -c 'Print :Name' /tmp/relprof.plist 2>/dev/null)"

echo "==> Packaging .ipa"
rm -rf "$OUT"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
( cd "$OUT" && zip -qry SilentBell.ipa Payload && rm -rf Payload )

codesign --verify --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")

cat <<NOTE

==> $OUT/SilentBell.ipa  —  version $VERSION ($BUILD)

    Upload with Transporter (Mac App Store): drag the .ipa in, then Deliver.
    Transporter validates first and reports specific errors; xcodebuild does not.

    Bump CURRENT_PROJECT_VERSION in project.yml before every re-upload —
    App Store Connect rejects a build number it has already seen.

NOTE
