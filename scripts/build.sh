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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# A stable identity keeps macOS permissions across rebuilds (see make-dev-cert.sh);
# fall back to ad-hoc signing, which loses them every build.
if security find-certificate -c "Barloom Dev" >/dev/null 2>&1; then
    codesign --force --sign "Barloom Dev" "$APP" >/dev/null
else
    codesign --force --sign - "$APP" >/dev/null
fi
echo "Built $APP"

if [[ "${1:-}" == "--run" ]]; then
    pkill -x Barloom && sleep 1 || true
    open "$APP"
fi
