#!/bin/bash
# ============================================================================
# MacGesture — Release Script
# ============================================================================
# Creates a signed release archive and generates/updates the appcast XML
# for Sparkle auto-updates.
#
# Prerequisites:
#   1. Run ./build.sh first
#   2. Generate EdDSA keys (one-time): ./vendor/Sparkle/bin/generate_keys
#   3. Set SUPublicEDKey in Info.plist
#   4. Set SUFeedURL in Info.plist
#
# Usage:
#   ./release.sh [version]
#
# Example:
#   ./release.sh 2.3
# ============================================================================

set -e

APP_NAME="MacGesture"
BUILD_DIR="./build"
RELEASE_DIR="./releases"
VENDOR_DIR="./vendor"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SPARKLE_BIN="${VENDOR_DIR}/Sparkle/bin"

# ── Parse version ──
VERSION="$1"
if [ -z "$VERSION" ]; then
    VERSION=$(defaults read "$(pwd)/${APP_BUNDLE}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "")
    if [ -z "$VERSION" ]; then
        echo "Usage: ./release.sh <version>"
        echo "Example: ./release.sh 2.3"
        exit 1
    fi
    echo "Using version from Info.plist: ${VERSION}"
fi

echo "========================================"
echo "  Releasing ${APP_NAME} v${VERSION}"
echo "========================================"
echo ""

# ── Verify build exists ──
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ App bundle not found. Run ./build.sh first."
    exit 1
fi

# ── Verify Sparkle tools exist ──
if [ ! -d "$SPARKLE_BIN" ]; then
    echo "❌ Sparkle tools not found at ${SPARKLE_BIN}"
    echo "   Run ./build.sh to download Sparkle first."
    exit 1
fi

# ── Check for EdDSA signing key ──
# Sparkle stores the private key in the macOS Keychain.
# generate_keys creates it on first run; sign_update reads it automatically.
if ! "${SPARKLE_BIN}/sign_update" --help &>/dev/null; then
    echo "⚠️  sign_update tool not working. Ensure Sparkle was downloaded correctly."
fi

mkdir -p "$RELEASE_DIR"

# ==========================================
# Step 1: Create release ZIP
# ==========================================
echo "📦 Step 1: Creating release archive..."

ARCHIVE_NAME="${APP_NAME}-${VERSION}.zip"
ARCHIVE_PATH="${RELEASE_DIR}/${ARCHIVE_NAME}"

# Remove old archive if exists
rm -f "$ARCHIVE_PATH"

# Create zip from the app bundle (Sparkle expects a zip containing the .app)
cd "$BUILD_DIR"
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "../${ARCHIVE_PATH}"
cd ..

echo "   ✅ ${ARCHIVE_PATH} ($(du -h "$ARCHIVE_PATH" | cut -f1))"

# ==========================================
# Step 2: Sign the archive with EdDSA
# ==========================================
echo ""
echo "🔏 Step 2: Signing archive with EdDSA..."

SIGNATURE=$("${SPARKLE_BIN}/sign_update" "$ARCHIVE_PATH" 2>&1) || {
    echo ""
    echo "   ❌ Signing failed."
    echo ""
    echo "   If this is your first release, generate keys first:"
    echo "     ${SPARKLE_BIN}/generate_keys"
    echo ""
    echo "   This creates an EdDSA keypair in your macOS Keychain."
    echo "   Then update Info.plist SUPublicEDKey with the public key."
    echo ""
    exit 1
}

# sign_update outputs: sparkle:edSignature="..." length="..."
echo "   ✅ Signed"
echo "   ${SIGNATURE}"

# Parse the signature and length
ED_SIGNATURE=$(echo "$SIGNATURE" | grep -oP 'sparkle:edSignature="\K[^"]+' || echo "")
FILE_LENGTH=$(echo "$SIGNATURE" | grep -oP 'length="\K[^"]+' || echo "")

# Fallback parsing for different output formats
if [ -z "$ED_SIGNATURE" ]; then
    ED_SIGNATURE=$(echo "$SIGNATURE" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')
fi
if [ -z "$FILE_LENGTH" ]; then
    FILE_LENGTH=$(stat -f%z "$ARCHIVE_PATH" 2>/dev/null || stat -c%s "$ARCHIVE_PATH" 2>/dev/null)
fi

# ==========================================
# Step 3: Generate appcast entry
# ==========================================
echo ""
echo "📡 Step 3: Generating appcast..."

# You must set this to where you'll host the ZIP
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-https://github.com/is-harshul/mac-gesture/releases/download/v${VERSION}}"
DOWNLOAD_URL="${DOWNLOAD_BASE_URL}/${ARCHIVE_NAME}"

APPCAST_FILE="${RELEASE_DIR}/appcast.xml"
MIN_OS="12.0"
CURRENT_DATE=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")

# Create or update appcast
if [ ! -f "$APPCAST_FILE" ]; then
    # Create new appcast
    cat > "$APPCAST_FILE" << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>MacGesture Updates</title>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${CURRENT_DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <h2>MacGesture ${VERSION}</h2>
                <p>Update description here.</p>
            ]]></description>
            <enclosure
                url="${DOWNLOAD_URL}"
                ${SIGNATURE}
                type="application/octet-stream"
            />
        </item>
    </channel>
</rss>
APPCAST_EOF
    echo "   ✅ Created new appcast.xml"
else
    # Prepend new item to existing appcast
    NEW_ITEM=$(cat << ITEM_EOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${CURRENT_DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <h2>MacGesture ${VERSION}</h2>
                <p>Update description here.</p>
            ]]></description>
            <enclosure
                url="${DOWNLOAD_URL}"
                ${SIGNATURE}
                type="application/octet-stream"
            />
        </item>
ITEM_EOF
    )

    # Insert after <channel> + <language> line
    sed -i.bak "/<language>en<\/language>/a\\
${NEW_ITEM}
" "$APPCAST_FILE"
    rm -f "${APPCAST_FILE}.bak"
    echo "   ✅ Added v${VERSION} to existing appcast.xml"
fi

# ==========================================
# Alternative: Use Sparkle's generate_appcast
# ==========================================
# If you prefer Sparkle's built-in tool (handles signing automatically):
#
#   ${SPARKLE_BIN}/generate_appcast ${RELEASE_DIR}
#
# This scans the directory for .zip/.dmg files and creates/updates appcast.xml.
# It reads the EdDSA key from Keychain automatically.

# ==========================================
# Summary
# ==========================================
echo ""
echo "========================================"
echo "  ✅ Release v${VERSION} ready!"
echo "========================================"
echo ""
echo "  Files:"
echo "    ${ARCHIVE_PATH}"
echo "    ${APPCAST_FILE}"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Edit the release notes in ${APPCAST_FILE}"
echo ""
echo "  2. Upload the ZIP to your release host:"
echo "     gh release create v${VERSION} ${ARCHIVE_PATH} --title 'v${VERSION}'"
echo ""
echo "  3. Publish the appcast:"
echo "     • GitHub Pages: copy appcast.xml to your gh-pages branch"
echo "     • Or any static host where SUFeedURL points to"
echo ""
echo "  4. Verify the update URL resolves:"
echo "     curl -I ${DOWNLOAD_URL}"
echo ""
