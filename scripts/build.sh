#!/bin/bash
# Builds build/Barloom.app. Pass --run to relaunch it afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Barloom"

APP=build/Barloom.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Barloom"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--run" ]]; then
    pkill -x Barloom && sleep 1 || true
    open "$APP"
fi
