# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make whisper      # Build whisper.cpp static library with Metal (one-time, ~1 min)
make model        # Download default model from HuggingFace (one-time)
make app          # Compile Swift sources, generate icon, code sign, create .app bundle
make run          # Build + open the app
make dmg          # Build + create DMG installer
make clean        # Remove build/ directory
```

**Run tests** (requires xcodegen):
```bash
xcodegen generate && xcodebuild test -project WhisperDictation.xcodeproj -scheme WhisperDictation -destination "platform=macOS"
```

The Makefile compiles directly via `xcrun swiftc` with a bridging header — it does **not** use xcodebuild. An XcodeGen `project.yml` exists for IDE use (`xcodegen generate` to regenerate `.xcodeproj`).

**When adding new .swift files**, add them to `SWIFT_FILES` in the Makefile and add the framework to `FRAMEWORKS` if needed. There is no glob — all sources are listed explicitly.

## Architecture

**State machine** drives the app: `idle → recording → processing → typing → idle`

```
HotkeyMonitor (CGEvent tap, with watchdog timer to re-enable stale taps)
    ↓ key down/up
DictationEngine (@Observable, orchestrates everything)
    ├── AudioCapture (AVAudioEngine → AVAudioConverter → 16kHz mono Float32)
    ├── WhisperBridge (C API via bridging header → whisper_full() with VAD + beam search)
    ├── TextCorrector (rule-based grammar: 100+ dev term casing, capitalization, punctuation)
    ├── TextInjector (CGEvent keyboardSetUnicodeString)
    └── SoundFeedback (NSSound system sounds)
