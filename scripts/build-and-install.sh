#!/bin/bash
# Build and install LocalFlow to /Applications

set -e

cd "$(dirname "$0")/.."

# Check for any signing identity
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "1)" | sed 's/.*"\(.*\)"/\1/')

echo "Building LocalFlow..."
xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -configuration Release build 2>&1 | grep -E "(BUILD|error:)" || true

echo ""
echo "Installing to /Applications..."
pkill -f LocalFlow 2>/dev/null || true
sleep 1

rm -rf /Applications/LocalFlow.app 2>/dev/null || true
cp -R ~/Library/Developer/Xcode/DerivedData/LocalFlow-*/Build/Products/Release/LocalFlow.app /Applications/

# Re-sign with consistent certificate if available
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing with '$SIGNING_IDENTITY'..."
    codesign --force --deep --sign "$SIGNING_IDENTITY" /Applications/LocalFlow.app 2>/dev/null || {
        echo "Warning: Signing failed, using ad-hoc signing"
        codesign --force --deep --sign - /Applications/LocalFlow.app
    }
else
    echo "No signing certificate found (permissions will reset on rebuild)"
    echo "Run: cat scripts/setup-signing.sh for instructions on persistent signing"
    codesign --force --deep --sign - /Applications/LocalFlow.app
fi

echo ""
echo "Launching LocalFlow..."
open /Applications/LocalFlow.app

echo ""
echo "Done! LocalFlow is running from /Applications"
