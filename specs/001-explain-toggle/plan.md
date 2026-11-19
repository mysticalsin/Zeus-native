# Implementation Plan: Explain toggle, then show and point

**Branch**: `001-explain-toggle` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-explain-toggle/spec.md`

**Note**: This file is the plan for a later implementation. This commit is the spec, the plan, and the tasks only.

## Summary

A lone tap of Right Option toggles explain listening. A second tap sends, Esc cancels, and silence does not send. The sent turn either describes the screen with numbered marks, flies a drawn pointer to the real control and highlights it, or walks one step at a time. One click-through overlay carries the pointer and the marks, and it is torn down when the turn ends. Control-Option hold-to-talk and Right Command hold-to-dictate stay. A click Zeus would make for the person still uses the existing approval card.

## Technical Context

**Language/Version**: Swift 6, the language mode ZeusCore already uses

**Primary Dependencies**: The existing `VoiceKeyMachine` tap maximum (0.3 s), the existing explanation protocol and screen geometry, the existing approval card, AppKit for one click-through overlay. No new package.

**Storage**: None. A turn is in memory and ends with the overlay.

**Testing**: Swift Testing. Red tests land before the behavior they name. Linux can run a pure machine test only. The Mac run is the gate for the overlay, VoiceOver, displays, and the p50 clocks.

**Target Platform**: macOS 14.2, the package's existing deployment target

**Project Type**: Native macOS app. The decision core stays in ZeusCore. The overlay stays in the app target.

**Performance Goals**: p50 on Tony's Mac, 20 timestamped turns each: first audio <= 1.2 s, pointer <= 1.0 s, fast action <= 300 ms. The clocks are the ones in spec.md SC-001, SC-002, and SC-003.

**Constraints**: No private APIs. No new window besides the one overlay. No microphone or screen capture without the person's own OS consent. No Package.swift, workflow, entitlement, or CI timeout change. Top bar visuals and animations stay. Reduce Motion replaces the pointer flight with a fade.

**Scale/Scope**: One explain turn at a time. One overlay. Marks for the items the current answer names. Steps for one walk.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Simplicity**: One gesture, one overlay, one primary outcome per request (describe, point, or walk). The top bar is not restyled. Pass.
- **II. Red-first tests**: tasks.md writes each failing test before the change that makes it pass. A missing Mac proof stays blocked. Pass.
- **III. Clean-room**: This spec names Zeus, Murmur, and Scribe only. It does not name another app. Pass.
- **IV. Privacy by default**: Turns are local. Tests use synthetic screens and generated audio. Capture still needs the person's own OS consent. Silence does not send. Pass.
- **V. Motion and accessibility**: Reduce Motion fades instead of flying. VoiceOver can listen, send, and cancel, and hears mark numbers and control names. Status does not depend on color alone. Pass.

Preserved surfaces: the top bar's visuals, springs, and animations stay. Right Command's tap stays off by default. Push-to-talk cue sounds stay.

Quality gates for the later implementation head, not for this docs commit: hosted app and feature-map on that head, Sentinel before any capture path is called done, and a Devin review of that same SHA. This docs commit does not freeze an implementation.

## Project Structure

### Documentation (this feature)

```text
specs/001-explain-toggle/
├── spec.md
├── plan.md
└── tasks.md

specs/002-shared-mic/
└── spec.md          # stub only, not this slice
```

`research.md`, `data-model.md`, `quickstart.md`, and `contracts/` are not part of this docs commit. The entities in spec.md are enough to start the red tests.

### Source Code (repository root)

```text
Sources/ZeusCore/
├── VoiceKeyMachine.swift          # existing tap maximum, unchanged window
└── Explanation/                   # existing protocol and geometry

Sources/Zeus/
├── Voice/                         # Right Option routing beside Control-Option
├── Explanation/                   # turn, overlay, pointer, marks
└── Notch/                         # existing approval card, not a new one

Tests/ZeusCoreTests/
└── ExplainToggleTests.swift       # new pure tests named in tasks.md

Tests/ZeusAppTests/
└── ExplainOverlayTests.swift      # new overlay tests named in tasks.md
```

**Structure Decision**: Decisions that do not need AppKit live in a new ZeusCore type reached from the existing key path. The one overlay lives next to the existing explanation app types. Approval stays the existing card. Slice 002's shared microphone owner is not built here.

## Complexity Tracking

No constitution violation needs a justification. The overlay is the one new window the spec allows, and it is torn down with the turn.
