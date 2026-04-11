#!/bin/bash
# Create a DMG installer for WhisperDictation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/WhisperDictation.app"
DMG_NAME="WhisperDictation"
DMG_OUTPUT="$BUILD_DIR/${DMG_NAME}.dmg"
VOLUME_NAME="WhisperDictation"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Run 'make app' first."
    exit 1
fi

# Remove previous DMG
rm -f "$DMG_OUTPUT"

# Create a temporary directory for DMG contents
TMP_DIR=$(mktemp -d)
cp -R "$APP_BUNDLE" "$TMP_DIR/"

# Remove quarantine attribute so the icon shows correctly in the DMG
xattr -cr "$TMP_DIR/WhisperDictation.app" 2>/dev/null || true

ln -s /Applications "$TMP_DIR/Applications"

echo "==> Creating DMG..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "==> DMG created: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"
