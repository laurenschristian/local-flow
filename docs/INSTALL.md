# LocalFlow Installation Guide

## Quick Install (Recommended)

Download the latest DMG from [Releases](https://github.com/laurenschristian/local-flow/releases) and follow the instructions in the [README](../README.md#installation).

---

## Build from Source

This guide is for developers who want to build LocalFlow from source.

### Requirements

| Requirement | Minimum |
|-------------|---------|
| macOS | 14.0 (Sonoma) |
| Chip | Apple Silicon (M1+) |
| Xcode | 15.0+ |
| RAM | 8GB |
| Disk | 1GB |

### Prerequisites

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install Homebrew (if needed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install xcodegen cmake
```

### Build Steps

```bash
# Clone repository
git clone https://github.com/laurenschristian/local-flow.git
cd local-flow

# Build whisper.cpp with Metal acceleration
./scripts/setup-whisper.sh

# Download Whisper model
./scripts/download-model.sh small

# Generate Xcode project
xcodegen generate

# Build and install
./scripts/build-and-install.sh
```

### Grant Permissions

After building, you need to grant permissions:

1. **Accessibility**: System Settings > Privacy & Security > Accessibility
   - Click the + button
   - Navigate to `/Applications/LocalFlow.app`
   - Toggle ON

2. **Microphone**: Automatically prompted on first recording

> **Note**: When building from source, accessibility permissions reset each time you rebuild because the code signature changes. This is expected macOS behavior. For persistent permissions, use the pre-built DMG from Releases.

### Models

Download models with:

```bash
./scripts/download-model.sh <model>
```

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| tiny | 75MB | Fastest | Basic |
| base | 142MB | Fast | Good |
| small | 466MB | Medium | Better |
| medium | 1.5GB | Slow | Best |

### Development

```bash
# Regenerate project after changes to project.yml
xcodegen generate

# Build release
xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -configuration Release build

# Run tests
xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow test
```

### Creating a Release

```bash
# Bump version
./scripts/bump-version.sh 0.3.0

# Build, create DMG, sign, update appcast
./scripts/release.sh

# Commit and push
git add appcast.xml
git commit -m "release v0.3.0"
git push

# Create GitHub release
gh release create v0.3.0 build/LocalFlow-v0.3.0-mac-arm64.dmg --title "LocalFlow v0.3.0"
```

### Troubleshooting

**"whisper.h not found"**
```bash
rm -rf vendor/whisper.cpp
./scripts/setup-whisper.sh
```

**"Failed to load model"**
```bash
./scripts/download-model.sh small
```

**Hotkey not working**
- Check System Settings > Privacy & Security > Accessibility
- Ensure LocalFlow is toggled ON
- Restart the app

**Accessibility resets after rebuild**

This is expected. Each build creates a new code signature. Use the pre-built DMG for persistent permissions, or re-grant after each build during development.

### Getting Help

- [GitHub Issues](https://github.com/laurenschristian/local-flow/issues)
