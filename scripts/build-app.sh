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

ACTOOL_TMP="$(mktemp -d)"
trap 'rm -rf "$ACTOOL_TMP"' EXIT

ICON_COMPILED=0
if command -v xcrun >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then
  if [[ -d "$ROOT_DIR/AppResources/AppIcon.icon" ]]; then
    if xcrun actool "$ROOT_DIR/AppResources/AppIcon.icon" \
      --compile "$APP_BUNDLE/Contents/Resources" \
      --app-icon AppIcon \
      --include-all-app-icons \
      --enable-on-demand-resources NO \
      --development-region en \
      --target-device mac \
      --platform macosx \
      --minimum-deployment-target 14.0 \
      --output-partial-info-plist "$ACTOOL_TMP/actool.plist" \
      --output-format human-readable-text \
      --errors --warnings >"$ACTOOL_TMP/actool-icon.log" 2>&1 \
      && [[ -s "$APP_BUNDLE/Contents/Resources/Assets.car" ]]; then
      ICON_COMPILED=1
    else
      echo "Note: actool could not compile AppIcon.icon (falling back to Assets.xcassets / AppIcon.icns):" >&2
      cat "$ACTOOL_TMP/actool-icon.log" >&2 || true
    fi
  fi

  if [[ "$ICON_COMPILED" -eq 0 && -d "$ROOT_DIR/AppResources/Assets.xcassets" ]]; then
    if xcrun actool "$ROOT_DIR/AppResources/Assets.xcassets" \
      --compile "$APP_BUNDLE/Contents/Resources" \
      --app-icon AppIcon \
      --include-all-app-icons \
      --enable-on-demand-resources NO \
      --development-region en \
      --target-device mac \
      --platform macosx \
      --minimum-deployment-target 14.0 \
      --output-partial-info-plist "$ACTOOL_TMP/actool.plist" \
      --output-format human-readable-text \
      --errors --warnings >"$ACTOOL_TMP/actool-xcassets.log" 2>&1 \
      && [[ -s "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]]; then
      ICON_COMPILED=1
    else
      echo "Note: actool could not compile Assets.xcassets (falling back to prebuilt AppIcon.icns):" >&2
      cat "$ACTOOL_TMP/actool-xcassets.log" >&2 || true
    fi
  fi
fi

if [[ ! -s "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/AppResources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Ad-hoc code signing SpacedOut.app..."
codesign --force --deep --sign - --entitlements "$ROOT_DIR/AppResources/SpacedOut.entitlements" "$APP_BUNDLE"

echo "==> Built: $APP_BUNDLE"
echo "    Run with: open \"$APP_BUNDLE\""
