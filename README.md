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
- **Works in any app** — Text is inserted wherever your cursor is
- **Auto-updates** — Built-in update system keeps you current
- **Visual feedback** — Floating overlay with live audio waveform
- **Punctuation mode** — Automatically add punctuation
- **Clipboard mode** — Copy to clipboard without auto-pasting
- **History** — Access your recent transcriptions
- **Custom hotkey** — Configure your preferred trigger key
- **Sound feedback** — Audio cues for recording start/stop
- **Auto-launch** — Start LocalFlow when you log in
- **Fast** — Sub-second transcription on Apple Silicon
- **Private** — No cloud, no telemetry, no data collection

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1/M2/M3/M4)

## Installation

### Download (Recommended)

1. **Download** the latest DMG from [Releases](https://github.com/laurenschristian/local-flow/releases)

2. **Open the DMG** and drag LocalFlow to Applications

3. **First launch** — Right-click LocalFlow.app and select "Open"

   > macOS will warn that the app is from an unidentified developer. Click "Open" to proceed. This only happens once.

4. **Grant permissions** when prompted:
   - **Accessibility** — Required for hotkey detection and text insertion
   - **Microphone** — Required for voice recording

5. **Download a model** — Go to Settings > Model and download your preferred model

That's it! Double-tap Option to start dictating.

### Bypassing Gatekeeper

Since LocalFlow isn't notarized with Apple, macOS shows a warning on first launch. Two ways to handle this:

**Option A: Right-click to Open**
1. Right-click (or Control-click) on LocalFlow.app
2. Select "Open" from the menu
3. Click "Open" in the dialog

**Option B: System Settings**
1. Try to open LocalFlow normally (it will be blocked)
2. Go to System Settings > Privacy & Security
3. Scroll down to find "LocalFlow was blocked"
4. Click "Open Anyway"

### Build from Source

For developers who want to build from source, see [docs/INSTALL.md](docs/INSTALL.md).

## Usage

| Action | How |
|--------|-----|
| **Start recording** | Double-tap Option key, then hold |
| **Stop & transcribe** | Release the key |
| **Open menu** | Click waveform icon in menu bar |
| **Settings** | Click menu bar icon → Settings |
| **Check for updates** | Click menu bar icon → Check for Updates |

## Configuration

Access settings via the menu bar icon.

| Setting | Description |
|---------|-------------|
| **Model** | Choose Whisper model (tiny/base/small/medium) |
| **Hotkey** | Configure trigger key (Option, Control, Fn) |
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

**Recommendation**: Start with `small` for the best balance of speed and accuracy.

## Documentation

- [Installation Guide](docs/INSTALL.md) — Build from source
- [Model Comparison](docs/MODELS.md) — Choose the right model
- [Troubleshooting](docs/TROUBLESHOOTING.md) — Common issues
- [Privacy Policy](docs/PRIVACY.md) — How your data is handled

## Privacy

LocalFlow is designed with privacy as a core principle:

- All speech recognition happens on-device using whisper.cpp
- No internet connection required for transcription
- No data is ever sent to external servers
- No analytics or telemetry
- Update checks only fetch a small XML file from GitHub

See our full [Privacy Policy](docs/PRIVACY.md).

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Made with Swift for macOS
</p>