```

**WhisperBridge** wraps whisper.cpp's C API through `WhisperDictation-Bridging-Header.h → lib/whisper.h`. Loads model once at startup, runs inference on a dedicated dispatch queue. Marked `@unchecked Sendable` (thread safety via the queue). Uses beam search on Apple Silicon (GPU), greedy on Intel (CPU). Supports VAD (Silero model) to trim silence before inference.

**Audio format**: whisper.cpp requires 16kHz mono Float32. AudioCapture reads `inputNode.outputFormat(forBus:0)` AFTER `engine.prepare()`, passes that format to `installTap`, and converts via `AVAudioConverter` with `converter.reset()` before each callback. The converter is created upfront from the hardware format (not lazily). Do NOT use `nil` format with `installTap` — it causes the tap callback to never fire on some hardware.

**Text injection**: CGEvent with `keyboardSetUnicodeString` in 16-char UTF-16 chunks, 5ms delay. Must run off MainActor to avoid blocking UI.

## Key Patterns

- **DictationEngine** uses `@Observable` (Swift 6). Settings/ModelManager/PermissionManager use `ObservableObject` + `@Published`.
- **AppSettings** (not `Settings` — renamed to avoid SwiftUI `Settings` scene conflict) is a singleton backed by UserDefaults.
- **Settings window** uses a `Window` scene with `openWindow(id: "settings")` — `SettingsLink` and `Settings` scene don't work in `LSUIElement` menu bar apps.
- **ModelManager** stores models in `~/Library/Application Support/WhisperDictation/Models/`. Supports full precision and quantized (Q5) models, plus Silero VAD model.
- **HotkeyMonitor** uses `CGEvent.tapCreate` with `Unmanaged.passRetained`. Must store the pointer and release in `stop()`. Has a 2-second watchdog timer that re-enables the tap if macOS silently disables it (happens when binary is re-signed).
- **Version number**: `Info.plist` `CFBundleShortVersionString`. Update when releasing. Displayed in menu bar dropdown and settings sidebar via `Bundle.main.infoDictionary`.
- **TextCorrector** runs <5ms post-processing: acronym/term casing (100+ dev terms), user custom terms (cached combined regex with `cacheQueue` for thread safety), sentence capitalization, punctuation cleanup. Custom terms are stored as `[String]` in UserDefaults via `AppSettings.customTerms`.
- **C callbacks in WhisperBridge**: Use `Unmanaged.passRetained` to create a context object, pass its opaque pointer as `user_data`, and `release()` in a `defer` after `whisper_full` returns. The callback uses `takeUnretainedValue()`. Do not keep a separate local Swift reference — the Unmanaged retain handles lifetime.
- **FlowLayout** in SettingsView.swift — custom `Layout` for wrapping pill/tag UIs. Reusable for any flow-wrapped content.

## whisper.cpp Integration

- Git submodule at `whisper.cpp/`
- `scripts/build-whisper.sh` builds static libs with CMake (`GGML_METAL=ON`, `GGML_METAL_EMBED_LIBRARY=ON`)
- Output goes to `lib/`: static libraries (`.a`) + headers (`.h`)
- Linked libs: `libwhisper`, `libggml`, `libggml-base`, `libggml-cpu`, `libggml-metal`, `libggml-blas`, `libc++`
- Frameworks: Accelerate, Metal, MetalKit, AVFoundation, CoreGraphics, AppKit, ServiceManagement

## Gotchas

- **DMG packaging**: `make dmg` handles code signing, icon generation, and plist variable substitution. Info.plist uses Xcode-style `$(EXECUTABLE_NAME)` variables that the Makefile resolves via `sed` + `PlistBuddy`. App is ad-hoc signed. Users must right-click > Open Anyway on first launch.
- **App icon**: Generated at build time by `scripts/generate-icon.py` (compiles a Swift script using AppKit/CoreGraphics). Never use qlmanage for SVG-to-PNG — produces broken icons.
- **Running from DMG vs /Applications**: App must be copied to /Applications. Running from mounted DMG causes Accessibility permission issues.
- **Swift `print()` not visible in terminal**: whisper.cpp logs to stderr but Swift `print()` goes to buffered stdout. Use `fputs("...\n", stderr)` for diagnostic logs.
- **`CharacterSet.punctuation` doesn't exist** — use `.punctuationCharacters` in Swift.
- **Accessibility permission goes stale** when the binary is re-signed. `AXIsProcessTrusted()` returns true but the event tap receives zero events. User must toggle the permission off/on in System Settings. The watchdog timer detects and re-enables disabled taps.
- **`installTap` format**: Pass the hardware format from `inputNode.outputFormat(forBus:0)` read AFTER `engine.prepare()`. Do NOT pass `nil` (tap callback never fires on some hardware). Do NOT pass a custom format like 16kHz (throws uncatchable NSException). Create `AVAudioConverter` upfront and call `converter.reset()` before each conversion.
- **TextInjector.type() uses a dedicated DispatchQueue** — never call it on MainActor (Thread.sleep blocks UI) or on a Swift cooperative thread pool (starves it). It has its own serial queue internally.
- **NSSound must be called on main thread** — `SoundFeedback.playDoneSound()` etc. must be inside `MainActor.run` or dispatched to main queue.
- **Metal GPU disabled on Intel Macs** (`#if arch(arm64)`) — whisper.cpp Metal kernels are optimized for Apple Silicon, slower on AMD GPUs.
- **`xcodegen generate` overwrites Info.plist** — resets `CFBundleIconFile`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSUIElement`, etc. to defaults. Restore version numbers and `CFBundleIconFile` to `AppIcon` after running. Makefile build is unaffected.
- **Singletons need `@unchecked Sendable`** — all `ObservableObject` singletons must conform for xcodebuild compatibility (Swift 6 strict concurrency).
- **Tests must not assert hardcoded UserDefaults values** — user may have changed hotkey, model, or device. Assert ranges/invariants instead (e.g., `hotkeyKeyCode >= 0` not `== 61`).
- **Vocabulary prompt must stay under ~750 words** — Whisper's 1024 token limit. Exceeding it causes `whisper_tokenize: too many resulting tokens` and degrades accuracy. DictationEngine caps custom terms to fit within a 700-word budget. UI limits to 100 custom terms.
- **SwiftUI `foregroundStyle` ternary pitfall** — `.orange` (Color) and `.tertiary` (ShapeStyle) are different types; a ternary between them won't compile. Use `foregroundColor()` with concrete `Color` values instead.

## Permissions

The app requires **Microphone** (prompted by AVAudioEngine) and **Accessibility** (manual grant, required for CGEvent tap + text injection). `LSUIElement = true` hides the dock icon.

## CI/CD

- `.github/workflows/ci.yml`: Builds on push/PR to main (macOS 15 runner, caches `lib/`)
- `.github/workflows/release.yml`: On `v*` tag, builds DMG via `scripts/create-dmg.sh` and creates GitHub Release

### Manual Release
```bash
make dmg
git tag v1.x.x && git push origin v1.x.x
gh release create v1.x.x build/WhisperDictation.dmg --title "WhisperDictation v1.x.x" --notes "..."
```
