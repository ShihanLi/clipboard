#!/bin/zsh
# Builds a signed, notarized Clipboard.dmg for distribution.
#
# One-time setup:
#   1. Create a "Developer ID Application" certificate:
#      Xcode → Settings → Accounts → Manage Certificates → +
#   2. Store notarization credentials (uses an app-specific password from appleid.apple.com):
#      xcrun notarytool store-credentials clipboard-notary --apple-id <you> --team-id <TEAMID>
#
# Usage: ./release.sh
set -e
cd "$(dirname "$0")"
PROFILE=${NOTARY_PROFILE:-clipboard-notary}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
APP=build/Clipboard.app

APP_ID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
[[ -n "$APP_ID" ]] || { echo "No 'Developer ID Application' certificate found (see setup above)."; exit 1; }

./build.sh
codesign --force --options runtime --timestamp --sign "$APP_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

OUT=build/Clipboard-$VERSION.dmg
STAGE=build/dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Clipboard" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$STAGE"
codesign --sign "$APP_ID" --timestamp "$OUT"

xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$OUT"
spctl --assess --type open --context context:primary-signature -v "$OUT" || true

echo "\nReady: $OUT"
echo "Publish with: gh release create v$VERSION $OUT --title \"Clipboard $VERSION\""
