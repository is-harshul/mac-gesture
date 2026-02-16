#!/bin/bash
# ============================================================================
# FourFingerTap — Package as DMG for Distribution
# ============================================================================
# Creates a distributable .dmg with the app and Applications symlink.
#
# Usage:
#   ./build.sh           # Build first
#   ./package_dmg.sh     # Then package
# ============================================================================

set -e

APP_NAME="FourFingerTap"
VERSION="2.1"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_DIR="${BUILD_DIR}/dmg_staging"
DMG_OUTPUT="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ App bundle not found. Run ./build.sh first."
    exit 1
fi

echo "📦 Creating DMG..."

# Prepare staging area
rm -rf "$DMG_DIR" "$DMG_OUTPUT"
mkdir -p "$DMG_DIR"

# Copy app
cp -R "$APP_BUNDLE" "$DMG_DIR/"

# Create Applications symlink (for drag-to-install)
ln -s /Applications "$DMG_DIR/Applications"

# Create a README in the DMG
cat > "$DMG_DIR/READ ME FIRST.txt" << 'EOF'
FourFingerTap
=============

Installation:
  Drag FourFingerTap.app into the Applications folder.

First Launch:
  1. Open FourFingerTap from Applications
  2. Grant Accessibility permission when prompted
     (System Settings → Privacy & Security → Accessibility)
  3. Done! Tap the trackpad with 4 fingers to trigger your action.

Configure:
  Click the icon in the menu bar to change the action,
  tap duration, and movement tolerance.

Note: If macOS says the app is from an "unidentified developer",
right-click the app → Open → Open to bypass Gatekeeper.
EOF

# Create DMG
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUTPUT"

# Cleanup
rm -rf "$DMG_DIR"

echo ""
echo "✅ DMG created: $DMG_OUTPUT"
echo "   Size: $(du -h "$DMG_OUTPUT" | cut -f1)"
echo ""
echo "📋 Distribution steps:"
echo ""
echo "  Option A — Direct sharing:"
echo "    Share ${DMG_OUTPUT} via website, GitHub, email, etc."
echo "    Users may need to right-click → Open on first launch."
echo ""
echo "  Option B — Notarize for trusted distribution:"
echo "    See DISTRIBUTION.md for full instructions."
echo ""
