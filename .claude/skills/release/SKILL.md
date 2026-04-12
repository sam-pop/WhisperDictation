---
name: release
description: Build DMG, tag version, and create GitHub release
disable-model-invocation: true
---

# Release WhisperDictation

Build and publish a new version. Usage: `/release v1.x.x`

## Steps

1. Run `make clean && make dmg` to build a fresh DMG
2. Verify the DMG was created at `build/WhisperDictation.dmg`
3. Stage and commit any pending changes
4. Create a git tag with the version argument
5. Push the tag to origin
6. Create a GitHub release using `gh release create` with the DMG attached
7. Include a changelog in the release notes summarizing commits since the last tag

## Release Notes Format

```
## WhisperDictation <version>

### New
- [features from commits]

### Fixed
- [fixes from commits]

### Install
1. Download **WhisperDictation.dmg** → drag to Applications
2. System Settings > Privacy & Security > **Open Anyway**
3. Grant Microphone + Accessibility
4. Settings > Model > download a model

Requires macOS 14+.
```

## Commands

```bash
make clean && make dmg
git add -A && git commit -m "v<version>: <summary>"
git tag <version> && git push origin <version>
gh release create <version> build/WhisperDictation.dmg --title "WhisperDictation <version>" --notes "<notes>"
```
