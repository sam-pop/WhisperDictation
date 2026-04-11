# WhisperDictation

Local, private voice-to-text for macOS. Hold a key, speak, release -- your words appear at the cursor. Powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp) running entirely on your machine.

**No cloud. No API keys. No subscriptions. No data leaves your Mac.**

## Features

- **Push-to-talk dictation** -- hold a hotkey to record, release to transcribe and type
- **Works everywhere** -- types text at the cursor in any app (Terminal, VS Code, Claude Code, browsers, Slack, etc.)
- **Fast** -- sub-second transcription on Apple Silicon via Metal GPU acceleration
- **Private** -- all processing happens locally using whisper.cpp
- **Developer-optimized** -- vocabulary prompt biases Whisper toward 400+ technical terms (API, JSON, Kubernetes, PostgreSQL, etc.)
- **Grammar correction** -- auto-capitalizes sentences, fixes acronym casing (api -> API), adds punctuation
- **Multiple models** -- choose between Base (fast), Small (balanced), or Medium (accurate)
- **Configurable hotkey** -- bind any key (default: Right Option)
- **Sound feedback** -- audio cues for recording start/stop/done
- **Menu bar app** -- lives in the menu bar with status indicator, no dock icon
- **Light & dark mode** -- follows your macOS system theme

## Quick Start

```bash
git clone --recurse-submodules https://github.com/sam-pop/WhisperDictation.git
cd WhisperDictation

# Build whisper.cpp (one-time, ~1 min)
./scripts/build-whisper.sh

# Download a model (one-time)
./scripts/download-model.sh small.en    # 466 MB, recommended
# or: ./scripts/download-model.sh base.en   # 142 MB, faster

# Build and run
make run
```

On first launch, grant **Microphone** and **Accessibility** permissions when prompted.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)
- CMake (`brew install cmake`)
- ~500 MB disk space (model + app)

## Usage

1. Look for the waveform icon in your menu bar
2. Hold **Right Option** (or your configured hotkey)
3. Speak naturally
4. Release the key -- text appears at your cursor

The menu bar icon changes to show status:
- Waveform -- ready
- Red mic -- recording
- Brain -- transcribing
- Cursor -- typing

## Models

| Model | Size | Speed | Accuracy | Best for |
|-------|------|-------|----------|----------|
| `base.en` | 142 MB | Fastest | Good | Quick notes, Intel Macs |
| `small.en` | 466 MB | Balanced | Better | Daily use (recommended) |
| `medium.en` | 1.5 GB | Slower | Best | Maximum accuracy |

Download models via the script or from the Settings > Model tab in the app.

## Grammar Correction

WhisperDictation automatically post-processes transcriptions:

- **Capitalization** -- first letter of sentences, standalone "I"
- **Acronym casing** -- api -> API, json -> JSON, aws -> AWS, graphql -> GraphQL
- **Proper nouns** -- javascript -> JavaScript, postgresql -> PostgreSQL, docker -> Docker
- **Punctuation** -- adds missing periods, removes stray spaces before punctuation

Toggle in Settings > General > "Auto-correct grammar & formatting"

## Build Commands

```bash
make whisper    # Build whisper.cpp static library
make model      # Download default model (small.en)
make app        # Compile Swift and create .app bundle
make run        # Build and launch
make clean      # Remove build artifacts
```

For Xcode development:
```bash
brew install xcodegen    # One-time
xcodegen generate        # Generate .xcodeproj from project.yml
```

## Architecture

```
HotkeyMonitor (CGEvent tap, global key monitoring)
    |
DictationEngine (state machine: idle -> recording -> processing -> typing)
    |-- AudioCapture (AVAudioEngine -> 16kHz mono Float32)
    |-- WhisperBridge (C API via bridging header -> whisper_full())
    |-- TextCorrector (rule-based grammar/casing/punctuation)
    |-- TextInjector (CGEvent keyboardSetUnicodeString)
    |-- SoundFeedback (NSSound system sounds)
```

whisper.cpp is compiled as a static library with Metal GPU acceleration and linked via a C bridging header.

## Project Structure

```
WhisperDictation/
  App/                    # SwiftUI app entry point, menu bar
  Engine/                 # Core: audio capture, whisper bridge, text injection, grammar
  UI/                     # Settings window, menu bar dropdown, onboarding
  Utilities/              # Hotkey monitor, permissions, settings persistence
whisper.cpp/              # Git submodule
scripts/                  # Build, download, packaging scripts
.github/workflows/        # CI/CD
```

## CI/CD

- **CI**: Builds on every push/PR to `main` (GitHub Actions, macOS runner)
- **Release**: Tag `v*` triggers DMG build and GitHub Release

## License

MIT License. See [LICENSE](LICENSE).

This project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (MIT License) and [Whisper models](https://github.com/openai/whisper) by OpenAI (MIT License).

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov -- the C/C++ port that makes local inference fast
- [Whisper](https://github.com/openai/whisper) by OpenAI -- the speech recognition model
- Inspired by [Willow Voice](https://www.heywillow.io/) and [WisprFlow](https://wisprflow.com/)
