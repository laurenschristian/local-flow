# LocalFlow Installation Guide

Complete guide to installing LocalFlow on your Mac.

## System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| macOS | 14.0 (Sonoma) | 14.0+ |
| Chip | Apple Silicon (M1) | M1 Pro/Max or newer |
| RAM | 8GB | 16GB |
| Disk Space | 500MB | 1GB |
| Xcode | 15.0 | Latest |

## Prerequisites

### 1. Install Xcode Command Line Tools

```bash
xcode-select --install
```

### 2. Install Homebrew (if not installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Install Required Tools

```bash
brew install xcodegen cmake
```

## Installation

### Step 1: Clone the Repository

```bash
git clone https://github.com/laurenschristian/local-flow.git
cd local-flow
```

### Step 2: Build whisper.cpp

This builds the speech recognition engine with Metal GPU acceleration:

```bash
./scripts/setup-whisper.sh
```

This will:
- Clone whisper.cpp from GitHub
- Build with Metal support for Apple Silicon
- Create necessary library files

**Expected time**: 2-5 minutes

### Step 3: Download a Whisper Model

```bash
./scripts/download-model.sh small
```

Available models:

| Model | Download Size | Disk Size | RAM Usage |
|-------|---------------|-----------|-----------|
| tiny | 75MB | 75MB | ~400MB |
| base | 142MB | 142MB | ~500MB |
| small | 466MB | 466MB | ~1GB |
| medium | 1.5GB | 1.5GB | ~2.5GB |

**Recommendation**: Start with `small` for the best balance of speed and accuracy.

### Step 4: Generate Xcode Project

```bash
xcodegen generate
```

### Step 5: Build and Install

```bash
./scripts/build-and-install.sh
```

This will:
- Build LocalFlow in Release mode
- Install to `/Applications/LocalFlow.app`
- Launch the app

### Step 6: Grant Permissions

LocalFlow needs two permissions to function:

#### Microphone Access
- Automatically prompted on first recording attempt
- Click "OK" when prompted

#### Accessibility Access
Run this command to open System Settings:

```bash
./scripts/grant-permissions.sh
```

Then:
1. Find LocalFlow in the list
2. Toggle it ON
3. If not listed, click '+' and navigate to `/Applications/LocalFlow.app`

## Verifying Installation

1. Look for the waveform icon in your menu bar
2. Click it to see the status (should show "Ready")
3. Double-tap the Option key to test recording
4. Speak a few words, then release
5. Your text should appear at the cursor

## Updating LocalFlow

To update to a new version:

```bash
cd local-flow
git pull origin main
./scripts/build-and-install.sh
./scripts/grant-permissions.sh  # Re-grant if needed
```

## Uninstalling

```bash
# Remove the app
rm -rf /Applications/LocalFlow.app

# Remove models (optional)
rm -rf ~/path/to/local-flow/models/*.bin

# Remove the repository (optional)
rm -rf ~/path/to/local-flow
```

## Troubleshooting

### Build Fails with "whisper.h not found"

Ensure whisper.cpp was built correctly:

```bash
ls vendor/whisper.cpp/build/src/libwhisper.a
```

If missing, rebuild:

```bash
rm -rf vendor/whisper.cpp
./scripts/setup-whisper.sh
```

### "Failed to load model" Error

1. Check model exists:
   ```bash
   ls models/
   ```

2. Re-download if needed:
   ```bash
   ./scripts/download-model.sh small
   ```

### Hotkey Not Working

1. Check accessibility permissions:
   ```bash
   ./scripts/grant-permissions.sh
   ```

2. Ensure LocalFlow is toggled ON in the list

3. Try restarting LocalFlow:
   ```bash
   pkill LocalFlow
   open /Applications/LocalFlow.app
   ```

### No Sound/Recording

1. Check microphone permissions in System Settings > Privacy & Security > Microphone
2. Ensure LocalFlow is listed and enabled
3. Test your microphone in another app

## Getting Help

- [GitHub Issues](https://github.com/laurenschristian/local-flow/issues)
- Check existing issues before creating new ones
- Include macOS version, chip type, and error messages
