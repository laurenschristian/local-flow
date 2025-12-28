# LocalFlow

A lightweight, privacy-first voice dictation app for macOS. Double-tap Option, speak, release - text appears.

## What is this?

LocalFlow is a local alternative to [Wispr Flow](https://wisprflow.ai/). All speech recognition runs on your Mac using OpenAI's Whisper model via [whisper.cpp](https://github.com/ggml-org/whisper.cpp). No internet required, no data leaves your device.

## Features

- **Double-tap to talk** - Double-tap Option key, hold and speak, release to transcribe
- **Works everywhere** - Inserts text into any app (Slack, VS Code, Safari, etc.)
- **Fast** - Sub-second transcription on Apple Silicon
- **Private** - 100% local processing, no cloud, no telemetry
- **Lightweight** - Menu bar app using < 50MB RAM when idle

## Requirements

- macOS 13.0+ (Ventura)
- Apple Silicon recommended (Intel supported with reduced speed)
- ~500MB disk space (with small model)
- Xcode 15+ for building

## Setup

### 1. Clone and build whisper.cpp

```bash
git clone https://github.com/laurenschristian/local-wisper.git
cd local-wisper

# Build whisper.cpp with Metal support
./scripts/setup-whisper.sh
```

### 2. Download a Whisper model

```bash
./scripts/download-model.sh small
```

### 3. Create Xcode project

1. Open Xcode → File → New → Project
2. Choose macOS → App
3. Product Name: `LocalFlow`
4. Bundle Identifier: `com.yourname.localflow`
5. Interface: SwiftUI, Language: Swift

### 4. Add source files

1. Delete the auto-generated ContentView.swift
2. Drag all files from `LocalFlow/` folder into Xcode
3. Ensure "Copy items if needed" is unchecked

### 5. Link whisper.cpp

In Build Settings:
- **Header Search Paths**: Add `$(PROJECT_DIR)/vendor/whisper.cpp`
- **Library Search Paths**: Add `$(PROJECT_DIR)/vendor/whisper.cpp/build`
- **Other Linker Flags**: Add `-lwhisper -lc++`

In Build Phases → Link Binary With Libraries:
- Add `Metal.framework`
- Add `Accelerate.framework`
- Add `libwhisper.a` from `vendor/whisper.cpp/build/`

### 6. Configure entitlements

1. Add `LocalFlow.entitlements` from the LocalFlow folder
2. In Signing & Capabilities, add:
   - Audio Input (for microphone)
   - Accessibility (for text insertion)

### 7. Build and run

Press Cmd+R to build and run. Grant permissions when prompted.

## Usage

1. Launch LocalFlow - it appears in your menu bar
2. Grant microphone and accessibility permissions when prompted
3. **Double-tap Option key** to start recording
4. Keep holding and speak clearly
5. Release - your text appears at the cursor

## Models

| Model | Size | Speed | Best For |
|-------|------|-------|----------|
| tiny | 75MB | Fastest | Quick notes |
| base | 142MB | Fast | General use |
| small | 466MB | Balanced | **Recommended** |
| medium | 1.5GB | Slower | High accuracy |

## Project Structure

```
local-wisper/
├── LocalFlow/
│   ├── App/
│   │   ├── LocalFlowApp.swift      # Entry point
│   │   └── AppDelegate.swift       # Menu bar setup
│   ├── Views/
│   │   ├── MenuBarView.swift       # Popover UI
│   │   └── SettingsView.swift      # Settings window
│   ├── Services/
│   │   ├── AudioRecorder.swift     # Microphone capture
│   │   ├── WhisperService.swift    # Transcription
│   │   ├── HotkeyManager.swift     # Double-tap detection
│   │   └── TextInserter.swift      # Clipboard + paste
│   ├── Models/
│   │   ├── AppState.swift          # Global state
│   │   └── Settings.swift          # User preferences
│   ├── Info.plist
│   └── LocalFlow.entitlements
├── scripts/
│   ├── setup-whisper.sh            # Build whisper.cpp
│   └── download-model.sh           # Download models
├── vendor/                          # whisper.cpp (after setup)
├── SPEC.md                          # Technical specification
└── README.md
```

## Development Status

Work in Progress - See [SPEC.md](./SPEC.md) for the full technical specification.

## Tech Stack

- Swift 5.9 / SwiftUI
- whisper.cpp (Metal + CoreML acceleration)
- AVFoundation for audio capture
- CGEvent for text insertion

## License

MIT
