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
# Requires: create-dmg (brew install create-dmg)

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

# Use create-dmg for professional DMG with icon layout
create-dmg \
    --volname "SideRoll" \
    --background "assets/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "SideRoll.app" 160 190 \
    --app-drop-link 440 190 \
    --hide-extension "SideRoll.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH" \
    || {
        # create-dmg returns 2 when it can't set custom icon (CI/headless)
        # but DMG is still created successfully
        if [ -f "$DMG_PATH" ]; then
            echo "⚠ create-dmg exited non-zero but DMG was created (likely headless mode)"
        else
            echo "✗ create-dmg failed"
            exit 1
        fi
    }

SIZE=$(du -h "$DMG_PATH" | cut -f1)
SHA=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

echo ""
echo "✓ Built $DMG_PATH ($SIZE)"
echo "  SHA256: $SHA"
