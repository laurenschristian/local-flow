# LocalFlow

A lightweight, privacy-first voice dictation app for macOS. Double-tap Option, speak, release - text appears.

## What is this?

LocalFlow is a local alternative to [Wispr Flow](https://wisprflow.ai/). All speech recognition runs on your Mac using OpenAI's Whisper model via [whisper.cpp](https://github.com/ggml-org/whisper.cpp). No internet required, no data leaves your device.

## Features

- **Double-tap to talk** - Double-tap Option key, hold and speak, release to transcribe
- **Works everywhere** - Inserts text into any app (Slack, VS Code, Safari, etc.)
- **Visual feedback** - Floating overlay shows recording status with live audio visualization
- **Fast** - Sub-second transcription on Apple Silicon
- **Private** - 100% local processing, no cloud, no telemetry
- **Lightweight** - Menu bar app using < 50MB RAM when idle

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1/M2/M3)
- ~500MB disk space (with small model)
- Xcode 15+ and XcodeGen

## Quick Start

```bash
# Install XcodeGen if not already installed
brew install xcodegen

# Clone the repo
git clone https://github.com/laurenschristian/local-wisper.git
cd local-wisper

# Build whisper.cpp with Metal support
./scripts/setup-whisper.sh

# Download a Whisper model (small recommended)
./scripts/download-model.sh small

# Generate Xcode project and build
xcodegen generate
./scripts/build-and-install.sh

# Grant accessibility permissions (opens System Settings)
./scripts/grant-permissions.sh
```

## Permissions

LocalFlow requires two permissions:

| Permission | Purpose | How to Grant |
|------------|---------|--------------|
| Microphone | Record your voice | Automatic prompt on first use |
| Accessibility | Insert text into apps | Run `./scripts/grant-permissions.sh` |

**Note on rebuilding**: Accessibility permissions are tied to the app's code signature. If you rebuild, you'll need to re-grant access. For persistent permissions, see `scripts/setup-signing.sh`.

## Usage

1. **Launch** - LocalFlow appears in your menu bar (waveform icon)
2. **Record** - Double-tap Option key, then hold and speak
3. **Transcribe** - Release to transcribe and insert text at cursor
4. **Done** - Text appears wherever your cursor is

The floating overlay shows:
- **Listening** - Recording with live audio visualization
- **Processing** - Transcribing your speech

## Models

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| tiny | 75MB | Fastest | Basic | Quick notes, testing |
| base | 142MB | Fast | Good | General use |
| small | 466MB | Balanced | Better | **Recommended** |
| medium | 1.5GB | Slower | Best | High accuracy needs |

Download different models:
```bash
./scripts/download-model.sh tiny    # Fastest
./scripts/download-model.sh base    # Balanced
./scripts/download-model.sh small   # Recommended
./scripts/download-model.sh medium  # Most accurate
```

## Troubleshooting

**"Failed to load model"**
- Ensure you've downloaded a model: `./scripts/download-model.sh small`
- Check the model exists: `ls models/`

**Hotkey not working**
- Grant accessibility permissions: `./scripts/grant-permissions.sh`
- Check System Settings > Privacy & Security > Accessibility

**No audio recording**
- Grant microphone access when prompted
- Check System Settings > Privacy & Security > Microphone

## Project Structure

```
local-wisper/
├── LocalFlow/
│   ├── App/
│   │   ├── LocalFlowApp.swift       # App entry point
│   │   └── AppDelegate.swift        # Menu bar + orchestration
│   ├── Views/
│   │   ├── MenuBarView.swift        # Menu bar popover
│   │   ├── SettingsView.swift       # Settings window
│   │   └── RecordingOverlay.swift   # Floating recording indicator
│   ├── Services/
│   │   ├── AudioRecorder.swift      # Microphone capture (16kHz)
│   │   ├── WhisperService.swift     # Whisper transcription
│   │   ├── HotkeyManager.swift      # Double-tap Option detection
│   │   └── TextInserter.swift       # Clipboard + Cmd+V paste
│   └── Models/
│       ├── AppState.swift           # Global app state
│       └── Settings.swift           # User preferences
├── scripts/
│   ├── setup-whisper.sh             # Clone + build whisper.cpp
│   ├── download-model.sh            # Download Whisper models
│   ├── build-and-install.sh         # Build + install to /Applications
│   ├── grant-permissions.sh         # Open accessibility settings
│   └── setup-signing.sh             # Code signing instructions
├── models/                          # Whisper models (after download)
├── vendor/                          # whisper.cpp (after setup)
└── project.yml                      # XcodeGen configuration
```

## How It Works

1. **Hotkey Detection** - CGEvent tap monitors for double-tap Option key
2. **Audio Capture** - AVAudioEngine records at 16kHz mono (Whisper's expected format)
3. **Transcription** - whisper.cpp processes audio using Metal GPU acceleration
4. **Text Insertion** - Copies text to clipboard and simulates Cmd+V

## Tech Stack

- Swift 5.9 / SwiftUI
- whisper.cpp with Metal acceleration
- AVFoundation for audio
- CGEvent for global hotkeys and text insertion
- XcodeGen for project generation

## Contributing

1. Fork the repo
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a PR

## License

MIT
