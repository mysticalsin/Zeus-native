# Plan: companion parity slices

This file plans later pull requests. It does not implement them. Slices land foundation first. After S1 the parallel slices touch only files they own. A slice that needs a type from another slice calls that type. It does not edit the other slice's files.

No slice edits `Package.swift`, CI, workflows, or toolchains. No slice adds a missing-proof override. Native rungs that cannot run are failed, as `e2e-proof-plan.md` says.

The orb body is not a slice. See the unfilled section in `spec.md`.

## Turn machine

One machine owns the companion turn. Pointing's existing machine (`Sources/ZeusCore/Pointing/PointingSession.swift`) stays the pointing session. The companion machine is the voice turn Tony holds. S12a is the only slice that may connect the two.

Phases: `idle`, `listening`, `transcribing`, `thinking`, `speaking`, `interrupted`, `error`.

| From | Event | To | Effects |
|---|---|---|---|
| idle | key confirmed (Right Option past its confirm, or the primary talk key) | listening | show buddy, lamp mic on, arm capture, start mic |
| idle | key tap inside the confirm | idle | none |
| idle | mouse-down while Right Option is arming | idle | none |
| listening | key up | transcribing | lamp mic off when the device closes, commit partial |
| listening | double-tap latch | listening | stay, arm the silence timer |
| listening | silence timer on a latch | transcribing | same as key up |
| listening | Escape | idle | stop mic, lamp off, hide after linger |
| listening | capture denied at start | error | speak the short line |
| transcribing | partial committed, route is instant | speaking | no brain, no capture wait |
| transcribing | partial committed, route needs a brain | thinking | send transcript, attach capture if it succeeded |
| transcribing | empty partial | idle | no request |
| transcribing | recognizer failure | error | speak the short line |
| thinking | first sentence ready | speaking | schedule that sentence, fly if a point tag is already parsed |
| thinking | brain failure, or capture was denied and the question needs the screen | error | speak the short line, do not invent a screen |
| thinking | key down | interrupted | cancel brain, cancel speech |
| speaking | playback ended and no sentence is queued | idle | lamps off, linger |
| speaking | key down | interrupted | stop speech, stop flight, stop capture |
| speaking | Escape | interrupted | same |
| interrupted | cleanup done and the key is still held | listening | start a new mic |
| interrupted | cleanup done and the key is up | idle | linger |
| error | the line has been spoken | idle | lamps off, pointer cleared |
| error | key down | listening | the line may be cut |
| any | sleep or display change during a hold | interrupted | discard capture |

Any other pair is illegal and the red test fails the build.

Poses, shared by the notch and the buddy: `listening`, `thinking` (transcribing uses thinking), `speaking`, `pointing` while a flight is active during speaking, `interrupted`, `error`, and `idle`.

## Persona protocol

S9 adds this surface and nothing draws an orb.

```swift
protocol Persona: Sendable {
    var id: String { get }
    var title: String { get }
    var usesOrb: Bool { get }
    func instructions() -> String
    func line(for situation: PersonaSituation) -> String
}
```

- `MascotPersona` is the default. It forwards to the current Ultron and Plain lines (`Sources/ZeusCore/Persona/ZeusVoiceLines.swift`). `usesOrb` is false.
- `OrbPersona` exists only as a type whose `usesOrb` is true and whose every method traps in the test as unfilled. The setting store rejects its id while `spec.md`'s orb section still contains the unfilled marker.
- Settings default is `MascotPersona`. Right Option and Right Command are unchanged.

A later study that replaces the marked section in `spec.md` may fill `OrbPersona`. Until that edit, no slice adds orb pixels, orb motion, or Jarvis lines.

## Red first

Every slice's first commit adds its tests and does not add the production type those tests call. The tests fail to compile or fail an assertion. The next commit on that slice makes them pass. A slice that lands green tests and production code in one commit has skipped the rule.

## Slices

Owners are exclusive. A file appears in one slice.

