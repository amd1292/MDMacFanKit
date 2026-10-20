#!/bin/bash
# Builds build/MDMacFanKit.app with SwiftPM only (no Xcode needed) and signs it ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP=build/MDMacFanKit.app

swift build -c "$CONFIG" --product MDMacFanKit
swift build -c "$CONFIG" --product MDFanHelper
swift build -c "$CONFIG" --product mdfan
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/MDMacFanKit" "$APP/Contents/MacOS/"
cp "$BIN/MDFanHelper" "$BIN/mdfan" "$APP/Contents/Resources/"
cp Resources/com.mdmacfankit.helper.plist scripts/install-helper.sh scripts/uninstall-helper.sh "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign - --identifier com.mdmacfankit.helper "$APP/Contents/Resources/MDFanHelper"
codesign --force --sign - --identifier com.mdmacfankit.mdfan "$APP/Contents/Resources/mdfan"
codesign --force --sign - "$APP"

echo "Built $APP"
