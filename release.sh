#!/bin/bash
# ============================================================================
# MacGesture — Release Script
# ============================================================================
# Builds the app, creates a DMG, and prints instructions for publishing.
#
# Usage:
#   ./release.sh           # Uses version from Info.plist
#   ./release.sh 2.3       # Override version
# ============================================================================

set -e

APP_NAME="MacGesture"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "========================================"
echo "  MacGesture — Release"
echo "========================================"
echo ""

# ── Step 1: Build ──
echo "🔨 Step 1: Building..."
chmod +x build.sh
./build.sh
echo ""

# ── Read / override version ──
VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null)}"

if [ -z "$VERSION" ]; then
    echo "❌ Could not determine version."
    echo "   Usage: ./release.sh [version]"
    exit 1
fi

echo "📌 Version: ${VERSION}"
echo ""

# ── Step 2: Create DMG ──
echo "📦 Step 2: Creating DMG..."
chmod +x package_dmg.sh
./package_dmg.sh

DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found at ${DMG_PATH}"
    exit 1
fi

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

# ── Done ──
echo ""
echo "========================================"
echo "  ✅ Release v${VERSION} ready!"
echo "========================================"
echo ""
echo "  Artifact: ${DMG_PATH} (${DMG_SIZE})"
echo ""
echo "  Publish to GitHub:"
echo "    gh release create v${VERSION} ${DMG_PATH} \\"
echo "      --title \"Mac Gesture v${VERSION}\" \\"
echo "      --notes \"Release v${VERSION}\""
echo ""
