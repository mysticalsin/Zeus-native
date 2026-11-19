# Implementation Plan: Hold Right Option, then act or explain

**Branch**: `001-explain-toggle` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-explain-toggle/spec.md`

**Note**: This file is the plan for a later implementation. This commit is docs only. Tony's 13:12 ruling replaces the tap-to-toggle model. No implementation starts from this commit.

## Summary

Holding Right Option alone starts an explain turn. The overlay is up while it is held and the person speaks. Releasing it is what Zeus processes. The hold does not fire when Right Option is a modifier, when another key goes down, or when a click happens, and Esc while held cancels. On release Zeus can open, close, or explain, each with matching visuals, and it can still describe the screen, point at a real control, or walk one step at a time. One click-through overlay carries the pointer and the marks, and it is torn down when the turn ends. Control-Option hold-to-talk and Right Command hold-to-dictate stay. A close that would lose unsaved work, and a click Zeus would make for the person, still use the existing approval or confirm gate.

## Technical Context

**Language/Version**: Swift 6, the language mode ZeusCore already uses

**Primary Dependencies**: The existing explanation protocol and screen geometry, the existing approval card, AppKit for one click-through overlay. No new package. The listen gesture is a hold of Right Option, not the 0.3 s tap maximum.

**Storage**: None. A turn is in memory and ends with the overlay.

**Testing**: Swift Testing. Red tests land before the behavior they name. Linux can run a pure machine test only. The Mac run is the gate for the overlay, VoiceOver, displays, and the p50 clocks.

**Target Platform**: macOS 14.2, the package's existing deployment target

**Project Type**: Native macOS app. The decision core stays in ZeusCore. The overlay stays in the app target.

**Performance Goals**: p50 on Tony's Mac, 20 timestamped turns each: first audio <= 1.2 s from release, pointer <= 1.0 s, fast action <= 300 ms. The clocks are the ones in spec.md SC-001, SC-002, and SC-003.

**Constraints**: No private APIs. No new window besides the one overlay. No microphone or screen capture without the person's own OS consent. No Package.swift, workflow, entitlement, or CI timeout change. Top bar visuals and animations stay. Reduce Motion replaces the pointer flight with a fade. The 45 s and 20 s timeouts stay.

**Scale/Scope**: One explain turn at a time. One overlay. Open, close, and explain, plus describe, point, and one walk.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Simplicity**: One hold, one overlay, one result when the key comes up. The top bar is not restyled. Pass.
- **II. Red-first tests**: tasks.md writes each failing test before the change that makes it pass. A missing Mac proof stays blocked. Pass.
- **III. Clean-room**: This spec names Zeus, Murmur, and Scribe only. Applications in tests are fixtures. It does not name another app. Pass.
- **IV. Privacy by default**: Turns are local. Tests use synthetic screens and generated audio. Capture still needs the person's own OS consent. Pass.
- **V. Motion and accessibility**: Reduce Motion fades instead of flying. VoiceOver can hear the hold, the release, and cancel, and hears mark numbers and control names. Status does not depend on color alone. Pass.

Preserved surfaces: the top bar's visuals, springs, and animations stay. Right Command's tap stays off by default. Control-Option hold-to-talk stays. Push-to-talk cue sounds stay.

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

specs/003-approval-sync/
└── README.md        # stub only, not this slice
```

`research.md`, `data-model.md`, `quickstart.md`, and `contracts/` are not part of this docs commit. The entities in spec.md are enough to start the red tests.

### Source Code (repository root)

```text
Sources/ZeusCore/
└── Explanation/                   # existing protocol and geometry; the hold decision joins it

Sources/Zeus/
├── Voice/                         # Right Option hold beside Control-Option
├── Explanation/                   # turn, overlay, pointer, marks, open and close
└── Notch/                         # existing approval card, not a new one

Tests/ZeusCoreTests/
└── ExplainToggleTests.swift       # new pure tests named in tasks.md

Tests/ZeusAppTests/
└── ExplainOverlayTests.swift      # new overlay tests named in tasks.md
```

**Structure Decision**: The hold decision lives in ZeusCore and does not need AppKit. The one overlay lives next to the existing explanation app types. Open and close call the existing application actions. Approval stays the existing card. Slice 002's shared microphone owner is not built here.

## Complexity Tracking

No constitution violation needs a justification. The overlay is the one new window the spec allows. It is up while Right Option is held and for the result, and it is torn down with the turn.
