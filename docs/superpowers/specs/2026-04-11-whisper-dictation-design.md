# WhisperDictation Design Spec

**Date**: 2026-04-11
**Status**: Draft
**Goal**: Build a local macOS dictation app (Willow Voice / WisprFlow clone) for use while programming, including in terminal apps like Claude Code.

## Overview

WhisperDictation is a native macOS menu bar app that provides push-to-talk voice dictation powered by whisper.cpp running entirely locally. Hold a hotkey to record, release to transcribe, and text is typed at the cursor position in any app.

**Key principles**: Zero cost (fully local), fast (~0.5-1s transcription), private (no data leaves the machine), developer-friendly (optimized for technical vocabulary).

## Architecture

```
┌──────────────────────────────────────────────────┐
│               WhisperDictation.app                │
│                                                    │
│  ┌────────────┐  ┌────────────┐  ┌─────────────┐ │
│  │ MenuBarUI   │  │ HotkeyMonitor│ │ SettingsView│ │
│  │ (SwiftUI)   │  │ (CGEvent)    │ │ (SwiftUI)   │ │
│  └──────┬──────┘  └──────┬──────┘  └─────────────┘ │
│         │                │                          │
│  ┌──────▼────────────────▼──────┐                  │
│  │       DictationEngine        │                  │
│  │  State: idle → recording →   │                  │
│  │    processing → typing       │                  │
│  └──┬──────────┬──────────┬─────┘                  │
│     │          │          │                          │
│  ┌──▼────┐ ┌──▼──────┐ ┌─▼───────────┐            │
│  │Audio  │ │Whisper  │ │TextInjector │            │
│  │Capture│ │Bridge   │ │(CGEvents)   │            │
│  │(AVF)  │ │(C API)  │ └─────────────┘            │
│  └───────┘ └──┬──────┘                             │
│               │                                     │
│          ┌────▼──────┐                              │
│          │whisper.cpp │                              │
│          │(static lib │                              │
│          │+ Metal GPU)│                              │
│          └───────────┘                               │
└──────────────────────────────────────────────────┘
```

## Components

### 1. MenuBarUI (SwiftUI)

- `MenuBarExtra` with a microphone icon
- Icon states: gray (idle), red (recording), orange (processing)
- Dropdown menu: status text, settings access, quit
- No dock icon — menu bar only (`LSUIElement = true`)

### 2. HotkeyMonitor

- Uses `CGEvent.tapCreate` for global key monitoring
- Default hotkey: **right Option key** (easily reachable, rarely conflicts)
- Detects key-down → starts recording, key-up → stops recording and triggers transcription
- Requires Accessibility permission
- Configurable hotkey via settings

### 3. Audio Capture (AVAudioEngine)

- Uses AVFoundation's `AVAudioEngine` for real-time mic capture
- Records to an in-memory buffer: **16kHz, mono, Float32** (native whisper.cpp format)
- No temp files — audio stays in memory for minimum latency
- Requires Microphone permission
- Supports selecting audio input device in settings

### 4. WhisperBridge (C Bridging Header)

- Wraps whisper.cpp's C API (`whisper.h`) via a Swift bridging header
- **Model loading**: Loads `ggml-small.en.bin` once at app startup, keeps in memory
- **Inference**: Takes Float32 audio buffer, returns transcribed String
- **Initial prompt**: Passes developer vocabulary prompt to bias recognition toward technical terms
- **Threading**: Runs inference on a background queue to keep UI responsive
- Metal GPU acceleration enabled for fast inference

### 5. TextInjector (CGEvents)

- Uses `CGEvent` to simulate keystrokes at the current cursor position
- Types transcribed text character-by-character
- Works in any app: terminal (Claude Code, iTerm), editors (VS Code, Xcode), browsers, etc.
- Handles special characters and Unicode
- Requires Accessibility permission (same as HotkeyMonitor)

### 6. SoundFeedback

- Plays short audio cues using `NSSound` or `AudioServicesPlaySystemSound`
- Three sounds:
  - **Recording start** (key down): subtle "blip"
  - **Recording stop** (key up): softer tone
  - **Transcription complete**: optional confirmation sound
- Toggle on/off in settings (default: on)

## State Machine

```
IDLE ──(key down)──→ RECORDING ──(key up)──→ PROCESSING ──(done)──→ TYPING ──→ IDLE
  │                     │                        │                     │
  │              play start sound          play stop sound      play done sound
  │              icon → red               icon → orange         icon → gray
  │              start AVAudioEngine      stop recording        type text via CGEvent
  │                                       run whisper inference
```

**Edge cases**:
- Key released very quickly (<0.3s): discard, too short to be intentional
- App loses focus during recording: continue recording (push-to-talk is global)
- Whisper returns empty string: no-op, return to idle

## Whisper Configuration

### Model: `ggml-small.en.bin` (~466MB)

- English-only model — faster than multilingual
- Good accuracy for clear speech in quiet environments
- ~0.5-1.0s inference for a 5s audio clip with Metal acceleration
- Downloaded on first launch or bundled with app

### Developer Vocabulary Prompt

