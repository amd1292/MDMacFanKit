#!/bin/bash
# Builds the app and zips it for a GitHub release: build/MDMacFanKit-<version>-<arch>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
ARCH="$(uname -m)"
ZIP="build/MDMacFanKit-$VERSION-$ARCH.zip"

codesign --verify --deep --strict build/MDMacFanKit.app
rm -f "$ZIP"
# ditto keeps the bundle's signature and extended attributes intact.
ditto -c -k --keepParent build/MDMacFanKit.app "$ZIP"
shasum -a 256 "$ZIP"
