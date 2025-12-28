#!/bin/bash

# Setup whisper.cpp for LocalFlow
# This script downloads and builds whisper.cpp as a static library

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/vendor"
WHISPER_DIR="$VENDOR_DIR/whisper.cpp"

echo "Setting up whisper.cpp for LocalFlow..."
echo ""

# Create vendor directory
mkdir -p "$VENDOR_DIR"

# Clone or update whisper.cpp
if [[ -d "$WHISPER_DIR" ]]; then
    echo "Updating whisper.cpp..."
    cd "$WHISPER_DIR"
    git pull
else
    echo "Cloning whisper.cpp..."
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
    cd "$WHISPER_DIR"
fi

echo ""
echo "Building whisper.cpp with Metal support..."
echo ""

# Build with Metal support for Apple Silicon
mkdir -p build
cd build

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_METAL=ON \
    -DWHISPER_COREML=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_OSX_ARCHITECTURES="arm64"

cmake --build . --config Release -j$(sysctl -n hw.ncpu)

echo ""
echo "Build complete!"
echo ""
echo "Library location: $WHISPER_DIR/build/libwhisper.a"
echo "Header location: $WHISPER_DIR/whisper.h"
echo ""
echo "Next steps:"
echo "1. Open Xcode and create a new macOS App project named 'LocalFlow'"
echo "2. Add the Swift files from LocalFlow/ to the project"
echo "3. Add $WHISPER_DIR/build/libwhisper.a to Link Binary With Libraries"
echo "4. Add $WHISPER_DIR to Header Search Paths"
echo "5. Add -lc++ to Other Linker Flags"
echo "6. Add Metal.framework and Accelerate.framework"
