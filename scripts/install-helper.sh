#!/bin/bash
# Installs the MDMacFanKit root helper as a LaunchDaemon. Must run as root.
# Usage: sudo install-helper.sh [directory containing MDFanHelper and com.mdmacfankit.helper.plist]
set -euo pipefail

LABEL=com.mdmacfankit.helper
SRC="${1:-$(cd "$(dirname "$0")" && pwd)}"
BIN=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist

if [ "$(id -u)" != 0 ]; then echo "Run as root (sudo)." >&2; exit 1; fi
[ -f "$SRC/MDFanHelper" ] || { echo "MDFanHelper not found in $SRC" >&2; exit 1; }

if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "system/$LABEL" || true
    # bootout returns before the job is fully gone; bootstrapping too early fails with error 5.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        launchctl print "system/$LABEL" >/dev/null 2>&1 || break
        sleep 0.5
    done
fi

install -d -m 755 -o root -g wheel /Library/PrivilegedHelperTools
install -m 755 -o root -g wheel "$SRC/MDFanHelper" "$BIN"
install -m 644 -o root -g wheel "$SRC/$LABEL.plist" "$PLIST"
launchctl bootstrap system "$PLIST"
echo "Installed $LABEL"
