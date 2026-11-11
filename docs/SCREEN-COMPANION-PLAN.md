# Zeus screen-aware companion: grounded plan (2026-11-11)

Source of truth for the request "hold a shortcut, speak while pointing, get a spoken answer that draws on the
screen, shows photos, builds charts and animates 3D". Built on the code inventory of
`codex/integration-20261111` (file references below) and `docs/HEYCLICKY-REA.md`. A second teardown of the
installed HeyClicky 1.1.1 (`docs/HEYCLICKY-REA-2.md`, in progress) will refine slices S3 to S5. Everything
below that is not marked **Exists** is a proposal until it is implemented and tested.

## 1. Sequence: "Explain what this bar does" (pointing at an input bar)

```
Tony        HotkeyMonitor   PointingController   ScreenContext   Provider(LLM)   BeatScheduler   Overlay/Canvas   Speech
 | hold Ctrl+Opt  |                |                   |               |               |               |            |
 |--------------->| turn T1 begins |                   |               |               |               |            |
 |                |--------------->| marker + trail on (local, <50 ms) |               |               |            |
 | trace bar, say |   samples 30Hz | capture display under pointer (Zeus excluded)     |               |            |
 |  "explain this"|                |------------------>| image + identity + AX probe   |               |            |
 | release        |                | STT final text    |               |               |               |            |
 |--------------->|--------------->| envelope{T1, text, image, gesture summary, AX candidates, scene rev}           |
 |                |                |---------------------------------->| NDJSON beats (validated per line)            |
 |                |                |                   |               |-------------->| b1 ready: ring(targetID) + speech     |
 |                |                |                   |               |               |-------------->| ring drawn |
 |                |                |                   |               |               |------------------------------>| plays b1
 |                |                |                   |               |               | cues admitted from playback time |
 | (interrupt: press keys / Esc)                                                       |               |            |
 |--------------->| T1 cancelled: SSE task cancelled, pending beats dropped, audio stops, temporary marks cleared,  |
 |                | late callbacks with T1 ignored (generation token), scene kept for a follow-up                    |
```

## 2. Module map (existing types, new ones marked NEW)

| Responsibility (spec name) | Zeus today | Status |
|---|---|---|
| InputCoordinator | `PointingHotkeyMonitor`, `PointingEventTap` (listen-only CGEventTap, NSEvent fallback), `PointingKeyGesture`, `SharedKeyGesture`, `ShortcutConflicts` | Exists; Phase 2 adds double-Control and Fn+Control (unmerged) |
| PointerGestureRecorder | `PointingTrace` (`PointerSample`, `PointingStroke`, `PointingDwell`, bounded) | Exists; trail only on drag |
| ScreenContextService | `ExplanationScreenContext` (SCK, Zeus excluded, identity, lease) | Exists, one display per turn |
| AccessibilityContextService | `PointingTargetProbe` (AX hit test, secure labels dropped) | Exists; runs off-main (verify) |
| Coordinate transforms | `ExplanationCaptureGeometry`, `ExplanationViewportTransform`, `ScreenCoordinateMapper`, `PointingGeometry` | Exists with 12+ tests |
| ResponseDecoder | `ExplanationWire` strict NDJSON, `ExplanationLimits`, `ExplanationWireProfile` | Exists (v1 + v2 targetID) |
| SceneStore | `ExplanationSceneReducer`, `ExplanationHistoryStore` | Exists for Chat; desktop RAM only |
| OverlayWindowCoordinator | `ExplanationOverlay` (per display, non-activating, click-through) | Exists; draws capture-space only |
| DiagramRenderer | `ExplanationCanvas` layout + painter | Exists; charts lack axes |
| ThreeDRenderer | `ExplanationSceneView` (SceneKit) | Exists in Chat pane only |
| SpeechPlaybackService / BeatScheduler | `ExplanationPlayback` state machine, `PointingSession`, `PointingSpeechRouter`, word marks via ElevenLabs | Exists |
| ActionBroker | `DrivePlan.Risk`, `DriveController.approvalCard`, `TextInserter(pressReturn:false)` | Exists outside pointing; NEW bridge |
| Photos | schema only (`retrievedPhoto`) | NEW |
| Diagnostics | `ExplanationDiagnostics`, `PointingController.Metrics` | Partial; NEW trace spans |

