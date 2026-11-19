# Implementation Plan: One microphone, one speech engine

**Branch**: `002-shared-mic` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-shared-mic/spec.md`

**Note**: Docs only. No implementation starts from this commit. The slice sits under Explain slice 001: Right Option holds to talk, and the release still processes the request.

## Summary

One owner lends the microphone to Zeus, Murmur, or Scribe, and never to two of them. One warm speech engine serves Zeus and Murmur, streams partial transcripts to the overlay, and is not rebuilt on a press. The first captured buffer is under 100 ms after a Right Option press. Murmur's Right Command hold drops six per-dictation costs, each with a before and after measurement. Scribe uses the same owner once a recording has already started. "Start automatically" and the 20 s ask timeout are not changed. A Zeus hold during a Scribe recording is mic busy: Scribe keeps recording and Zeus processes nothing.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: The existing dictation path in `Sources/Zeus/Dictation/`, the existing Scribe machine in `Sources/ZeusCore/Scribe/ScribeAutoStart.swift`, and the Explain overlay from slice 001. No new package.

**Storage**: None. The owner and the registry live in memory.

**Testing**: Swift Testing, red first. Each of the six removals records a before count and an after count. Linux can run a pure owner test. The Mac run is the gate for capture timing, accessibility, and the top bar.

**Target Platform**: macOS 14.2

**Project Type**: Native macOS app. The owner and the registry are pure enough to test without a device. Capture timestamps are Mac-only.

**Performance Goals**: First captured audio under 100 ms after a warm Right Option press. The six dictation costs go to zero. No new latency target replaces slice 001's 1.2 s, 1.0 s, and 300 ms clocks.

**Constraints**: No private APIs. No Package.swift or CI change. Top bar visuals and animations stay. Scribe does not start itself. The 45 s slow-start stays. Reduce Motion and VoiceOver cover denied, busy, and failure.

**Scale/Scope**: Three capturers, one engine, one owner.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Simplicity**: One owner, one engine, three callers. The top bar is not restyled. Pass.
- **II. Red-first tests**: tasks.md names the failing test before each removal and each rule. A missing before/after measurement stays blocked. Pass.
- **III. Clean-room**: Zeus, Murmur, and Scribe only. No third-party application name. Pass.
- **IV. Privacy by default**: Capture still needs the person's own OS consent. Tests use generated audio. Nothing is logged. Pass.
- **V. Motion and accessibility**: Reduce Motion stays a fade or an immediate change. VoiceOver hears denied, busy, and failure. Pass.

Preserved surfaces: the top bar's springs and animations stay. Per-buffer main-thread redraws are the thing this slice removes, not the visuals.

## Project Structure

### Documentation (this feature)

```text
specs/002-shared-mic/
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/ZeusCore/
└── the shared owner and registry, new, tested without AppKit

Sources/Zeus/Dictation/
└── DictationController.swift and SpeechEngines.swift, the six costs

Sources/ZeusCore/Scribe/ScribeAutoStart.swift
└── unchanged automatic mode and 20 s ask timeout

Tests/ZeusCoreTests/
├── SharedMicOwnerTests.swift
└── ScribeManualOnlyTests.swift

Tests/ZeusAppTests/
└── DictationWarmStartTests.swift
```

**Structure Decision**: Arbitration is a pure owner so the overlap tests do not need a device. The warm start and the measured costs are checked against `DictationController.begin` (lines 575–622) and `speech.onLevel`. Scribe's automatic mode and 20 s ask timeout are not edited.

## Complexity Tracking

No constitution violation needs a justification. One owner is the smaller design. A second engine or a second capture is what this slice removes.
