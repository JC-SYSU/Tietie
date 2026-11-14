#!/usr/bin/env bash
# Build a Release copy of Tietie.app and pack it into a DMG.
#
# No Apple Developer account is used. The app is ad-hoc signed, so on first
# launch the user has to right-click > Open, or run:
#   xattr -dr com.apple.quarantine /Applications/Tietie.app
#
# Output: build/release/Tietie-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Tietie/Info.plist)"
BUILD="$ROOT/build/release"
DERIVED="$ROOT/build/DerivedData"
DMG="$BUILD/Tietie-${VERSION}.dmg"

echo "==> Generating Tietie.xcodeproj"
xcodegen generate

echo "==> Building Release"
rm -rf "$DERIVED"
xcodebuild -project Tietie.xcodeproj -scheme Tietie -configuration Release \
  -derivedDataPath "$DERIVED" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
  build

APP="$(find "$DERIVED/Build/Products/Release" -maxdepth 1 -name "Tietie.app" -print -quit)"
if [[ -z "$APP" ]]; then
  echo "Tietie.app not found under $DERIVED/Build/Products/Release" >&2
  exit 1
fi

echo "==> Packaging DMG"
mkdir -p "$BUILD"
rm -f "$DMG"
hdiutil create -volname "贴贴" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> Done: $DMG"
