#!/bin/bash
#
# Package an already-built TaskWatch.app into a compressed DMG with a
# drag-to-Applications layout.
#
#   ./package-dmg.sh [version]   (version defaults to git tag, then 1.0)
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TaskWatch"
APP_BUNDLE="${APP_NAME}.app"
VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo 1.0)}"
DMG="${APP_NAME}-${VERSION}.dmg"
STAGING="dmg-staging"

if [ ! -d "${APP_BUNDLE}" ]; then
    echo "error: ${APP_BUNDLE} not found — run ./build.sh first" >&2
    exit 1
fi

echo "Staging DMG contents..."
rm -rf "${STAGING}" "${DMG}"
mkdir -p "${STAGING}"
cp -R "${APP_BUNDLE}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

echo "Creating ${DMG}..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    "${DMG}"

rm -rf "${STAGING}"
echo "Built: ${DMG}"
