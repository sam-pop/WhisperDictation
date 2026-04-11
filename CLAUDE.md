# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make whisper      # Build whisper.cpp static library with Metal (one-time, ~1 min)
make model        # Download ggml-small.en.bin from HuggingFace (one-time, 466MB)
make app          # Compile Swift sources and create .app bundle
make run          # Build + open the app
make clean        # Remove build/ directory
```

The Makefile compiles directly via `xcrun swiftc` with a bridging header — it does **not** use xcodebuild. An XcodeGen `project.yml` exists for IDE use (`xcodegen generate` to regenerate `.xcodeproj`).

After modifying `project.yml`, run `xcodegen generate` to update the Xcode project.

## Architecture

**State machine** drives the app: `idle → recording → processing → typing → idle`

```
HotkeyMonitor (CGEvent tap)
    ↓ key down/up
DictationEngine (@Observable, orchestrates everything)
    ├── AudioCapture (AVAudioEngine → 16kHz mono Float32 buffer)
    ├── WhisperBridge (C API via bridging header → whisper_full())
    ├── TextInjector (CGEvent keyboardSetUnicodeString)
    └── SoundFeedback (NSSound system sounds)
```

**WhisperBridge** wraps whisper.cpp's C API through `WhisperDictation-Bridging-Header.h → lib/whisper.h`. It loads the model once at startup, runs inference synchronously on a dedicated dispatch queue, and is marked `@unchecked Sendable` (thread safety managed manually via the queue).

**Audio format**: whisper.cpp requires 16kHz mono Float32. AudioCapture handles sample rate conversion from the device's native rate via AVAudioConverter automatically.

**Text injection**: CGEvent with `keyboardSetUnicodeString` in 16-char UTF-16 chunks, 5ms delay between chunks. Works in any app including terminals.

## Key Patterns

- **DictationEngine** uses `@Observable` (Swift 6). Settings classes use `ObservableObject` + `@Published`.
- **AppSettings** (not `Settings` — renamed to avoid SwiftUI `Settings` scene conflict) is a singleton backed by UserDefaults with manual `objectWillChange.send()` on setters.
- **Settings window** uses a `Window` scene with `openWindow(id: "settings")` — `SettingsLink` and `Settings` scene don't work in `LSUIElement` menu bar apps.
- **ModelManager** stores models in `~/Library/Application Support/WhisperDictation/Models/`, not in the project directory.
- **HotkeyMonitor** uses `CGEvent.tapCreate` with `Unmanaged` pointer for the C callback. It consumes matched key events (returns nil) to prevent propagation.

## whisper.cpp Integration

- Git submodule at `whisper.cpp/`
- `scripts/build-whisper.sh` builds static libs with CMake (`GGML_METAL=ON`, `GGML_METAL_EMBED_LIBRARY=ON`)
- Output goes to `lib/`: static libraries (`.a`) + headers (`.h`)
- Linked libs: `libwhisper`, `libggml`, `libggml-base`, `libggml-cpu`, `libggml-metal`, `libggml-blas`, plus `libc++`
- Frameworks: Accelerate, Metal, MetalKit, AVFoundation, CoreGraphics, AppKit

## Permissions

The app requires **Microphone** (prompted by AVAudioEngine) and **Accessibility** (manual grant in System Settings, required for CGEvent tap + text injection). `LSUIElement = true` in Info.plist hides the dock icon.

## CI/CD

- `.github/workflows/ci.yml`: Builds on push/PR to main (macOS 15 runner, caches `lib/`)
- `.github/workflows/release.yml`: On `v*` tag, builds DMG via `scripts/create-dmg.sh` and creates GitHub Release
