#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

APP_ICON_DIR="$ROOT/Resources/Assets.xcassets/AppIcon.appiconset"
MENU_ICON_DIR="$ROOT/Resources/Assets.xcassets/MenuBarTemplate.imageset"
MANIFESTS=(
  "$ROOT/Resources/Assets.xcassets/Contents.json"
  "$APP_ICON_DIR/Contents.json"
  "$MENU_ICON_DIR/Contents.json"
)
APP_ICON_FILES=(
  AppIcon-16.png AppIcon-Dark-16.png
  AppIcon-32.png AppIcon-Dark-32.png
  AppIcon-64.png AppIcon-Dark-64.png
  AppIcon-128.png AppIcon-Dark-128.png
  AppIcon-256.png AppIcon-Dark-256.png
  AppIcon-512.png AppIcon-Dark-512.png
  AppIcon-1024.png AppIcon-Dark-1024.png
)

validate_resources() {
  local manifest filename
  for manifest in "${MANIFESTS[@]}"; do
    if [[ ! -f "$manifest" ]]; then
      printf 'Missing required icon resource: %s\n' "${manifest#$ROOT/Resources/Assets.xcassets/}" >&2
      return 1
    fi
    # This plutil's lint mode does not auto-detect JSON; normalize through plutil first.
    plutil -convert xml1 -o - "$manifest" | plutil -lint -
  done

  for filename in "${APP_ICON_FILES[@]}"; do
    if [[ ! -f "$APP_ICON_DIR/$filename" ]]; then
      printf 'Missing required icon resource: %s\n' "$filename" >&2
      return 1
    fi
  done
  for filename in MenuBarTemplate-16.png MenuBarTemplate-32.png; do
    if [[ ! -f "$MENU_ICON_DIR/$filename" ]]; then
      printf 'Missing required icon resource: %s\n' "$filename" >&2
      return 1
    fi
  done
}

# Reject incomplete committed resources, then verify the regenerated output too.
validate_resources
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift \
  "$ROOT/Scripts/generate-icons.swift" "$ROOT/Resources/Assets.xcassets"
validate_resources

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release --product FloatingWorkspace
APP="$ROOT/dist/FloatingWorkspace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/FloatingWorkspace" "$APP/Contents/MacOS/FloatingWorkspace"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/FloatingWorkspace"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun actool \
  --app-icon AppIcon \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --output-partial-info-plist "$ROOT/dist/actool-partial-info.plist" \
  --compile "$APP/Contents/Resources" \
  "$ROOT/Resources/Assets.xcassets"
for filename in Assets.car AppIcon.icns; do
  if [[ ! -f "$APP/Contents/Resources/$filename" ]]; then
    printf 'Missing compiled icon resource: %s\n' "$filename" >&2
    exit 1
  fi
done
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
