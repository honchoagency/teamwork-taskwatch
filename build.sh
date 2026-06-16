#!/bin/bash
#
# Build TaskWatch and assemble a runnable TaskWatch.app bundle.
#
#   ./build.sh              native build (fast, for local dev)
#   UNIVERSAL=1 ./build.sh  universal arm64 + x86_64 (for release)
#
# No third-party dependencies, so we compile the sources directly with swiftc
# (universal builds then work with Command Line Tools — no full Xcode needed).
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TaskWatch"
BUNDLE_ID="agency.honcho.TaskWatch"
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || true)
VERSION=${VERSION:-1.0}
SDK=$(xcrun --show-sdk-path)
APP_BUNDLE="${APP_NAME}.app"
EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
DEPLOY_TARGET="13.0"

SOURCES=(Sources/TaskWatch/*.swift)

FRAMEWORKS=(
    -framework AppKit
    -framework SwiftUI
    -framework UserNotifications
    -framework Security
)

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

compile() { # <arch> <output>
    swiftc "${SOURCES[@]}" \
        -sdk "$SDK" \
        -target "$1-apple-macosx${DEPLOY_TARGET}" \
        -swift-version 5 \
        -O \
        "${FRAMEWORKS[@]}" \
        -o "$2"
}

if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "Compiling Swift (universal)..."
    compile "arm64" "${EXECUTABLE}-arm64"
    compile "x86_64" "${EXECUTABLE}-x86_64"
    lipo -create "${EXECUTABLE}-arm64" "${EXECUTABLE}-x86_64" -output "$EXECUTABLE"
    rm "${EXECUTABLE}-arm64" "${EXECUTABLE}-x86_64"
else
    ARCH=$(uname -m)
    echo "Compiling Swift (${ARCH})..."
    compile "${ARCH}" "$EXECUTABLE"
fi

echo "Processing Info.plist..."
sed \
    -e 's/$(EXECUTABLE_NAME)/'"${APP_NAME}"'/g' \
    -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/'"${BUNDLE_ID}"'/g' \
    -e 's/$(PRODUCT_NAME)/'"${APP_NAME}"'/g' \
    -e 's/$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g' \
    -e 's/$(MACOSX_DEPLOYMENT_TARGET)/'"${DEPLOY_TARGET}"'/g' \
    -e 's/$(DEVELOPMENT_LANGUAGE)/en/g' \
    -e 's/$(MARKETING_VERSION)/'"${VERSION}"'/g' \
    "Resources/Info.plist" > "${APP_BUNDLE}/Contents/Info.plist"

echo "Copying resources..."
cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo ""
echo "Built: ${APP_BUNDLE} (version ${VERSION})"
echo "Run:   open '${APP_BUNDLE}'"
