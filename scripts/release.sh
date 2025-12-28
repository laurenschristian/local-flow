#!/bin/bash
set -e

# LocalFlow Release Script
# Creates a signed DMG and updates appcast.xml for Sparkle

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="LocalFlow"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Get version from Info.plist
VERSION=$(defaults read "$PROJECT_DIR/LocalFlow/Info.plist" CFBundleShortVersionString)
BUILD_NUMBER=$(defaults read "$PROJECT_DIR/LocalFlow/Info.plist" CFBundleVersion)

info "Building LocalFlow v$VERSION ($BUILD_NUMBER)"

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release
info "Building release..."
cd "$PROJECT_DIR"
xcodegen generate
xcodebuild -project LocalFlow.xcodeproj \
    -scheme LocalFlow \
    -configuration Release \
    -arch arm64 \
    build \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED)" || true

if [ ! -d "$BUILD_DIR/$APP_NAME.app" ]; then
    error "Build failed - app not found"
fi

info "Build complete"

# Create DMG
DMG_NAME="$APP_NAME-v$VERSION-mac-arm64.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
DMG_TEMP="$BUILD_DIR/dmg_temp"

info "Creating DMG..."
mkdir -p "$DMG_TEMP"
cp -R "$BUILD_DIR/$APP_NAME.app" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TEMP"

# Get file size
DMG_SIZE=$(stat -f%z "$DMG_PATH")
info "DMG created: $DMG_NAME ($DMG_SIZE bytes)"

# Find Sparkle tools
SPARKLE_DIR=$(find "$DERIVED_DATA" -path "*/SourcePackages/artifacts/sparkle/Sparkle" -type d 2>/dev/null | head -1)
if [ -z "$SPARKLE_DIR" ]; then
    error "Sparkle not found. Run 'xcodebuild -resolvePackageDependencies' first."
fi

SIGN_UPDATE="$SPARKLE_DIR/bin/sign_update"
GENERATE_APPCAST="$SPARKLE_DIR/bin/generate_appcast"

# Sign the DMG
info "Signing DMG with Sparkle EdDSA key..."
SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH" 2>&1)
ED_SIGNATURE=$(echo "$SIGNATURE" | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')

if [ -z "$ED_SIGNATURE" ]; then
    error "Failed to sign DMG"
fi

info "Signature: $ED_SIGNATURE"

# Generate appcast entry
DOWNLOAD_URL="https://github.com/laurenschristian/local-flow/releases/download/v$VERSION/$DMG_NAME"
PUB_DATE=$(date -R)

info "Updating appcast.xml..."
cat > "$PROJECT_DIR/appcast.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>LocalFlow Updates</title>
        <link>https://raw.githubusercontent.com/laurenschristian/local-flow/main/appcast.xml</link>
        <description>Updates for LocalFlow</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="$DOWNLOAD_URL"
                       type="application/octet-stream"
                       sparkle:edSignature="$ED_SIGNATURE"
                       length="$DMG_SIZE"/>
        </item>
    </channel>
</rss>
EOF

info "appcast.xml updated"

echo ""
info "Release artifacts ready:"
echo "  DMG: $DMG_PATH"
echo "  Appcast: $PROJECT_DIR/appcast.xml"
echo ""
info "Next steps:"
echo "  1. git add appcast.xml && git commit -m 'release v$VERSION'"
echo "  2. git push"
echo "  3. gh release create v$VERSION '$DMG_PATH' --title 'LocalFlow v$VERSION'"
echo ""
info "Done!"
