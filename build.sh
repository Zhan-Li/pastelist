#!/bin/bash
# Builds PasteList.app. No Xcode required — Command Line Tools are enough.
#
#   ./build.sh          # universal build into build/PasteList.app
#   ./build.sh --run    # build, then (re)launch it
set -euo pipefail

APP_NAME="PasteList"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
BUNDLE="$BUILD/$APP_NAME.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Universal binary. Set PASTELIST_ARCH=native for a fast single-slice dev build;
# release builds must ship both or Intel Macs cannot launch the app at all.
compile() {
	swiftc \
		-O \
		-parse-as-library \
		-swift-version 5 \
		-target "$1"-apple-macos14.0 \
		-framework SwiftUI \
		-framework AppKit \
		"$ROOT"/Sources/*.swift \
		-o "$2"
}

if [ "${PASTELIST_ARCH:-universal}" = "native" ]; then
	compile "$(uname -m)" "$BUNDLE/Contents/MacOS/$APP_NAME"
else
	compile arm64 "$BUILD/$APP_NAME-arm64"
	compile x86_64 "$BUILD/$APP_NAME-x86_64"
	lipo -create "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64" \
		-output "$BUNDLE/Contents/MacOS/$APP_NAME"
	rm -f "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64"
fi

# PasteList needs no privacy grants, so an ad-hoc signature is fine for local
# builds. Set PASTELIST_SIGN_IDENTITY to a Developer ID certificate to ship a
# build that opens without the right-click ▸ Open dance.
IDENTITY="${PASTELIST_SIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ] && security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
	codesign --force --sign "$IDENTITY" --timestamp=none "$BUNDLE"
else
	codesign --force --sign - --timestamp=none "$BUNDLE"
fi

echo "Built $BUNDLE"

if [ "${1:-}" = "--run" ]; then
	pkill -x "$APP_NAME" 2>/dev/null || true
	open "$BUNDLE"
	echo "Launched — look for the checklist icon in the menu bar."
fi
