#!/bin/bash
# ============================================================================
# FourFingerTap — Build Script
# ============================================================================
# Generates the app icon, compiles Swift, and packages into a macOS .app bundle.
#
# Requirements:
#   macOS 12+, Xcode Command Line Tools (xcode-select --install)
#   Optional: brew install librsvg (for best SVG→PNG conversion)
#
# Usage:
#   chmod +x build.sh
#   ./build.sh
# ============================================================================

set -e

APP_NAME="FourFingerTap"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "  Building ${APP_NAME}"
echo "========================================"
echo ""

# --- Clean ---
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

# --- Step 1: Generate Icon ---
echo "🎨 Step 1: Generating app icon..."
ICNS_FILE="${SCRIPT_DIR}/AppIcon.icns"
SVG_FILE="${SCRIPT_DIR}/icon.svg"
PNG_1024="${SCRIPT_DIR}/_icon_1024.png"
ICONSET="${SCRIPT_DIR}/_AppIcon.iconset"

if [ -f "$ICNS_FILE" ]; then
    echo "   Using existing AppIcon.icns"
else
    # SVG → 1024px PNG
    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$PNG_1024"
    elif command -v /usr/bin/qlmanage &>/dev/null; then
        /usr/bin/qlmanage -t -s 1024 -o "${SCRIPT_DIR}" "$SVG_FILE" 2>/dev/null
        mv "${SCRIPT_DIR}/icon.svg.png" "$PNG_1024" 2>/dev/null || true
    else
        echo "   ⚠️  No SVG converter found. Install: brew install librsvg"
        echo "   Skipping icon generation."
        PNG_1024=""
    fi

    if [ -n "$PNG_1024" ] && [ -f "$PNG_1024" ]; then
        rm -rf "$ICONSET"
        mkdir -p "$ICONSET"

        for size in 16 32 64 128 256 512 1024; do
            sips -z "$size" "$size" "$PNG_1024" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null 2>&1
        done

        cp "${ICONSET}/icon_16x16.png"     "${ICONSET}/icon_16x16.png"
        cp "${ICONSET}/icon_32x32.png"     "${ICONSET}/icon_16x16@2x.png"
        cp "${ICONSET}/icon_32x32.png"     "${ICONSET}/icon_32x32.png"
        cp "${ICONSET}/icon_64x64.png"     "${ICONSET}/icon_32x32@2x.png"
        cp "${ICONSET}/icon_128x128.png"   "${ICONSET}/icon_128x128.png"
        cp "${ICONSET}/icon_256x256.png"   "${ICONSET}/icon_128x128@2x.png"
        cp "${ICONSET}/icon_256x256.png"   "${ICONSET}/icon_256x256.png"
        cp "${ICONSET}/icon_512x512.png"   "${ICONSET}/icon_256x256@2x.png"
        cp "${ICONSET}/icon_512x512.png"   "${ICONSET}/icon_512x512.png"
        cp "${ICONSET}/icon_1024x1024.png" "${ICONSET}/icon_512x512@2x.png"
        rm -f "${ICONSET}/icon_64x64.png" "${ICONSET}/icon_1024x1024.png"

        iconutil -c icns "$ICONSET" -o "$ICNS_FILE"
        rm -rf "$ICONSET" "$PNG_1024"
        echo "   ✅ AppIcon.icns generated"
    fi
fi

if [ -f "$ICNS_FILE" ]; then
    cp "$ICNS_FILE" "${RESOURCES}/AppIcon.icns"
fi

# --- Step 2: Compile ---
echo ""
echo "📦 Step 2: Compiling Swift..."

ARCH=$(uname -m)
echo "   Architecture: ${ARCH}"

swiftc \
    -O \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework Carbon \
    -o "${MACOS}/${APP_NAME}" \
    Sources/main.swift

echo "   ✅ Compiled successfully"

# --- Step 3: Bundle ---
echo ""
echo "📁 Step 3: Packaging app bundle..."

cp Info.plist "${CONTENTS}/Info.plist"
chmod +x "${MACOS}/${APP_NAME}"

echo "   ✅ ${APP_BUNDLE}"

# --- Done ---
echo ""
echo "========================================"
echo "  ✅ Build successful!"
echo "========================================"
echo ""
echo "  Install:"
echo "    cp -r ${APP_BUNDLE} /Applications/"
echo ""
echo "  Run:"
echo "    open /Applications/${APP_NAME}.app"
echo ""
echo "  Create DMG for distribution:"
echo "    ./package_dmg.sh"
echo ""
