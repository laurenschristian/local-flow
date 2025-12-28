# LocalFlow - Local Voice Dictation for macOS

A lightweight, privacy-first voice dictation app for macOS that runs entirely locally using OpenAI's Whisper model.

## Overview

LocalFlow is a local alternative to Wispr Flow, providing hold-to-talk voice dictation that works in any application. All processing happens on-device using whisper.cpp, optimized for Apple Silicon.

## Goals

1. **Privacy First** - All audio processing happens locally, no data leaves the device
2. **Lightweight** - Minimal CPU/memory footprint, runs as a menu bar app
3. **Fast** - Sub-second transcription using Apple Silicon acceleration
4. **Universal** - Works in any text field across all macOS applications
5. **Simple** - Hold a key, speak, release - text appears

## Core Features

### MVP (v0.1)

| Feature | Description |
|---------|-------------|
| Double-tap to talk | Double-tap Option key to start recording, hold and speak, release to transcribe |
| Local Whisper | whisper.cpp with Metal/CoreML acceleration for Apple Silicon |
| Text insertion | Automatically type transcribed text at cursor position |
| Menu bar app | Lightweight presence with status indicator |
| Model selection | Support tiny/base/small/medium models (trade-off speed vs accuracy) |

### Future (v0.2+)

| Feature | Description |
|---------|-------------|
| Voice activity detection | Auto-stop when silence detected |
| Text cleanup | Remove filler words (um, uh, like) |
| Corrections | Handle "no wait" / "I mean" style corrections |
| Custom vocabulary | Add domain-specific words |
| Multiple languages | Beyond English support |
| Audio history | Optional local storage of recordings |

## Technical Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     LocalFlow App                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Menu Bar   │  │   Hotkey    │  │   Settings Window   │  │
│  │   Status    │  │   Manager   │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │                  Audio Pipeline                          ││
│  │  ┌──────────┐   ┌──────────┐   ┌──────────────────────┐ ││
│  │  │ AVAudio  │ → │  Buffer  │ → │  whisper.cpp/Swift   │ ││
│  │  │ Engine   │   │  Manager │   │  (Metal/CoreML)      │ ││
│  │  └──────────┘   └──────────┘   └──────────────────────┘ ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │                  Text Insertion                          ││
│  │  ┌──────────────┐   ┌────────────────────────────────┐  ││
│  │  │  Clipboard   │ → │  CGEvent (Cmd+V simulation)    │  ││
│  │  │  Manager     │   │  or keystroke injection        │  ││
│  │  └──────────────┘   └────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Language | Swift 5.9+ | Native macOS, low overhead, excellent performance |
| UI Framework | SwiftUI | Modern, declarative, lightweight for menu bar apps |
| Audio Capture | AVFoundation | Native macOS audio APIs |
| Speech Recognition | whisper.cpp | C++ port optimized for Apple Silicon |
| ML Acceleration | Metal/CoreML | Hardware acceleration on Apple Silicon |
| Global Hotkey | Carbon/CGEvent | System-wide keyboard monitoring |
| Text Insertion | CGEvent | Simulate keystrokes for universal compatibility |
| Storage | UserDefaults | Simple settings persistence |

## System Requirements

- macOS 13.0+ (Ventura or later)
- Apple Silicon (M1/M2/M3) recommended
- Intel Macs supported with reduced performance
- ~150MB disk space (app + base model)
- ~200MB RAM during transcription

## Whisper Model Options

| Model | Size | VRAM | Speed* | Accuracy |
|-------|------|------|--------|----------|
| tiny.en | 75MB | ~125MB | ~10x realtime | Good for short phrases |
| base.en | 142MB | ~200MB | ~7x realtime | Better accuracy |
| small.en | 466MB | ~500MB | ~4x realtime | Recommended default |
| medium.en | 1.5GB | ~1.5GB | ~2x realtime | High accuracy |

*Speed on M1 Pro with Metal acceleration

## Implementation Plan

### Phase 1: Foundation (Core App)

1. **Project Setup**
   - Create Xcode project with SwiftUI
   - Configure as menu bar app (LSUIElement)
   - Set up signing and entitlements

2. **whisper.cpp Integration**
   - Add whisper.cpp as Swift Package or embedded framework
   - Build with Metal and CoreML support
   - Create Swift wrapper for C++ interface

3. **Audio Pipeline**
   - AVAudioEngine setup for microphone capture
   - Audio buffer management (16kHz, mono, float32)
   - Recording state machine

### Phase 2: Core Functionality

4. **Global Hotkey**
   - Carbon Event Manager for Fn key detection
   - Or CGEvent tap for custom key combinations
   - Hold-to-record, release-to-transcribe pattern

5. **Transcription**
   - Load Whisper model on app launch
   - Process audio buffer on release
   - Handle transcription in background thread

