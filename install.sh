#!/bin/bash
#
# Build the current source and install it as your live local copy:
#   - native build (fast)
#   - copy to /Applications/TaskWatch.app (replacing any existing copy)
#   - register a Login Item so it starts automatically at login
#   - relaunch it now
#
# Re-run this any time you want your running TaskWatch to reflect the latest
# code. Your settings survive (Keychain + UserDefaults are keyed by bundle id,
# which doesn't change).
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TaskWatch"
APP_BUNDLE="${APP_NAME}.app"
DEST="/Applications/${APP_BUNDLE}"

echo "Building (native)..."
./build.sh

echo "Stopping any running instance..."
osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 1

echo "Installing to ${DEST}..."
rm -rf "${DEST}"
cp -R "${APP_BUNDLE}" "${DEST}"

echo "Registering Login Item..."
osascript <<OSA 2>/dev/null || echo "  (skipped — grant Automation permission and re-run if you want auto-start at login)"
tell application "System Events"
    if exists (login item "${APP_NAME}") then delete login item "${APP_NAME}"
    make login item at end with properties {path:"${DEST}", hidden:false}
end tell
OSA

echo "Launching..."
open "${DEST}"

echo ""
echo "Installed: ${DEST}"
echo "It will start automatically at login. Re-run ./install.sh after code changes."