### S1. Turn machine (foundation, merges first)

- `Sources/ZeusCore/Companion/CompanionTurnMachine.swift`
- `Sources/ZeusCore/Companion/CompanionTurnPhase.swift`
- `Tests/ZeusCoreTests/CompanionTurnMachineTests.swift`

Red tests: every illegal transition, the barge-in order, error then hold, empty partial, instant route skips thinking's brain effect.

No other slice edits these files. Later slices may read them.

### S2. Latency budgets and signpost names

Parallel with S3–S11 after S1.

- `Sources/ZeusCore/Companion/CompanionLatencyBudget.swift`
- `Tests/ZeusCoreTests/CompanionLatencyBudgetTests.swift`

Red tests: the thresholds in `perf-budgets.md` are the constants, the indicator interval does not contain the mic interval, and a sample set that misses p95 fails the pure checker.

### S3. Streaming transcript

- `Sources/ZeusCore/Companion/StreamingTranscript.swift`
- `Tests/ZeusCoreTests/StreamingTranscriptTests.swift`

Red tests: partials before stop, commit of the stable partial within 150 ms of fake time, no 2.5 s wait when a partial exists.

### S4. First-audio gate

- `Sources/ZeusCore/Companion/FirstAudioGate.swift`
- `Tests/ZeusCoreTests/FirstAudioGateTests.swift`

Red tests: sentence 1 is scheduled before stream end, a front point tag is emitted before that schedule, the first PCM chunk is scheduled before the body end.

### S5. Barge-in policy

- `Sources/ZeusCore/Companion/BargeInPolicy.swift`
- `Tests/ZeusCoreTests/BargeInPolicyTests.swift`

Red tests: one key-down from speaking produces stop-speech, stop-flight, stop-capture, then listening, inside 150 ms of fake time.

### S6. Numbered marks and highlights

- `Sources/ZeusCore/Companion/NumberedMarkModel.swift`
- `Sources/Zeus/Companion/NumberedMarkPainter.swift`
- `Tests/ZeusCoreTests/NumberedMarkTests.swift`
- `Tests/ZeusAppTests/HighlightTests.swift`

Red tests: six marks in sentence order, the seventh refused, display 2 placement, a missing display dropped, a highlight rectangle excluded from the next capture set. The painter is new and does not edit `MarkOverlay.swift`.

### S7. Privacy lamps

- `Sources/ZeusCore/Companion/PrivacyLamp.swift`
- `Tests/ZeusCoreTests/PrivacyLampTests.swift`

Red tests: mic and capture lamps are independent, both end with the use, and a log-line builder rejects transcript text.

### S8. Offline core

- `Sources/ZeusCore/Companion/OfflineCorePolicy.swift`
- `Tests/ZeusCoreTests/OfflineCorePolicyTests.swift`

Red tests: dead network allows face and instant commands, forbids a brain call, and a screen question with no capture speaks the refusal.

### S9. Persona protocol

- `Sources/ZeusCore/Companion/Persona.swift`
- `Sources/ZeusCore/Companion/MascotPersona.swift`
- `Sources/ZeusCore/Companion/OrbPersona.swift`
- `Sources/Zeus/Companion/PersonaSetting.swift`
- `Tests/ZeusCoreTests/PersonaSwapTests.swift`
- `Tests/ZeusCoreTests/OrbPersonaTests.swift`

Red tests: the default id is the current mascot, the orb id is rejected while the study is unfilled, error lines stay at ten words or fewer.

### S10. Accessibility and Reduce Motion policy

- `Sources/ZeusCore/Companion/CompanionAccessibility.swift`
- `Sources/ZeusCore/Companion/ReduceMotionPolicy.swift`
- `Tests/ZeusCoreTests/CompanionAccessibilityTests.swift`
- `Tests/ZeusCoreTests/ReduceMotionPolicyTests.swift`

Red tests: each phase has one announcement, each mark has "Mark N, title", Reduce Motion returns a cut for every transition.

