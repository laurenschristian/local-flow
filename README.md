# LocalFlow

A lightweight, privacy-first voice dictation app for macOS. Hold a key, speak, release - text appears.

## What is this?

LocalFlow is a local alternative to [Wispr Flow](https://wisprflow.ai/). All speech recognition runs on your Mac using OpenAI's Whisper model via [whisper.cpp](https://github.com/ggml-org/whisper.cpp). No internet required, no data leaves your device.

## Features

- **Hold-to-talk** - Hold your hotkey, speak naturally, release to transcribe
- **Works everywhere** - Inserts text into any app (Slack, VS Code, Safari, etc.)
- **Fast** - Sub-second transcription on Apple Silicon
- **Private** - 100% local processing, no cloud, no telemetry
- **Lightweight** - Menu bar app using < 50MB RAM when idle

## Requirements

- macOS 13.0+ (Ventura)
- Apple Silicon recommended (Intel supported with reduced speed)
- ~200MB disk space

## Installation

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/local-wisper.git
cd local-wisper

# Download a Whisper model
./scripts/download-model.sh small.en

# Open in Xcode and build
open LocalFlow.xcodeproj
```

## Usage

1. Launch LocalFlow - it appears in your menu bar
2. Grant microphone and accessibility permissions when prompted
3. Hold the hotkey (default: Right Option key)
4. Speak clearly
5. Release - your text appears at the cursor

## Models

| Model | Size | Speed | Best For |
|-------|------|-------|----------|
| tiny.en | 75MB | Fastest | Quick notes |
| base.en | 142MB | Fast | General use |
| small.en | 466MB | Balanced | **Recommended** |
| medium.en | 1.5GB | Slower | High accuracy |

## Development Status

🚧 **Work in Progress**

See [SPEC.md](./SPEC.md) for the full technical specification.

## Tech Stack

- Swift 5.9 / SwiftUI
- whisper.cpp (Metal + CoreML acceleration)
- AVFoundation for audio
- CGEvent for text insertion

## License

MIT
