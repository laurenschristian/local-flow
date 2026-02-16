#!/bin/bash
set -e

# LocalFlow - First-time setup
# Idempotent: safe to run multiple times

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "  LocalFlow - Setup"
echo "  ─────────────────"
echo ""

# ── Check prerequisites ────────────────────────────────────────────

# Apple Silicon check
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    fail "Apple Silicon (M1/M2/M3/M4) required. Detected: $ARCH"
fi
info "Apple Silicon detected"

# Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    warn "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Re-run this script after installation completes."
    exit 1
fi
info "Xcode CLI tools installed"

# cmake
if ! command -v cmake &>/dev/null; then
    if command -v brew &>/dev/null; then
        warn "Installing cmake via Homebrew..."
        brew install cmake
    else
        fail "cmake not found. Install with: brew install cmake"
    fi
fi
info "cmake available"

# xcodegen (optional but used by release script)
if command -v xcodegen &>/dev/null; then
    info "xcodegen available"
else
    warn "xcodegen not found (optional - needed for 'make release')"
    echo "    Install with: brew install xcodegen"
fi

# ── Build whisper.cpp ──────────────────────────────────────────────

if [ -f "vendor/whisper.cpp/build/src/libwhisper.a" ]; then
    info "whisper.cpp already built"
else
    echo ""
    echo "  Building whisper.cpp (this takes ~2 minutes)..."
    echo ""
    ./scripts/setup-whisper.sh
    info "whisper.cpp built"
fi

# ── Generate Xcode project ────────────────────────────────────────

if command -v xcodegen &>/dev/null; then
    echo ""
    info "Generating Xcode project from project.yml..."
    xcodegen generate 2>/dev/null
    info "Xcode project generated"
elif [ -f "LocalFlow.xcodeproj/project.pbxproj" ]; then
    info "Xcode project exists (skipping xcodegen)"
else
    warn "No Xcode project found and xcodegen not available"
    echo "    Install xcodegen: brew install xcodegen"
    echo "    Then run: xcodegen generate"
fi

# ── Done ───────────────────────────────────────────────────────────

echo ""
echo "  ─────────────────────────────────────────"
echo -e "  ${GREEN}Setup complete!${NC}"
echo ""
echo "  Next steps:"
echo "    make build          Build the app"
echo "    make install-dev    Install to /Applications (preserves permissions)"
echo "    make download-model Download Whisper model (default: small)"
echo ""
echo "  Or open in Xcode:"
echo "    open LocalFlow.xcodeproj"
echo ""
