#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
xcrun swift build -c release --product FloatingWorkspace
APP="$ROOT/dist/FloatingWorkspace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/FloatingWorkspace" "$APP/Contents/MacOS/FloatingWorkspace"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/FloatingWorkspace"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