```
Technical programming discussion. Code, API, SDK, CLI, JSON, YAML, REST,
GraphQL, React, SwiftUI, TypeScript, Python, Docker, Kubernetes, Git,
GitHub, npm, async, await, middleware, endpoint, webhook, PostgreSQL,
MongoDB, Firebase, deployment, refactor, dependency, repository,
function, variable, parameter, argument, return, class, struct, enum,
protocol, interface, component, module, package, import, export.
```

This prompt is passed as `whisper_full_params.initial_prompt` to bias the model toward recognizing technical terms. User-editable in settings.

### Model Options (in settings)

| Model | Size | Speed (5s clip) | Accuracy | Use case |
|-------|------|-----------------|----------|----------|
| base.en | 142MB | ~0.3s | Good | Maximum speed |
| small.en | 466MB | ~0.7s | Better | Default — good balance |
| medium.en | 1.5GB | ~1.5s | Best | Maximum local accuracy |

## Settings (persisted via UserDefaults)

- **Hotkey**: Key combination for push-to-talk (default: right Option)
- **Model**: Whisper model selection (default: small.en)
- **Sound feedback**: On/off toggle (default: on)
- **Vocabulary prompt**: Editable text field, pre-filled with developer terms
- **Audio input**: Microphone device picker
- **Launch at login**: On/off toggle (default: off)
- **Minimum recording duration**: Threshold to discard accidental taps (default: 0.3s)

## Permissions

The app requires two macOS permissions:

1. **Microphone Access** — for audio capture. Prompted automatically by AVAudioEngine.
2. **Accessibility Access** — for global hotkey monitoring and text injection via CGEvents. Must be granted manually in System Settings > Privacy & Security > Accessibility.

First-launch flow:
1. App starts → requests Microphone permission (system dialog)
2. App detects missing Accessibility permission → shows a guide window with a button to open System Settings
3. Once both permissions are granted, app is ready

## Build System

### whisper.cpp Integration

1. Clone whisper.cpp as a git submodule
2. Build as a static library (`libwhisper.a`) with Metal support using CMake
3. Copy `whisper.h` to the Xcode project's bridging header path
4. Link `libwhisper.a`, `Accelerate.framework`, `Metal.framework`, `MetalKit.framework`
5. Copy Metal shader files (`.metallib`) to app bundle

### Xcode Project Structure

```
WhisperDictation/
├── WhisperDictation.xcodeproj
├── WhisperDictation/
│   ├── App/
│   │   ├── WhisperDictationApp.swift      # App entry point, MenuBarExtra
│   │   └── AppDelegate.swift              # Permission checks, model loading
│   ├── Engine/
│   │   ├── DictationEngine.swift          # State machine, orchestrator
│   │   ├── AudioCapture.swift             # AVAudioEngine wrapper
│   │   ├── WhisperBridge.swift            # Swift wrapper for whisper.cpp C API
│   │   ├── TextInjector.swift             # CGEvent text typing
│   │   └── SoundFeedback.swift            # Audio cue playback
│   ├── UI/
│   │   ├── MenuBarView.swift              # Menu bar icon and dropdown
│   │   └── SettingsView.swift             # Settings window
│   ├── Utilities/
│   │   ├── HotkeyMonitor.swift            # Global hotkey detection
│   │   └── PermissionManager.swift        # Permission status checking
│   ├── Resources/
│   │   ├── Sounds/                        # Audio feedback files
│   │   └── Assets.xcassets                # App icon, menu bar icons
│   └── WhisperDictation-Bridging-Header.h # C bridge to whisper.h
├── whisper.cpp/                           # Git submodule
├── Models/                                # Downloaded .bin model files
├── scripts/
│   └── build-whisper.sh                   # Script to build libwhisper.a
└── docs/
```

## Verification Plan

### Manual Testing

1. **Build**: Project compiles without errors, whisper.cpp static lib links correctly
2. **Permissions**: First launch correctly prompts for Microphone, guides to Accessibility
3. **Recording**: Hold right Option → menu bar icon turns red, start sound plays
4. **Transcription**: Release key → icon turns orange, stop sound plays, text appears at cursor
5. **Text injection**: Verified in Terminal, VS Code, Safari, and Claude Code
6. **Developer terms**: Dictate "create a REST API endpoint that returns JSON" and verify correct transcription
7. **Settings**: All settings persist across app restarts
8. **Edge cases**: Quick tap (<0.3s) is discarded, long recording (30s+) works correctly

### Performance Targets

- Model load time: <3s on app startup
- Recording start latency: <50ms from key press
- Transcription latency: <1.0s for a 5s clip (small.en + Metal)
- Text injection: <100ms after transcription completes
- Memory usage: <600MB with small.en model loaded
- CPU during idle: near zero

## Future Enhancements (not in v1)

- Post-processing text cleanup (auto-capitalize, dev term corrections)
- Cloud fallback mode (OpenAI Whisper API)
- Larger model support (medium.en, large-v3)
- Custom wake word instead of push-to-talk
- Clipboard mode (copy instead of type)
- Per-app vocabulary profiles
