#!/bin/bash
# Builds PasteList.app and packages it as an installable .dmg in dist/.
#
#   ./release.sh          # version taken from Info.plist
#   ./release.sh 1.1.0    # explicit version, also written into the bundle
set -euo pipefail

APP_NAME="PasteList"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
BUNDLE="$BUILD/$APP_NAME.app"

VERSION="${1:-}"
if [ -n "$VERSION" ]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT/Resources/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$ROOT/Resources/Info.plist"
fi

"$ROOT/build.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE/Contents/Info.plist")"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

# Staging folder with an /Applications symlink, so the DMG opens with the
# familiar drag-to-install layout.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "Packaged $DMG"
