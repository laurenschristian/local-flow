#!/bin/bash
set -e

# Create a self-signed code signing certificate for persistent accessibility permissions.
# macOS ties accessibility permissions to code signature — without consistent signing,
# permissions reset on every rebuild.

CERT_NAME="LocalFlow Development"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Check if certificate already exists
if security find-identity -v -p codesigning 2>&1 | grep -q "$CERT_NAME"; then
    info "Certificate '$CERT_NAME' already exists"
    echo ""
    echo "Your build scripts will automatically use this certificate."
    echo "Accessibility permissions will persist across rebuilds."
    exit 0
fi

echo ""
echo "  Creating self-signed code signing certificate"
echo "  ──────────────────────────────────────────────"
echo ""
echo "  This creates a certificate called '$CERT_NAME' in your keychain."
echo "  It allows accessibility permissions to persist across rebuilds."
echo ""

# Create certificate using security command
# This uses a temporary cert config
CERT_CONFIG=$(mktemp)
cat > "$CERT_CONFIG" << 'EOF'
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
[ req_dn ]
CN = LocalFlow Development
[ v3_code_signing ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

TEMP_KEY=$(mktemp)
TEMP_CERT=$(mktemp)
TEMP_P12=$(mktemp)

# Generate key and cert
openssl req -x509 -newkey rsa:2048 -keyout "$TEMP_KEY" -out "$TEMP_CERT" \
    -days 3650 -nodes -config "$CERT_CONFIG" -extensions v3_code_signing 2>/dev/null

# Create PKCS12 bundle
openssl pkcs12 -export -out "$TEMP_P12" -inkey "$TEMP_KEY" -in "$TEMP_CERT" \
    -passout pass: 2>/dev/null

# Import into keychain
security import "$TEMP_P12" -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign -P "" 2>/dev/null || \
security import "$TEMP_P12" -k ~/Library/Keychains/login.keychain \
    -T /usr/bin/codesign -P "" 2>/dev/null

# Clean up
rm -f "$CERT_CONFIG" "$TEMP_KEY" "$TEMP_CERT" "$TEMP_P12"

# Verify
if security find-identity -v -p codesigning 2>&1 | grep -q "$CERT_NAME"; then
    info "Certificate created successfully"
    echo ""
    warn "You need to trust the certificate:"
    echo "    1. Open Keychain Access"
    echo "    2. Find '$CERT_NAME' in login keychain"
    echo "    3. Double-click it > Trust > Code Signing: Always Trust"
    echo ""
    echo "  After trusting, rebuild with: make install"
    echo "  Accessibility permissions will persist across rebuilds."
else
    echo -e "${RED}[✗]${NC} Failed to create certificate"
    echo ""
    echo "  Manual alternative:"
    echo "    1. Open Keychain Access"
    echo "    2. Menu: Keychain Access > Certificate Assistant > Create a Certificate"
    echo "    3. Name: '$CERT_NAME'"
    echo "    4. Type: Self-Signed Root, Certificate Type: Code Signing"
    echo "    5. Trust it for Code Signing"
    exit 1
fi
