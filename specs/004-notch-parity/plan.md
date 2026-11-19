# Implementation Plan: Notch parity

**Branch**: `004-notch-parity` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-notch-parity/spec.md`

**Note**: This commit is the spec, the plan, the tasks, the checklist, and the live face script. No production code. A task is done only when `checklist.md` names the test and a real "verified on" value.

## Summary

Wave 1 puts the existing top bar on every display, keeps one controller, and closes the public gaps in shuffle, lyrics, collapse, icons, and Settings labels. Wave 2 turns on, one setting at a time and off by default, the contracts Tony released on 13:16 and 13:17. Face verification uses a protocol embedder. The selected weights are OpenCV Zoo SFace (Apache-2.0) with YuNet (MIT). They are not added in this commit. SFace was trained on celebrity datasets and needs legal sign-off.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: The files named in spec.md. Sparkle 2 is approved for R-022 only and is not added in this commit. No lyrics-timing package is added. R-012 stays a parser of times already in the file.

**Storage**: Face templates in the Keychain only, encrypted, access-controlled. No images.

**Testing**: Swift Testing, red first. Levels: unit, integration, native Mac, live service. The live face script is `qa/face-approval-live.md` and is not a result.

**Target Platform**: macOS 14.2

**Project Type**: Native macOS app

**Performance Goals**: Unchanged from the features already on main, plus the 3 s music-script timeout and the lyrics backoff. Face false-accept rate is unmeasured.

**Constraints**: No private API except the Wave 2 contracts. No new entitlement. Camera permission is the one already in the app. No Package.swift change in this commit. Top bar visuals stay. One actor for audio and commands.

**Scale/Scope**: One bar per display. One capturer of actions. Held rows visible and disabled.

## Constitution Check

- **I. Simplicity**: One row per feature, plain words, held rows say "not available yet". Pass.
- **II. Red-first**: tasks.md names the failing test. The checklist stays empty until a run. Pass.
- **III. Clean-room**: Prior-art names are in spec.md and `THIRD_PARTY_NOTICES` because the MIT, BSD, and Apache notices have to be kept. GPL, AGPL, and MPL sources are not copied. The glance notch animation is excluded. Music, Spotify, and Chromium are the apps Zeus already scripts. Pass.
- **IV. Privacy**: No image stored or logged. No password in the repo. Camera stays off until the setting is on. Pass.
- **V. Motion and accessibility**: Existing top bar motion stays. New state changes follow Reduce Motion. VoiceOver hears the face failure sentences. Pass.

## Project Structure

```text
specs/004-notch-parity/
├── spec.md
├── plan.md
├── tasks.md
└── checklist.md

qa/face-approval-live.md
```

Wave 1 code, when it starts, touches `DisplaySelection`, `NotchController`, `MusicModes` or the script runner, `LyricsBackoff`, and the Settings pages. Wave 2 code is separate commits, each behind its setting.

## Blocker

No weight file is in the repository. The selected embedder is SFace with YuNet, behind the protocol in spec.md. Both licence files were read on 19 Nov 2026 and are permissive. **Risk: high.** SFace was trained on celebrity datasets and needs legal sign-off. Do not vendor the weights before that sign-off. InsightFace weights stay out. `VNGenerateImageFeaturePrintRequest` is not the verification model. Do not report a false-accept or false-reject rate until a run on licensed or synthetic fixtures produces one.

## Complexity Tracking

Wave 2's private symbols are the exception Tony named. Each fails closed when the symbol is missing. They are not a reason to use a private API on a Wave 1 path.
