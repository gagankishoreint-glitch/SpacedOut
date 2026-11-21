#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd -P "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: SpacedOut is a native macOS 14+ app and must be built on macOS." >&2
  exit 1
fi

CONFIG="${1:-release}"
BUILD_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$BUILD_DIR/SpacedOut.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Running SpacedOutCore tests..."
swift test

echo "==> Building SpacedOut ($CONFIG)..."
swift build -c "$CONFIG" --product SpacedOut
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/SpacedOut"

if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: Expected binary not found at $BIN_PATH" >&2
  exit 1
fi

WORK_TMP="$(mktemp -d)"
trap 'rm -rf "$WORK_TMP"' EXIT
STAGE_APP="$WORK_TMP/SpacedOut.app"

echo "==> Assembling $APP_BUNDLE..."
mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"

if grep -q '\$(' "$ROOT_DIR/AppResources/Info.plist" || ! grep -q 'LSUIElement' "$ROOT_DIR/AppResources/Info.plist"; then
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Note: Restoring AppResources/Info.plist from git HEAD (was overwritten with placeholders/missing keys)..." >&2
    git -C "$ROOT_DIR" checkout HEAD -- AppResources/Info.plist
  else
    echo "Error: AppResources/Info.plist contains unexpanded placeholders or is incomplete." >&2
    exit 1
  fi
fi

if ! grep -q 'personal-information.calendars' "$ROOT_DIR/AppResources/SpacedOut.entitlements"; then
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Note: Restoring AppResources/SpacedOut.entitlements from git HEAD..." >&2
    git -C "$ROOT_DIR" checkout HEAD -- AppResources/SpacedOut.entitlements
  fi
fi

cp -f "$BIN_PATH" "$STAGE_APP/Contents/MacOS/SpacedOut"
chmod 755 "$STAGE_APP/Contents/MacOS/SpacedOut"
cp -f "$ROOT_DIR/AppResources/Info.plist" "$STAGE_APP/Contents/Info.plist"
plutil -lint "$STAGE_APP/Contents/Info.plist" >/dev/null

if [[ -x /usr/libexec/PlistBuddy ]]; then
  BUNDLE_EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$STAGE_APP/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$BUNDLE_EXE" != "SpacedOut" ]]; then
    echo "Error: CFBundleExecutable in Info.plist is '$BUNDLE_EXE' (expected 'SpacedOut')." >&2
    exit 1
  fi
fi

ICON_COMPILED=0
if command -v xcrun >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then
  if [[ -d "$ROOT_DIR/AppResources/AppIcon.icon" ]]; then
    if xcrun actool "$ROOT_DIR/AppResources/AppIcon.icon" \
      --compile "$STAGE_APP/Contents/Resources" \
      --app-icon AppIcon \
      --include-all-app-icons \
      --enable-on-demand-resources NO \
      --development-region en \
      --target-device mac \
      --platform macosx \
      --minimum-deployment-target 14.0 \
      --output-partial-info-plist "$WORK_TMP/actool.plist" \
      --output-format human-readable-text \
      --errors --warnings >"$WORK_TMP/actool-icon.log" 2>&1 \
      && [[ -s "$STAGE_APP/Contents/Resources/Assets.car" ]]; then
      ICON_COMPILED=1
    else
      echo "Note: actool could not compile AppIcon.icon (falling back to Assets.xcassets / AppIcon.icns):" >&2
      cat "$WORK_TMP/actool-icon.log" >&2 || true
    fi
  fi

  if [[ "$ICON_COMPILED" -eq 0 && -d "$ROOT_DIR/AppResources/Assets.xcassets" ]]; then
    if xcrun actool "$ROOT_DIR/AppResources/Assets.xcassets" \
      --compile "$STAGE_APP/Contents/Resources" \
      --app-icon AppIcon \
      --include-all-app-icons \
      --enable-on-demand-resources NO \
      --development-region en \
      --target-device mac \
      --platform macosx \
      --minimum-deployment-target 14.0 \
      --output-partial-info-plist "$WORK_TMP/actool.plist" \
      --output-format human-readable-text \
      --errors --warnings >"$WORK_TMP/actool-xcassets.log" 2>&1 \
      && [[ -s "$STAGE_APP/Contents/Resources/AppIcon.icns" ]]; then
      ICON_COMPILED=1
    else
      echo "Note: actool could not compile Assets.xcassets (falling back to prebuilt AppIcon.icns):" >&2
      cat "$WORK_TMP/actool-xcassets.log" >&2 || true
    fi
  fi
fi

if [[ ! -s "$STAGE_APP/Contents/Resources/AppIcon.icns" ]]; then
  cp -f "$ROOT_DIR/AppResources/AppIcon.icns" "$STAGE_APP/Contents/Resources/AppIcon.icns"
fi

printf 'APPL????' > "$STAGE_APP/Contents/PkgInfo"

xattr -cr "$STAGE_APP" >/dev/null 2>&1 || true

echo "==> Ad-hoc code signing SpacedOut.app..."
codesign --force --deep --sign - --entitlements "$ROOT_DIR/AppResources/SpacedOut.entitlements" "$STAGE_APP"

if [[ ! -x "$STAGE_APP/Contents/MacOS/SpacedOut" ]]; then
  echo "Error: Assembled app is missing executable at $STAGE_APP/Contents/MacOS/SpacedOut" >&2
  exit 1
fi

codesign --verify --strict "$STAGE_APP"

mkdir -p "$BUILD_DIR"
if [[ -x "$LSREGISTER" ]]; then
  for stale in "$HOME/Library/Developer/Xcode/DerivedData"/SpacedOut-*/Build/Products/*/SpacedOut.app; do
    [[ -e "$stale" ]] && "$LSREGISTER" -u "$stale" >/dev/null 2>&1 || true
  done
  "$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

rm -rf "$APP_BUNDLE"
mv "$STAGE_APP" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "==> Built: $APP_BUNDLE"
echo "    Run with: open \"$APP_BUNDLE\""
