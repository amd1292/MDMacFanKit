#!/bin/bash
# Removes the MDMacFanKit root helper. The helper restores automatic fan control as it stops.
set -euo pipefail

LABEL=com.mdmacfankit.helper

if [ "$(id -u)" != 0 ]; then echo "Run as root (sudo)." >&2; exit 1; fi

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/PrivilegedHelperTools/$LABEL" "/Library/LaunchDaemons/$LABEL.plist"
echo "Removed $LABEL"