## 3. Per subsystem: reuse, build, unknown

1. **Input.** Reuse the tap and gesture model. Build: trail while hovering (not only dragging), held keys never swallow clicks (listen-only tap, overlay stays click-through), stuck-modifier timeout, reset on sleep/wake and display change. Merge Phase 2 (double-Control text entry, Fn+Control dictation preset, conflict checks).
2. **Gesture grounding.** Reuse `PointingTrace`. Build (Phase 2, merge): stroke-to-target scoring, deixis ("this/that/here/these"), outlined-region intent (underline vs loop vs point), dwell as evidence only.
3. **Screen and AX context.** Reuse SCK capture with self-exclusion. Build: move AX probe calls to the main actor (repo rule), display-change detection mid-gesture, context revision on every target. Unknown: whether ScreenCaptureKit excludes every overlay level on macOS 26; verify on device.
4. **Transforms.** Reuse. Build: tests for a notched display and a scaled resolution.
5. **Contract.** Reuse NDJSON v2. Build v3 additively: first-class `point` cue, `pill`, `flow` path animation, `cutaway`, chart `axis` spec (domain, ticks, units), `photo` with source, `edit` ops naming target id + expected revision, `proposal` for actions. Move the SSE loop off the main actor. Keep the closed op list; never execute model code.
6. **Overlay.** Reuse panels. Build: a desktop "explanation card" panel (non-activating, placed in free space by the layout pass) that hosts the existing canvas and SceneKit view, so charts and 3D from a pointing turn render on the desktop, not only in Chat. Overlay tests (hit testing, focus kept).
7. **Charts.** Build real scales in `ExplanationCanvas`: nice-number ticks, value axis, gridlines, units, zero baseline for bars, explicit handling of zero span and non-finite values, categorical vs time axis. Pure functions in ZeusCore with tests.
8. **Beats and speech.** Reuse `ExplanationPlayback` and generation tokens. Build: desktop captions in the card, beat-level sync for system TTS (no word marks), integration with the voice branch's streaming sentences.
9. **Photos.** Build a retrieval provider (licensed image search API to be chosen and verified; key in Keychain), attribution chip, source registry, never substitute a different product, no private people, failure fallback to speech. Unknown: which provider Tony has access to.
10. **3D.** Reuse SceneKit host. Build: time-driven `flow` markers along paths, cutaway/transparency presets, world-anchored labels with screen-space deconfliction, follow-up edits by stable id, the generic EV drivetrain fixture (battery pack, inverter, motor, reduction drive, wheels; propulsion and regeneration flows). Decision: stay on SceneKit now (exists, tested); RealityKit is a later swap behind the same scene schema.
11. **Persistence.** Reuse reducer and history. Build: desktop sessions saved to history with retention controls; re-anchor or invalidate moved targets (Phase 2 detects).
12. **Actions.** Build an ActionBroker bridge from `proposal` ops to the existing approval card and DriveController; draft insertion never presses Return; secure fields refused; result-confirmed speech only.
13. **Diagnostics.** Build trace spans (key down, first mic buffer, transcript final, screenshot ready, request sent, first valid beat, first audio, first visual, cancel complete) into the `voice-latency` log line.

## 4. Slices (order of delivery)

- **S1 vertical slice (first):** merge Phase 2; hover trail; clicks never swallowed; AX probe on main; overlay tests; trace spans. Acceptance: hold Ctrl+Opt, trace an input bar, say "explain what this bar does"; the ring lands on the bar, the original app keeps focus, speech and ring start together, Esc stops everything.
- **S2 desktop card + charts:** card panel on the desktop hosting canvas; real chart scales; captions. Acceptance: "chart these numbers" gives correct axes and values with narration in sync.
- **S3 3D on desktop + EV demo:** card hosts SceneKit; flow markers; cutaway; edit ops; EV fixture. Acceptance: EV cutaway builds with speech, rotates, "show the inside / slow it down" edit the same scene.
- **S4 photos** (after provider decision) and **S5 guidance and actions** (proposals, click walkthrough waiting for the user, approvals).

## 5. Verification

Each slice: unit tests for pure logic, CI green, then the packaged-app walkthrough (`scripts/human-qa.sh`, a `pointing` journey added per slice) on Tony's Mac. Compile, unit tests and a packaged-app interaction are reported separately; none implies the others.
