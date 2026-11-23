#!/bin/zsh
# Builds Clipboard.app and installs it to /Applications.
set -e
cd "$(dirname "$0")"
APP=build/Clipboard.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  Sources/*.swift -o "$APP/Contents/MacOS/Clipboard"
cp Info.plist "$APP/Contents/Info.plist"

# Sign with a stable identity so the Accessibility permission survives rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"

if [[ "$1" == "--install" ]]; then
  pkill -x Clipboard || true
  rm -rf /Applications/Clipboard.app
  cp -R "$APP" /Applications/
  open /Applications/Clipboard.app
  echo "Installed to /Applications/Clipboard.app"
fi
