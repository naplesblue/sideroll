#!/bin/bash
# scripts/build-dmg.sh — Build a SideRoll Release DMG with ad-hoc signing.
#
# Usage:
#   scripts/build-dmg.sh           Use MARKETING_VERSION from project.pbxproj
#   scripts/build-dmg.sh 0.1.0     Override version
#
# Output:
#   dist/SideRoll-<version>.dmg
#   SHA256 of the DMG (stdout)
#
# Notes:
# - Ad-hoc signed (no Apple Developer ID required). First-time users will need
#   to right-click → Open to bypass Gatekeeper, OR run:
#     xattr -dr com.apple.quarantine /Applications/SideRoll.app
# - For Gatekeeper-friendly distribution, enroll in Apple Developer Program
#   ($99/yr) and replace the codesign step with a Developer ID certificate.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(grep -m1 'MARKETING_VERSION' SideRoll.xcodeproj/project.pbxproj \
        | sed 's/.*= //' | tr -d '";')
fi

BUILD_DIR=".build-release"
APP_PATH="$BUILD_DIR/Build/Products/Release/SideRoll.app"
DMG_DIR="dist"
DMG_PATH="$DMG_DIR/SideRoll-${VERSION}.dmg"

echo "→ Building Release for SideRoll ${VERSION}"
rm -rf "$BUILD_DIR"
xcodebuild build \
    -project SideRoll.xcodeproj \
    -scheme SideRoll \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    > "${BUILD_DIR}.log" 2>&1 || {
        echo "✗ Build failed. Tail of log:"
        tail -30 "${BUILD_DIR}.log"
        exit 1
    }

if [ ! -d "$APP_PATH" ]; then
    echo "✗ Build succeeded but $APP_PATH not found"
    exit 1
fi

echo "→ Ad-hoc signing $APP_PATH"
codesign --force --sign - --deep "$APP_PATH"
codesign --verify --verbose=2 "$APP_PATH"

echo "→ Creating $DMG_PATH"
mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"

# Stage DMG contents: SideRoll.app + Applications shortcut
STAGE_DIR="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "SideRoll" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" > /dev/null

rm -rf "$STAGE_DIR"

SIZE=$(du -h "$DMG_PATH" | cut -f1)
SHA=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

echo ""
echo "✓ Built $DMG_PATH ($SIZE)"
echo "  SHA256: $SHA"
