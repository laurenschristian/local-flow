<p align="center">
  <img src="LocalFlow/Assets.xcassets/AppIcon.appiconset/icon_256.png" alt="LocalFlow" width="128" height="128">
</p>

<h1 align="center">LocalFlow</h1>

<p align="center">
  <strong>Voice-to-text that runs entirely on your Mac</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/chip-Apple%20Silicon-orange" alt="Chip">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

LocalFlow is a privacy-first voice dictation app for macOS. Speech recognition runs 100% locally using OpenAI's Whisper model—no internet connection required, no data ever leaves your device.

## Features

- **Double-tap to dictate** — Double-tap Option key, hold and speak, release to transcribe
- **Works in any app** — Text is inserted wherever your cursor is (Slack, VS Code, Notes, browsers, etc.)
- **Visual feedback** — Floating overlay shows recording status with live audio waveform
- **Punctuation mode** — Automatically add punctuation based on speech patterns
- **Clipboard mode** — Copy to clipboard without auto-pasting
- **History** — Access your recent transcriptions
- **Custom hotkey** — Configure your preferred trigger key
- **Sound feedback** — Audio cues for recording start/stop
- **Auto-launch** — Start LocalFlow when you log in
- **Fast** — Sub-second transcription on Apple Silicon
- **Private** — No cloud, no telemetry, no data collection
- **Lightweight** — Under 50MB RAM when idle

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1/M2/M3/M4)
- ~500MB disk space
- Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Installation

```bash
# Install dependencies
brew install xcodegen cmake

# Clone repository
git clone https://github.com/laurenschristian/local-flow.git
cd local-flow

# Build whisper.cpp with Metal acceleration
./scripts/setup-whisper.sh

# Download Whisper model
./scripts/download-model.sh small

# Build and install
xcodegen generate
./scripts/build-and-install.sh

# Grant accessibility permissions
./scripts/grant-permissions.sh
```

For detailed instructions, see the [Installation Guide](docs/INSTALL.md).

## Usage

| Action | How |
|--------|-----|
| **Start recording** | Double-tap Option key, then hold |
| **Stop & transcribe** | Release the key |
| **Open menu** | Click waveform icon in menu bar |
| **Settings** | Click menu bar icon → Settings |

The floating overlay indicates current status:
- **Listening** — Recording your voice (shows live waveform)
- **Processing** — Transcribing speech to text

## Configuration

Access settings via the menu bar icon.

| Setting | Description |
|---------|-------------|
| **Model** | Choose Whisper model (tiny/base/small/medium) |
| **Hotkey** | Configure trigger key |
| **Punctuation** | Auto-add punctuation |
| **Clipboard mode** | Copy only, don't paste |
| **Sound feedback** | Play sounds on record start/stop |
| **Launch at login** | Start automatically |

## Models

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| tiny | 75MB | ★★★★★ | ★★☆☆☆ |
| base | 142MB | ★★★★☆ | ★★★☆☆ |
| small | 466MB | ★★★☆☆ | ★★★★☆ |
| medium | 1.5GB | ★★☆☆☆ | ★★★★★ |

Download models with:
```bash
./scripts/download-model.sh <model-name>
```

## Architecture

```
LocalFlow/
├── App/                    # Application entry & lifecycle
├── Views/                  # SwiftUI views
│   ├── MenuBarView         # Menu bar popover
│   ├── SettingsView        # Preferences window
│   ├── HistoryView         # Transcription history
│   └── RecordingOverlay    # Floating status indicator
├── Services/               # Core functionality
│   ├── AudioRecorder       # Microphone capture
│   ├── WhisperService      # Speech recognition
│   ├── HotkeyManager       # Global hotkey detection
│   └── TextInserter        # Text insertion
└── Models/                 # Data models & state
```

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI | SwiftUI |
| Speech Recognition | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) |
| GPU Acceleration | Metal |
| Audio | AVFoundation |
| Hotkeys | CGEvent |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Made with Swift for macOS
</p>
