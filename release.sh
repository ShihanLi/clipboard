#!/bin/zsh
# Builds a signed, notarized Clipboard.dmg (or Clipboard.pkg with --pkg) for distribution.
#
# One-time setup:
#   1. Create a "Developer ID Application" certificate (and "Developer ID Installer" for --pkg):
#      Xcode → Settings → Accounts → Manage Certificates → +
#   2. Store notarization credentials (uses an app-specific password from appleid.apple.com):
#      xcrun notarytool store-credentials clipboard-notary --apple-id <you> --team-id <TEAMID>
#
# Usage: ./release.sh [--pkg]
set -e
cd "$(dirname "$0")"
PROFILE=${NOTARY_PROFILE:-clipboard-notary}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
APP=build/Clipboard.app

identity() {
  local args=(-v); [[ -n "$2" ]] && args+=(-p "$2")
  security find-identity "${args[@]}" | awk -F'"' -v k="$1" '$2 ~ k {print $2; exit}'
}
APP_ID=$(identity "Developer ID Application" codesigning)
[[ -n "$APP_ID" ]] || { echo "No 'Developer ID Application' certificate found (see setup above)."; exit 1; }

./build.sh
codesign --force --options runtime --timestamp --sign "$APP_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [[ "$1" == "--pkg" ]]; then
  INST_ID=$(identity "Developer ID Installer")
  [[ -n "$INST_ID" ]] || { echo "No 'Developer ID Installer' certificate found (see setup above)."; exit 1; }
  OUT=build/Clipboard-$VERSION.pkg
  pkgbuild --component "$APP" --install-location /Applications \
    --identifier "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' Info.plist)" \
    --version "$VERSION" --sign "$INST_ID" --timestamp "$OUT"
else
  OUT=build/Clipboard-$VERSION.dmg
  STAGE=build/dmg
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Clipboard" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
  rm -rf "$STAGE"
  codesign --sign "$APP_ID" --timestamp "$OUT"
fi

xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$OUT"
spctl --assess --type ${${1:+install}:-open} --context context:primary-signature -v "$OUT" || true

echo "\nReady: $OUT"
echo "Publish with: gh release create v$VERSION $OUT --title \"Clipboard $VERSION\""
