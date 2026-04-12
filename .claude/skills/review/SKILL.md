---
name: review
description: Deep codebase review for bugs, regressions, and edge cases
disable-model-invocation: true
---

# Full Codebase Review

Launch parallel review agents to find bugs, regressions, and edge cases.

## Review Agents

Launch these 3 agents in parallel using the Agent tool with `subagent_type: "feature-dev:code-reviewer"`:

### Agent 1: Engine Code
Review for memory leaks, race conditions, C API misuse, state machine bugs:
- `WhisperDictation/Engine/WhisperBridge.swift`
- `WhisperDictation/Engine/DictationEngine.swift`
- `WhisperDictation/Engine/AudioCapture.swift`
- `WhisperDictation/Engine/TextInjector.swift`
- `WhisperDictation/Engine/TextCorrector.swift`
- `WhisperDictation/Engine/ModelManager.swift`

### Agent 2: UI and Utilities
Review for retain cycles, NSEvent leaks, permission bugs, threading:
- `WhisperDictation/UI/*.swift`
- `WhisperDictation/Utilities/*.swift`
- `WhisperDictation/App/*.swift`

### Agent 3: Build System
Review for fresh-clone failures, CI correctness, missing files:
- `Makefile`
- `project.yml`
- `scripts/*.sh`
- `.github/workflows/*.yml`

## Focus Areas

Each agent should read `CLAUDE.md` first and check that code follows documented gotchas:
- installTap uses nil format
- TextInjector on dedicated queue (not MainActor or cooperative pool)
- NSSound on main thread
- Unmanaged pointer lifecycle correct
- State machine returns to .idle on all paths
- converter.reset() before each conversion

## Output

Filter to high-confidence issues only (>80%). Present a summary table with file, line, and severity.
