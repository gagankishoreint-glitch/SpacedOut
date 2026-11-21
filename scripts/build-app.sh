#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: SpacedOut is a native macOS 14+ app and must be built on macOS." >&2
  exit 1
fi

CONFIG="${1:-release}"
BUILD_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/SpacedOut.app"

echo "==> Running SpacedOutCore tests..."
swift test

echo "==> Building SpacedOut ($CONFIG)..."
swift build -c "$CONFIG" --product SpacedOut
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/SpacedOut"

if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: Expected binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/SpacedOut"
chmod +x "$APP_BUNDLE/Contents/MacOS/SpacedOut"
cp "$ROOT_DIR/AppResources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/AppResources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Ad-hoc code signing SpacedOut.app..."
codesign --force --deep --sign - --entitlements "$ROOT_DIR/AppResources/SpacedOut.entitlements" "$APP_BUNDLE"

echo "==> Built: $APP_BUNDLE"
echo "    Run with: open \"$APP_BUNDLE\""
