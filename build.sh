#!/bin/bash
# ============================================================================
# MacGesture — Build Script
# ============================================================================
# Downloads Sparkle framework, generates the app icon, compiles Swift,
# and packages everything into a macOS .app bundle with auto-update support.
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

APP_NAME="MacGesture"
SPARKLE_VERSION="2.7.5"
BUILD_DIR="./build"
VENDOR_DIR="./vendor"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
FRAMEWORKS="${CONTENTS}/Frameworks"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "  Building ${APP_NAME}"
echo "========================================"
echo ""

# --- Clean build ---
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}" "${FRAMEWORKS}"

# ==========================================
# Step 1: Download Sparkle
# ==========================================
echo "📥 Step 1: Sparkle framework..."

SPARKLE_DIR="${VENDOR_DIR}/Sparkle"
SPARKLE_FRAMEWORK="${SPARKLE_DIR}/Sparkle.framework"

if [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "   Using cached Sparkle ${SPARKLE_VERSION}"
else
    echo "   Downloading Sparkle ${SPARKLE_VERSION}..."
    mkdir -p "$VENDOR_DIR"
    rm -rf "$SPARKLE_DIR"

    SPARKLE_URL="https://github.com/nicklama/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    SPARKLE_URL_ALT="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

    TEMP_TAR="${VENDOR_DIR}/sparkle.tar.xz"

    # Try official Sparkle release
    if curl -fsSL -o "$TEMP_TAR" "$SPARKLE_URL_ALT" 2>/dev/null; then
        echo "   Downloaded from sparkle-project/Sparkle"
    elif curl -fsSL -o "$TEMP_TAR" "$SPARKLE_URL" 2>/dev/null; then
        echo "   Downloaded from mirror"
    else
        echo ""
        echo "   ⚠️  Could not download Sparkle automatically."
        echo ""
        echo "   Please download manually:"
        echo "     1. Go to: https://github.com/sparkle-project/Sparkle/releases"
        echo "     2. Download Sparkle-${SPARKLE_VERSION}.tar.xz (or latest 2.x)"
        echo "     3. Extract and place Sparkle.framework in: ${SPARKLE_DIR}/"
        echo ""
        echo "   Or build without Sparkle:"
        echo "     ./build.sh --no-sparkle"
        echo ""

        if [[ "$1" == "--no-sparkle" ]]; then
            echo "   Continuing WITHOUT Sparkle (no auto-update)..."
            NO_SPARKLE=1
        else
            exit 1
        fi
    fi

    if [ -z "$NO_SPARKLE" ]; then
        mkdir -p "$SPARKLE_DIR"
        tar -xf "$TEMP_TAR" -C "$SPARKLE_DIR"
        rm -f "$TEMP_TAR"

        if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
            # Some Sparkle releases nest the framework
            FOUND=$(find "$SPARKLE_DIR" -name "Sparkle.framework" -type d -maxdepth 3 | head -1)
            if [ -n "$FOUND" ]; then
                mv "$FOUND" "$SPARKLE_FRAMEWORK"
            else
                echo "   ❌ Sparkle.framework not found in archive"
                exit 1
            fi
        fi
        echo "   ✅ Sparkle ${SPARKLE_VERSION} ready"
    fi
fi

# ==========================================
# Step 2: Generate Icon
# ==========================================
echo ""
echo "🎨 Step 2: Generating app icon..."
ICNS_FILE="${SCRIPT_DIR}/AppIcon.icns"
SVG_FILE="${SCRIPT_DIR}/icon.svg"
PNG_1024="${SCRIPT_DIR}/_icon_1024.png"
ICONSET="${SCRIPT_DIR}/_AppIcon.iconset"

if [ -f "$ICNS_FILE" ]; then
    echo "   Using existing AppIcon.icns"
else
    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$PNG_1024"
    elif command -v /usr/bin/qlmanage &>/dev/null; then
        /usr/bin/qlmanage -t -s 1024 -o "${SCRIPT_DIR}" "$SVG_FILE" 2>/dev/null
        mv "${SCRIPT_DIR}/icon.svg.png" "$PNG_1024" 2>/dev/null || true
    else
        echo "   ⚠️  No SVG converter. Install: brew install librsvg"
        PNG_1024=""
    fi

    if [ -n "$PNG_1024" ] && [ -f "$PNG_1024" ]; then
        rm -rf "$ICONSET" && mkdir -p "$ICONSET"
        for size in 16 32 64 128 256 512 1024; do
            sips -z "$size" "$size" "$PNG_1024" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null 2>&1
        done
        cp "${ICONSET}/icon_32x32.png"     "${ICONSET}/icon_16x16@2x.png"
        cp "${ICONSET}/icon_64x64.png"     "${ICONSET}/icon_32x32@2x.png"
        cp "${ICONSET}/icon_256x256.png"   "${ICONSET}/icon_128x128@2x.png"
        cp "${ICONSET}/icon_512x512.png"   "${ICONSET}/icon_256x256@2x.png"
        cp "${ICONSET}/icon_1024x1024.png" "${ICONSET}/icon_512x512@2x.png"
        rm -f "${ICONSET}/icon_64x64.png" "${ICONSET}/icon_1024x1024.png"
        iconutil -c icns "$ICONSET" -o "$ICNS_FILE"
        rm -rf "$ICONSET" "$PNG_1024"
        echo "   ✅ AppIcon.icns generated"
    fi
fi

[ -f "$ICNS_FILE" ] && cp "$ICNS_FILE" "${RESOURCES}/AppIcon.icns"

# ==========================================
# Step 3: Compile
# ==========================================
echo ""
echo "📦 Step 3: Compiling Swift..."

ARCH=$(uname -m)
echo "   Architecture: ${ARCH}"

SWIFT_FLAGS=(
    -O
    -framework Cocoa
    -framework ApplicationServices
    -framework Carbon
)

# Add Sparkle linking if available
if [ -d "$SPARKLE_FRAMEWORK" ] && [ -z "$NO_SPARKLE" ]; then
    SWIFT_FLAGS+=(
        -F "${VENDOR_DIR}/Sparkle"
        -framework Sparkle
        -Xlinker -rpath -Xlinker "@executable_path/../Frameworks"
    )
    echo "   Linking with Sparkle ✓"
else
    # Compile with SPARKLE_DISABLED flag so the code skips Sparkle imports
    SWIFT_FLAGS+=(-D NO_SPARKLE)
    echo "   Building WITHOUT Sparkle"
fi

swiftc \
    "${SWIFT_FLAGS[@]}" \
    -o "${MACOS}/${APP_NAME}" \
    Sources/main.swift

echo "   ✅ Compiled successfully"

# ==========================================
# Step 4: Bundle
# ==========================================
echo ""
echo "📁 Step 4: Packaging app bundle..."

cp Info.plist "${CONTENTS}/Info.plist"
chmod +x "${MACOS}/${APP_NAME}"

# Embed Sparkle framework
if [ -d "$SPARKLE_FRAMEWORK" ] && [ -z "$NO_SPARKLE" ]; then
    cp -R "$SPARKLE_FRAMEWORK" "${FRAMEWORKS}/"

    # Also copy the XPC services that Sparkle 2.x needs
    INSTALLER_XPC="${VENDOR_DIR}/Sparkle/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    DOWNLOADER_XPC="${VENDOR_DIR}/Sparkle/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"

    # Sparkle 2.x bundles XPC services inside the framework — they're already
    # included by the cp -R above. Verify:
    if [ -d "${FRAMEWORKS}/Sparkle.framework" ]; then
        echo "   Sparkle.framework embedded ✓"
    fi
fi

echo "   ✅ ${APP_BUNDLE}"

# ==========================================
# Done
# ==========================================
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
echo "  First-time release setup:"
echo "    See RELEASING.md for Sparkle key generation"
echo "    and appcast publishing instructions."
echo ""
