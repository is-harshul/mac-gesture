#!/bin/bash
# ============================================================================
# Generate AppIcon.icns from icon.svg
#
# Requirements: macOS with sips, iconutil, and either:
#   - rsvg-convert (brew install librsvg)
#   - or qlmanage (built-in, fallback)
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SVG_FILE="${SCRIPT_DIR}/icon.svg"
ICONSET_DIR="${SCRIPT_DIR}/AppIcon.iconset"
ICNS_FILE="${SCRIPT_DIR}/AppIcon.icns"
PNG_1024="${SCRIPT_DIR}/icon_1024.png"

echo "🎨 Generating app icon from SVG..."

# Step 1: Convert SVG → 1024x1024 PNG
if command -v rsvg-convert &>/dev/null; then
    echo "   Using rsvg-convert..."
    rsvg-convert -w 1024 -h 1024 "$SVG_FILE" -o "$PNG_1024"
elif command -v /usr/bin/qlmanage &>/dev/null; then
    echo "   Using qlmanage (fallback)..."
    /usr/bin/qlmanage -t -s 1024 -o "${SCRIPT_DIR}" "$SVG_FILE" 2>/dev/null
    mv "${SCRIPT_DIR}/icon.svg.png" "$PNG_1024" 2>/dev/null || true
else
    echo "❌ Need rsvg-convert or qlmanage."
    echo "   Install: brew install librsvg"
    exit 1
fi

if [ ! -f "$PNG_1024" ]; then
    echo "❌ Failed to generate 1024px PNG"
    exit 1
fi

# Step 2: Generate all required icon sizes
echo "   Generating icon sizes..."
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

declare -a SIZES=(16 32 64 128 256 512 1024)

for size in "${SIZES[@]}"; do
    sips -z "$size" "$size" "$PNG_1024" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null 2>&1
done

# Rename to Apple's expected naming convention
cp "${ICONSET_DIR}/icon_16x16.png"     "${ICONSET_DIR}/icon_16x16.png"
cp "${ICONSET_DIR}/icon_32x32.png"     "${ICONSET_DIR}/icon_16x16@2x.png"
cp "${ICONSET_DIR}/icon_32x32.png"     "${ICONSET_DIR}/icon_32x32.png"
cp "${ICONSET_DIR}/icon_64x64.png"     "${ICONSET_DIR}/icon_32x32@2x.png"
cp "${ICONSET_DIR}/icon_128x128.png"   "${ICONSET_DIR}/icon_128x128.png"
cp "${ICONSET_DIR}/icon_256x256.png"   "${ICONSET_DIR}/icon_128x128@2x.png"
cp "${ICONSET_DIR}/icon_256x256.png"   "${ICONSET_DIR}/icon_256x256.png"
cp "${ICONSET_DIR}/icon_512x512.png"   "${ICONSET_DIR}/icon_256x256@2x.png"
cp "${ICONSET_DIR}/icon_512x512.png"   "${ICONSET_DIR}/icon_512x512.png"
cp "${ICONSET_DIR}/icon_1024x1024.png" "${ICONSET_DIR}/icon_512x512@2x.png"

# Remove intermediate files
rm -f "${ICONSET_DIR}/icon_64x64.png" "${ICONSET_DIR}/icon_1024x1024.png"

# Step 3: Convert iconset → icns
echo "   Creating .icns..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"

# Cleanup
rm -rf "$ICONSET_DIR" "$PNG_1024"

echo "✅ Icon created: $ICNS_FILE"
echo ""