### S11. Fixtures and onboarding step model

- `Tests/Fixtures/Companion/` (the files named in `e2e-proof-plan.md`, generated in tests where a binary would be noise)
- `Sources/ZeusCore/Companion/CompanionOnboardingStep.swift`
- `Tests/ZeusCoreTests/CompanionOnboardingTests.swift`
- `Tests/ZeusAppTests/FramePaceTests.swift`
- `Tests/ZeusAppTests/ListeningIndicatorTests.swift`
- `Tests/ZeusAppTests/BuddyPresenceTests.swift`
- `Tests/ZeusAppTests/ScreenCapturePolicyTests.swift`
- `Tests/ZeusAppTests/MultiMonitorTests.swift`
- `Tests/ZeusAppTests/ConsentTests.swift`
- `Tests/ZeusCoreTests/CompanionMemoryTests.swift`

Red tests: the ones named on each row of `e2e-proof-plan.md` that belong to these files. Frame pace and listening indicator start red because the product has no drop counter and no key-event lamp yet. They stay red until S12 wires them. That is allowed: S11 owns the tests, S12 owns the product edits, and the tests go green only in S12's commits that touch the matching behavior. S11's commit message says which tests are expected red.

### S12. Wiring (after S1–S11, still parallel inside S12 because the files do not overlap)

These are the only slices allowed to edit existing product files.

| Slice | Owns | Wires |
|---|---|---|
| S12a | `Sources/Zeus/App/VoiceTurnController.swift` | Phase machine, first-audio gate, barge-in, capture-on-listen, instant route |
| S12b | `Sources/Zeus/Voice/SpeechInput.swift` | Stable partial commit. No other voice file. |
| S12c | `Sources/Zeus/Voice/Speaker.swift` | Cancel and first-chunk scheduling. |
| S12d | `Sources/Zeus/Overlay/BuddyController.swift`, `Sources/Zeus/Overlay/BuddyModel.swift`, `Sources/Zeus/Overlay/BuddyOverlayView.swift` | Phase poses, waveform under Reduce Motion, accessibility label. |
| S12e | `Sources/Zeus/Mac/MarkOverlay.swift` | Paint numbered marks from `NumberedMarkModel` without changing `MarkLayout.swift`. |
| S12f | `Sources/Zeus/Screen/ScreenCapture.swift` | Typed denial, own-window exclusion checksum. |
| S12g | `Sources/Zeus/Settings/GlanceSettingsPages.swift` | Persona row, disabled orb, existing shortcut refusals left intact. |
| S12h | `Sources/Zeus/Onboarding/OnboardingFlow.swift` | One hold step that calls the S11 model. |
| S12i | `Sources/Zeus/Brain/ZeusPrompt.swift` | No new product names. Point tags stay in front. Numbered-mark instructions only. |
| S12j | `qa/feature-map.json`, `qa/regressions.json` | Real test names from the slices above. No override for a missing Mac run. |

S12a is the only editor of the voice turn controller, so the other S12 slices expose functions for it to call and do not reach into it.

### S13. Sittings

No product code. A checklist copy of sittings A–D from `e2e-proof-plan.md` may be added as `specs/007-companion-parity/sittings.md` only after Tony asks for a place to write results. This plan does not add it in advance. Evidence directories stay outside the repo.

## Order

1. S1 merges.
2. S2 through S11 run in parallel.
3. S12a through S12j run in parallel.
4. Scripted UI rungs run on a Mac for the rows that require them.
5. Sittings A–D run with Tony.
6. A failed row is fixed in the slice that owns the file, then that row's rungs run again.

## Out of scope

- Filling the orb section.
- Renaming Zeus or adding a menu-bar-only mode.
- Changing Right Command away from dictation, or removing Right Option.
- Installing, signing, notarizing, or replacing the app on Tony's Mac.
- Opening his real vault, using his provider keys in a test, or sending a message to anyone.