6. **Text Insertion**
   - Save current clipboard contents
   - Copy transcription to clipboard
   - Simulate Cmd+V keystroke
   - Restore original clipboard

### Phase 3: Polish

7. **Menu Bar UI**
   - Status indicator (idle/recording/processing)
   - Quick access to settings
   - Model download/selection

8. **Settings**
   - Hotkey configuration
   - Model selection
   - Audio input device selection
   - Launch at login toggle

9. **Model Management**
   - Download models from Hugging Face
   - Progress indicator
   - Local storage in Application Support

## File Structure

```
LocalFlow/
├── LocalFlow.xcodeproj
├── LocalFlow/
│   ├── App/
│   │   ├── LocalFlowApp.swift          # App entry point
│   │   └── AppDelegate.swift           # Menu bar setup
│   ├── Views/
│   │   ├── MenuBarView.swift           # Menu bar popover
│   │   ├── SettingsView.swift          # Settings window
│   │   └── RecordingOverlay.swift      # Visual feedback
│   ├── Services/
│   │   ├── AudioRecorder.swift         # AVAudioEngine wrapper
│   │   ├── WhisperService.swift        # whisper.cpp wrapper
│   │   ├── HotkeyManager.swift         # Global hotkey handling
│   │   └── TextInserter.swift          # Clipboard + CGEvent
│   ├── Models/
│   │   ├── AppState.swift              # Global app state
│   │   └── Settings.swift              # User preferences
│   ├── Resources/
│   │   └── Assets.xcassets
│   └── Info.plist
├── WhisperKit/                          # whisper.cpp Swift wrapper
│   ├── Package.swift
│   └── Sources/
├── Scripts/
│   └── download-model.sh               # Model download helper
└── README.md
```

## Entitlements Required

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

## Privacy Permissions

The app will request:
1. **Microphone Access** - Required for audio recording
2. **Accessibility** - Required for text insertion via CGEvent

## Performance Targets

| Metric | Target |
|--------|--------|
| Cold start | < 2 seconds |
| Model load | < 3 seconds (small.en) |
| Transcription latency | < 500ms for 5s audio |
| Idle CPU | < 0.1% |
| Idle RAM | < 50MB |
| Recording CPU | < 5% |
| Transcription CPU | < 100% (burst) |

## Alternative Approaches Considered

### WhisperKit vs whisper.cpp

| Approach | Pros | Cons |
|----------|------|------|
| whisper.cpp | Battle-tested, C++ speed, Metal support | Requires bridging to Swift |
| WhisperKit | Pure Swift, Apple-native CoreML | Newer, less battle-tested |

**Decision**: Start with whisper.cpp for proven performance, consider WhisperKit migration later.

### Text Insertion Methods

| Method | Pros | Cons |
|--------|------|------|
| Clipboard + Cmd+V | Universal, simple | Overwrites clipboard |
| CGEvent keystroke injection | No clipboard impact | Complex, character mapping |
| Accessibility API (AXUIElement) | Direct text insertion | Requires more permissions |

**Decision**: Use Clipboard + Cmd+V with clipboard preservation for MVP simplicity.

## Security Considerations

1. **No network access** - App operates fully offline
2. **No data storage** - Audio is processed and discarded
3. **Sandboxed** - Minimal system access
4. **Code signed** - Notarized for Gatekeeper

## Testing Strategy

### Unit Tests
- Audio buffer conversion (16kHz, mono, float32)
- Settings persistence
- Model loading/unloading

### Integration Tests
- Full recording → transcription pipeline
- Hotkey registration/unregistration
- Text insertion in various apps

### Manual Testing Checklist
- [ ] Works in Safari text fields
- [ ] Works in VS Code
- [ ] Works in Slack
- [ ] Works in Terminal
- [ ] Works in Notes
- [ ] Works in Messages
- [ ] Handles rapid start/stop
- [ ] Handles long recordings (30s+)
- [ ] Memory doesn't leak over time

## Open Questions

1. **Fn key detection** - Fn key is special on macOS, may need alternative default (e.g., Right Option)
2. **WhisperKit adoption** - Should we use Apple's newer WhisperKit instead of whisper.cpp?
3. **Text cleanup** - Local LLM for filler word removal, or regex-based?
4. **Distribution** - App Store (sandbox limits) or direct download?

## References

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) - C++ Whisper implementation
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Swift Whisper for Apple
- [OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) - Similar open-source project
- [Wispr Flow](https://wisprflow.ai/) - Commercial inspiration
- [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) - Commercial Mac Whisper app

## Success Criteria

1. User can hold hotkey, speak, release, and see text appear in < 1 second
2. App uses < 50MB RAM when idle
3. Transcription accuracy matches Whisper small.en benchmarks
4. Works reliably across common macOS apps
5. No internet connection required
