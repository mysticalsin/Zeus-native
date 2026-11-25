# Push-to-talk top bar and round indicator

Tony t2116u, 21 November 2026, asked for a top-bar animation while push to talk is held, and for the round listening mark as well. The ask is part of the reference-app parity scope (t2081u). Both marks are an original Zeus drawing. This spec does not name another product, and no third-party asset is copied.

## What appears

While push to talk is held, the existing notch panel shows two marks:

1. A light along the top of the bar already drawn in that panel.
2. A round orb inside the same panel, near the centre of the closed bar.

No new window is opened. The explain overlay is left alone: the notch panel already owns this area. The existing arm lights, halo, music wings, and microphone glow stay as they are. These marks are drawn beside them.

## Hold

Push to talk is a strict hold. Hold to talk, release to stop. It is never a toggle. Key handling belongs to other work and is not changed here. The indicator only reads state the app already publishes. The held flag is copied in the same call that sets it, so a short hold is not lost waiting for the avatar feed. A later tick that repeats the same flag changes nothing. The indicator reads:

- whether the talk key is held
- whether the microphone is listening
- the current level
- the capture-failure hint text, when that hint is the one already shown for a microphone that gave up

## States

`PTTIndicatorState` is one of:

| State | Meaning |
| --- | --- |
| idle | Nothing is drawn. No clock runs. |
| armed | The key is held and the microphone is not listening yet. |
| listening(level) | The microphone is listening. The level is clamped and drives the ring scale. |
| releasing | The key was released. The marks leave, then the state becomes idle. |
| error | A published capture failure. The marks are gone at once. |

A second sample that is still held does not turn listening off. Only a release, or an error, leaves listening.

## Motion

- Entry uses a spring. The spring response is 210 ms, inside 180 to 240 ms. Damping is under 1, so the spring can pass its target. The drawn opacity is clamped to the range 0 to 1.
- Exit lasts 150 ms and is linear. At 150 ms the marks are gone.
- The ring scale is `1 + 0.28 * clampedLevel`. The level is clamped to 0...1. A non-finite level becomes 0.
- Reduce Motion is an argument on every call. It has no default. The model never reads or writes the system Reduce Motion setting. With Reduce Motion the marks are static: full opacity while armed or listening, no travelling light, no pulse, and a release or an error clears in that same step. `needsClock` is false.
- A clock is needed only while an entry or an exit is still moving, and only when Reduce Motion is off. Idle and error never need a clock. After the exit duration the state is idle and the clock stops. There is no timer once idle.

## Release

The step that observes the release leaves `listening` in that same call, inside one frame. One frame later (1/60 second) the orb opacity is already below its held value. At 150 ms the state is idle, both opacities are 0, and `needsClock` is false. Nothing keeps animating after that.

## Error

An error drops the marks in the same step. Opacity and pulse are 0. `needsClock` is false. A later sample that repeats the error does not animate and does not speak again. When the failure flag clears and the key is up, the state is idle.

## Accessibility

- The step that enters listening returns `Listening` once.
- The step that leaves listening, by release or by error, returns `Stopped listening` once.
- Armed, level changes, and later samples of the same state return nothing.
- The accessibility label is `Listening` only while listening, and empty otherwise, so VoiceOver is not spoken to on every frame.
- The ring is a light colour on the black notch. Its contrast against that ground is at least 4.5 to 1.

## Placement

The orb is placed at the centre of the closed bar, 185 by 32 points, which is inside the existing panel. `opensWindow` is false. The surface is the existing notch panel.

## Mac drawing

`PTTIndicatorOverlay` paints the pure frame inside `NotchView`. That SwiftUI glue is Mac-pending: a Linux run does not build AppKit or prove the pixels. The overlay posts an announcement only when `advance` returns a phrase it has not just posted. It pauses its tick whenever `needsClock` is false.

## Out of scope

Key monitors, the talk-key machine, microphone capture, permission prompts, new windows, and changes to the package manifest.

## Tests

`Tests/ZeusCoreTests/PTTIndicatorTests.swift` is pure and runs on Linux. It covers the state transitions, Reduce Motion, the level clamp, release clearing inside one frame, no lingering clock after an error, the announcements once per transition, the entry spring, and the orb staying inside the existing panel.
