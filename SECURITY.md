# Security Policy

## Threat Model

WhisperDictation is a macOS dictation app that requires two sensitive permissions: **Microphone** and **Accessibility**. Because of this, we take security seriously and have designed the app to minimize attack surface.

### What the app does

| Permission | What it's used for |
|-----------|-------------------|
| Microphone | Capture audio **only** while the user holds the configured hotkey. Audio is processed in RAM (16kHz mono Float32), fed to whisper.cpp for transcription, and discarded. Never written to disk. |
| Accessibility | Detect the global hotkey via `CGEvent.tapCreate`, and inject transcribed text at the cursor via `CGEvent.keyboardSetUnicodeString`. Does not read screen contents or other keystrokes. |

### What the app does NOT do

- No audio or transcription data leaves the device. Ever.
- No telemetry, analytics, crash reporting, or any form of tracking.
- No network requests except for **user-initiated model downloads** from HuggingFace.
- No automatic updates / update server.
- No account, license check, or any "phone home" behavior.
- No clipboard access.
- No web content or external scripts (the app is 100% native Swift/SwiftUI).

## Auditability

The entire app is ~2,500 lines of Swift. You can verify every network-facing line in one command:

```bash
git clone https://github.com/sam-pop/WhisperDictation.git
cd WhisperDictation
grep -rE "URLSession|URLRequest|http://|https://|NSURLConnection|Network\.framework" WhisperDictation/**/*.swift
```

The only matches are in `WhisperDictation/Engine/ModelManager.swift` — URLs for HuggingFace model files and the `URLSession.shared.download` call that fetches them when the user clicks "Download" in Settings > Model.

We also recommend running a firewall like [Little Snitch](https://www.obdev.at/products/littlesnitch/) or [LuLu](https://objective-see.org/products/lulu.html) while testing the app. You will see zero outbound connections during normal use.

## Build from Source

Don't want to trust the pre-built DMG? Build from source:

```bash
git clone --recurse-submodules https://github.com/sam-pop/WhisperDictation.git
cd WhisperDictation
make whisper && make app
open build/WhisperDictation.app
```

The Makefile compiles directly via `xcrun swiftc` with no opaque build steps. You can read the entire pipeline in the [Makefile](Makefile).

## Dependencies

- **[whisper.cpp](https://github.com/ggerganov/whisper.cpp)** (git submodule) — C/C++ port of OpenAI Whisper. MIT licensed. Compiled as a static library, linked directly into the app. No dynamic libraries.
- **Whisper models** (downloaded on demand) — Pre-trained ML models from OpenAI, distributed via HuggingFace. MIT licensed.
- **macOS frameworks** (AVFoundation, Metal, CoreGraphics, AppKit, etc.) — First-party Apple frameworks.

No third-party Swift packages, no CocoaPods, no Carthage. The only external code is whisper.cpp and Apple's SDK.

## Code Signing

Releases are currently **ad-hoc signed** (not notarized by Apple). This means macOS Gatekeeper will show a warning on first launch. We document how to bypass this in the [install instructions](https://sam-pop.github.io/WhisperDictation/#install). Formal Developer ID notarization is planned once the project enrolls in the Apple Developer Program.

Every release DMG will include a SHA256 checksum in the release notes so you can verify integrity.

## Reporting a Vulnerability

If you discover a security issue, please **do not open a public issue**. Instead:

1. Email the maintainer directly (see [GitHub profile](https://github.com/sam-pop)), or
2. Open a [private security advisory](https://github.com/sam-pop/WhisperDictation/security/advisories/new) on GitHub

We aim to respond within 72 hours. Critical issues will be patched and disclosed on an accelerated timeline.

## Scope

In scope:
- Unintended network activity
- Privilege escalation via the Accessibility API
- Audio capture outside of the hotkey-held state
- Memory safety issues in our Swift code or bridging layer
- Supply chain concerns around whisper.cpp or model downloads

Out of scope:
- Vulnerabilities in whisper.cpp itself (please report to the [whisper.cpp project](https://github.com/ggerganov/whisper.cpp))
- Vulnerabilities in macOS or Apple frameworks
- Physical attacks requiring local user access

## Acknowledgments

Security researchers who responsibly disclose issues will be credited in release notes unless they prefer to remain anonymous.
