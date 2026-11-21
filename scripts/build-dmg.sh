#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -P "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: SpacedOut.dmg can only be built on macOS." >&2
  exit 1
fi

CONFIG="${1:-release}"
BUILD_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/SpacedOut.app"
DMG_PATH="$BUILD_DIR/SpacedOut.dmg"

"$ROOT_DIR/scripts/build-app.sh" "$CONFIG"

if [[ ! -d "$APP_BUNDLE" || ! -x "$APP_BUNDLE/Contents/MacOS/SpacedOut" ]]; then
  echo "Error: Built app bundle missing executable at $APP_BUNDLE/Contents/MacOS/SpacedOut" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

echo "==> Staging $DMG_PATH..."
ditto "$APP_BUNDLE" "$STAGE_DIR/SpacedOut.app"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "SpacedOut" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

xattr -cr "$DMG_PATH" >/dev/null 2>&1 || true

echo "==> Built DMG: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"
echo "    Open with: open \"$DMG_PATH\""
