#!/bin/bash
# ============================================================================
# MacGesture — Package as DMG for Distribution
# ============================================================================
# Creates a distributable .dmg with the app and Applications symlink.
#
# Usage:
#   ./build.sh           # Build first
#   ./package_dmg.sh     # Then package
# ============================================================================

set -e

APP_NAME="MacGesture"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ App bundle not found. Run ./build.sh first."
    exit 1
fi

# Read version from the built app's Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || echo "0.0")

DMG_DIR="${BUILD_DIR}/dmg_staging"
DMG_OUTPUT="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

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
MacGesture — Installation
=========================

1. Drag MacGesture.app into the Applications folder →

2. IMPORTANT — Before first launch, open Terminal and run:

   xattr -cr /Applications/MacGesture.app

   This removes the macOS quarantine flag. Without this step,
   macOS will block the app because it is not code-signed.

3. Open MacGesture from Applications.

4. Grant Accessibility permission when prompted:
   System Settings → Privacy & Security → Accessibility → MacGesture ON

5. Done! Tap the trackpad with 3, 4, or 5 fingers.

Tip: After each rebuild/update, you may need to re-run the xattr
command and toggle Accessibility permission OFF → ON in System Settings.
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
