#!/bin/bash
# Instructions for setting up code signing for persistent permissions
#
# macOS ties accessibility permissions to the app's code signature.
# Without consistent signing, permissions reset on each rebuild.
#
# OPTIONS:
#
# 1. EASIEST: Don't rebuild often
#    - Build once with ./scripts/build-and-install.sh
#    - Grant permissions once, they persist until next rebuild
#
# 2. FOR DEVELOPERS with Apple Developer Account:
#    - Open LocalFlow.xcodeproj in Xcode
#    - Set your Team in Signing & Capabilities
#    - Build from Xcode or use: xcodebuild -configuration Release
#
# 3. CREATE A SELF-SIGNED CERTIFICATE (manual steps):
#    a) Open Keychain Access
#    b) Menu: Keychain Access > Certificate Assistant > Create a Certificate
#    c) Name: "LocalFlow Development"
#    d) Identity Type: Self-Signed Root
#    e) Certificate Type: Code Signing
#    f) Click Create
#    g) Find the certificate, right-click > Get Info
#    h) Expand Trust, set Code Signing to "Always Trust"
#    i) Rebuild with ./scripts/build-and-install.sh
#
# After creating the certificate, the build script will automatically use it.

echo "=== LocalFlow Code Signing Setup ==="
echo ""

# Check for any signing identity
IDENTITIES=$(security find-identity -v -p codesigning 2>&1)
if echo "$IDENTITIES" | grep -q "valid identit"; then
    echo "Found signing identities:"
    echo "$IDENTITIES"
    echo ""
    echo "The build script will use the first available identity."
else
    echo "No code signing certificates found."
    echo ""
    echo "To create one, follow the instructions at the top of this script:"
    echo "  cat scripts/setup-signing.sh"
    echo ""
    echo "Or simply grant accessibility permissions after each rebuild."
fi
