# Zeus Pointing Assistant: Implementation Plan (v1)

Labels used throughout: **[Observed]** means behavior the owner reports seeing in HeyClicky. We have not verified it, and we know nothing about its implementation. **[Verified]** means read in this repo (file:line) or confirmed in a public source cited here. **[Rec]** means our recommendation. **[Verify]** means a fact that must be checked against current vendor docs before anyone relies on it.

This design is independent of HeyClicky. It uses no HeyClicky names, assets, prompts, voices or branding. We do not know its source, backend, models, voice provider or prompts.

---

## 1. Status table

### 1a. Reusable foundation (all [Verified] by reading the code)

| Capability | Where | Reuse decision |
|---|---|---|
| Typed scene protocol: closed operations, provenance, limits | `Sources/ZeusCore/Explanation/ExplanationProtocol.swift:70` (geometry kinds include ring, label, badge, arrow, underline, highlight, card, chart, timeline, plus 3D primitives), `:98` provenance (`proceduralIllustration/userProvided/retrievedPhoto/generatedImage`), `:190` operations, `:269` event, `:335` registry, `:366` limits | Extend to v2 as a strict superset. Do not fork it. |
| Closed-schema NDJSON decoder (duplicate keys, unknown fields and executable content rejected) | `ExplanationStream.swift:5`, model instructions `:29` | Reuse. Add the v2 allowlist branch. |
| Bounded SSE envelope, partial-chunk tolerant (a complete LF frame is required) | `ExplanationCompletionStream.swift:23,44` | Reuse unchanged. |
| Atomic reducer, projected graph, stable IDs, revisions | `ExplanationReducer.swift` | Reuse. Add `targetID` and v2 validation. |
| Cue admission from real playback (no estimated clock) | `ExplanationPlayback.swift:106-298` | Reuse as-is. This already meets the "never arbitrary sleeps" rule. |
| Image px to AppKit global conversion, plus the inverse (no clamping) | `ExplanationCoordinates.swift:32,56,65` | Canonical image/global transform for this feature. |
| Quartz/AX, screen, display, window, pixel and overlay mapper | `Sources/ZeusCore/Present/CoordinateMapper.swift:9,144,180` | Canonical AX to screen conversion. Add one bridging function and no third mapper. |
| Orchestrator: stop/cancel/freeze, backpressure (2 clips), history, diagnostics | `Sources/Zeus/Explanation/ExplanationController.swift:7,152,194,300,444,515` | Reuse. Add a desktop-turn entry point. |
| One-display SCK snapshot excluding Zeus, size bounds, stale rejection, 5 s lease | `ExplanationScreenContext.swift:77-79,111,263` | Reuse. Add "display under pointer" and an opt-in renewable lease policy. |
| Passive mouse-change observation with no AX/Input Monitoring permission | `ExplanationScreenContext.swift:284-306` | Reuse for stale detection. |
| Click-through, nonactivating per-display annotation panels | `ExplanationOverlay.swift:24-71` (`ignoresMouseEvents = true` `:57`, `canBecomeKey false` `:104`) | Reuse as the annotation renderer on the desktop. |
| Native 2D renderer and SceneKit 3D renderer driven by snapshots only | `ExplanationCanvas.swift:8,178,409`, `ExplanationSceneView.swift:13-20` | Reuse (see section 3). |
| On-device push-to-talk ASR, cache-only WhisperKit | `ExplanationMicrophone.swift:12,134` | Reuse for Phase 1. |
| System TTS to bounded PCM with measured duration | `ExplanationAudio.swift:44,51,140` | Reuse for Phase 1. |
| Audio takeover arbitration | `ExplanationAudioArbitration.swift`, `AppDelegate.swift:540,561-574` | Reuse. |
| Provider seam (replaceable adapter), Keychain credential | `ExplanationProvider.swift:27,35,43`, `AppDelegate.swift:575-577` | Reuse. Add pointing context. |
| Global key monitoring with no prompt at launch | `Voice/HotkeyMonitor.swift:20-50` (`KeyListenAccess`), `:65,108` | Reuse the monitor pattern and `ShortcutState`. |
| Chord state, spoiling, exact hold | `ZeusCore/Shortcut.swift:255-345`; `SharedKeyGesture.swift:6` | Reuse. |
| Conflict warnings (VoiceOver Ctrl+Opt, Globe/Fn listed) | `Shortcut.swift:182-232` | Extend with the pointing key and the chat hotkey. |
| Ink overlay that can capture or pass the mouse | `Mac/MarkOverlay.swift:31` `show(capturingMouse:)` | Reuse for scribbles. |
| Gesture trail and dwell | `ZeusCore/Present/SpatialTrail.swift:16-51` | Reuse. Additive changes: a cap and multiple dwells. |
| Cursor-follow spark with listen/think modes | `Overlay/BuddyController.swift:106,166,200` | Reuse as the colored listening marker. |
| AX snapshot of the focused window, secure fields redacted | `Mac/AXSnapshotter.swift:25-73` | Reuse for target candidates, with a smaller budget. |
| Guided-click session with revision barriers | `ZeusCore/Mac/Walkthrough.swift`, `ZeusCore/Present/GuidedPresent.swift`, `Mac/WalkthroughController.swift` | Reuse the session and `clickHits`. Replace its sleeps (see "must change"). |
| Action risk model, secret-word detection | `ZeusCore/Mac/DrivePlan.swift:4,83,94,111-131` | Reuse for action proposals. |
| Text insert that does not press Return by default | `Dictation/TextInserter.swift:162` | Reuse for dictation and focused-field insert. |
| TCC handler isolation fix, packaged resource fix, lint | `App/SystemAuthorization.swift`, `App/GlassTheme.swift:82` (`ZeusResources`), `qa/closed-loop/tests/test_source_lint.py` | Preserve. Extend the lint. |
| Settings declaration | `App/SettingsCatalog.swift:141-142` | Add `pointing.*` rows. |
| QA obligations | `qa/feature-map.json` F09 (`F09.explanation-*`, `F09.3`, `F09.4`), `qa/portable-core/prepare.py:32` | Add `F09.pointing-*` rows. |

### 1b. Must change

| Item | Why ([Verified]) | Change |
|---|---|---|
| `ExplanationController.canInteract` requires an open Chat conversation (`:97-100`) | A desktop turn has no Chat pane open. | Add `beginDesktopTurn(_:)`. It creates or reuses a session-scoped history linked to Chat. |
| `includeSnapshot` is a one-shot checkbox (`:27,174-175`) | A pointing turn must attach pixels without that checkbox. | Use a separate setting-level consent, `pointing.sendScreenshot`, default off. Pass it per turn. |
| Lease is 5 s and does not renew (`ExplanationScreenContext.swift:79,185-201`) | Explanations last 10 to 60 s. | Add a `LeasePolicy` parameter. Chat keeps its current default. Pointing renews every 0.25 s while identity is unchanged, up to 120 s. Any observed change invalidates. |
| Provider SSE loop iterates bytes on MainActor (`ExplanationProvider.swift:26,128-137`) | Main-thread cost and jank during streaming. | Move the byte and line loop into a `nonisolated` reader that delivers events through a one-slot `AsyncThrowingStream`, so backpressure is kept. |
| `AXSnapshotter.capture` runs synchronously on main with a 0.3 s budget (`:25`) | Would stall the marker animation. | Phase 1: pointed-element hit test with `AXUIElementCopyElementAtPosition`, a 0.1 s messaging timeout and a 50 ms budget. Thread choice: see section 2.4. |
| `WalkthroughController` advances on `Task.sleep` (400 ms, and `4 + chars/15` s) | Violates the "no arbitrary sleeps" rule. | The new guidance path advances on the real click, an AX/settle signal (with a bounded timeout labelled as a timeout), recapture, and real playback finish. |
| `ScreenCapture.globalPoint` clamps (`Screen/ScreenCapture.swift:48-62`), and `captureAll` grabs every display (`:9`), including from `VoiceTurnController.swift:158` | Clamping misplaces marks off-crop. Capturing all displays is broader than "at the interaction only". | The pointing path uses only `ExplanationCaptureGeometry` and captures only the display under the pointer. The existing talk path is untouched. |
| `SpatialTrail.raw` grows without bound (`:38`) and holds one dwell (`:28`) | Long holds use unbounded memory. Several dwells are needed. | Add a 4,096-sample cap and `dwells: [TrailSample]`. Existing tests unchanged. |
| `SpeechDrawingTimeline.estimate` (word-count clock, `SpeechTimeline.swift:62`) | Forbidden for this feature. | Do not call it from `Sources/Zeus/Pointing`. Enforce with the lint. |

### 1c. New

`Sources/ZeusCore/Pointing/*` (pure state machine, gesture, trace, context, proposals, v2 validation); `Sources/Zeus/Pointing/*` (controller, key monitor, target probe, marker, guidance and action tools); protocol v2; settings rows; tests; feature-map rows. Details in section 6.

### 1d. Unknown about HeyClicky (do not claim)

Source code, backend, LLM(s), ASR/TTS vendors, prompts, protocol, overlay technology, permission set, how it detects stale UI, retention policy, assets, pricing. **[Observed]** only: hold Control+Option to speak, double-tap Control for text entry, Fn+Control for dictation, a colored cursor marker while listening, pointing and scribbling while speaking, spoken answers with on-screen annotations. Nothing in this plan depends on how HeyClicky does any of this.

---

## 2. Architecture

### 2.1 Components

```
ZeusCore (pure, portable, unit-tested)
  Pointing/PointingKeyGesture      chord hold / spoil / double-tap Control
  Pointing/PointingSession         lifecycle state machine + generation tokens
  Pointing/PointingTrace           bounded samples, strokes, dwells, word-time alignment
  Pointing/PointingContext         Sendable request block: display, bounds, candidates, app/window
  Pointing/PointingProposal        typed proposals + allowlist validation + risk (reuses DrivePlan.Risk)
  Explanation/* (v2 additions)     targetID, proposals, claims, flow geometry

Zeus app (MainActor unless noted)
  Pointing/PointingController      orchestrates; owns a PointingSession; drives ExplanationController
  Pointing/PointingHotkeyMonitor   NSEvent global+local monitors -> PointingKeyGesture
  Pointing/PointingInputCapture    pointer monitor during hold, MarkOverlay ink when drawing
  Pointing/PointingTargetProbe     AX hit test -> PointingTargetCandidate (Sendable), bounded
  Pointing/PointingGuidance        await real click on target, settle, recapture, continue
  Pointing/PointingActionTools     open app, open URL, clipboard, focused-field insert; indicator + cancel
  Pointing/PointingTextEntry       small key-capable nonactivating panel (double Control)
  Reused: BuddyController (marker), MarkOverlay (ink), ExplanationScreenContext (capture/lease),
          ExplanationOverlay (annotations), ExplanationController (stream/playback/history),
          ExplanationMicrophone, SystemExplanationSpeechOutput, ExplanationHTTPProvider, TextInserter
```

### 2.2 Event flow

```
key-down (Ctrl+Opt held, exact)                     [main, NSEvent monitor -> assumeIsolated]
  ├─ PointingSession: idle -> listening(gen G)
  ├─ ExplanationAudioArbitration.yieldToNewCapture(); ExplanationController.stop()   (barge-in)
  ├─ Buddy.listen() marker (Reduce Motion: static ring, no spring)       target: next display frame
  ├─ ExplanationMicrophone.start(.appleOnDevice)  -> audio hostTime T0 recorded
  ├─ PointingInputCapture: mouseMoved global monitor (no permission) + MarkOverlay(capturingMouse:true)
  └─ ScreenContext.captureDisplay(containing: mouseLocation)  async SCK, own app excluded
       + PointingTargetProbe.hitTest(mouseLocation) -> candidate t0       (parallel, bounded)
while held:
  samples (NSEvent.timestamp, AppKit global pt, displayID) -> PointingTrace (cap 4096)
  mouse drag on overlay -> stroke -> state drawing; dwell >= 350 ms within 12 pt -> dwell + probe
  another key joins (e.g. Space for Chat Ctrl+Opt+Space) -> cancelled: discard audio, hide, no request
key-up
  ├─ mic.finish() -> transcript + SFTranscriptionSegment timings (relative to T0)
  ├─ if change observed during hold -> recapture once; else keep key-down capture
  ├─ resolve deixis: words "this/that/here/these" -> pointer sample at T0 + word time -> candidate
  ├─ build PointingContext (image px for all geometry, via ExplanationCaptureGeometry.imagePoint)
  └─ ExplanationController.beginDesktopTurn(prompt, context, snapshot?)   -> processing
provider stream (nonisolated SSE reader -> 1-slot stream -> main)
  -> ExplanationWire.decode (v2) -> reducer (projected) -> TTS render (<= 2 clips) -> player
playback observation (real media position)
  -> ExplanationPlayback admits cues -> presentation.sample -> ExplanationOverlay.present
     (capture-space objects only; lease recheck each frame; stale -> hide)
proposals
  guidance: ring target, state guiding, wait for real click inside target -> settle -> recapture -> next turn
  action:   confirmation card (risk >= risky, or always for send/delete/purchase/publish) -> tool -> indicator
key-down again / Esc / Stop menu -> interrupted -> ExplanationController.stop() (freezes admitted pose)
```

### 2.3 State machine (`PointingSession`, ZeusCore)

```
states: idle, listening, drawing, processing, speaking, guiding*, interrupted, cancelled, failed
(*guiding is an added sub-state of speaking for the guided-click wait; owner may fold it into speaking)

idle        --keyDown--------------------------> listening
listening   --mouseDown(on overlay)------------> drawing      --mouseUp--> listening
listening|drawing --chordSpoiled|Esc|emptyText-> cancelled
listening|drawing --keyUp(text)----------------> processing
processing  --firstPlaybackStart---------------> speaking
speaking    --buffering-------------------------> processing (no UI flicker; phase only)
speaking    --guidanceProposal admitted--------> guiding
guiding     --clickInTarget -> settled+recaptured -> processing (follow-up turn, same session)
processing|speaking|guiding --keyDown----------> interrupted -> listening (barge-in)
processing|speaking|guiding --Esc/Stop---------> interrupted -> idle
any         --permissionLost|providerError|invalidStream -> failed -> idle (visible reason)
cancelled|failed|interrupted -> idle after cleanup; each transition bumps generation; late callbacks
carrying an old generation are dropped (same pattern as ExplanationController.generation).
```

`ExplanationController.Phase` (`:9`) stays as it is. `PointingSession` maps onto it and owns only the pointing-specific states.

### 2.4 Thread and actor boundaries

| Work | Isolation | Rule |
|---|---|---|
| NSEvent global/local monitors | Delivered on main. Use `MainActor.assumeIsolated` (existing pattern in `HotkeyMonitor.swift:108`). | Handlers copy `timestamp`, `locationInWindow`/`mouseLocation` and `keyCode` only. |
| Controllers, overlays, session | `@MainActor` | Same as today. |
| Mic tap, TTS buffer callbacks | Audio render threads | `@Sendable` nonisolated closures that only write lock-protected buffers. Never written as a closure literal inside a `@MainActor` type (the class of crash (a)). |
| TCC requests | `SystemAuthorization` nonisolated helpers only | Lint extended (section 7). Mic uses the existing `await AVCaptureDevice.requestAccess`. |
| SSE byte loop | `nonisolated` async function | Yields `ExplanationEvent` into `AsyncThrowingStream(bufferingPolicy: .bufferingOldest(1))`. |
| AX hit test | **[Rec]** `nonisolated` function in a detached task. It returns a Sendable `PointingTargetCandidate`, and no `AXUIElement` crosses actors. | **[Verify]** that AX client calls are safe off the main thread for the target apps. Fallback: main thread with `AXUIElementSetMessagingTimeout(…, 0.1)` and a 50 ms budget. |
| ScreenCaptureKit | async API | Already used safely (`ExplanationScreenContext.swift:263`). |
| CGEventTap (not in Phase 1) | Callback on a dedicated run-loop thread | Writes a lock-protected ring only, then hops to main. |

### 2.5 Key API choice (exact native APIs)

- **[Rec] Keep `NSEvent.addGlobalMonitorForEvents` and `addLocalMonitorForEvents`** for `.flagsChanged/.keyDown/.keyUp`. This is what `HotkeyMonitor` already does. Global *key* monitoring requires Accessibility trust or Input Monitoring; Zeus already gates it with `KeyListenAccess.granted` (`HotkeyMonitor.swift:20-23`) and never prompts at launch. Monitors are listen-only and cannot swallow events. Modifier chords and double-Control do not need swallowing.
- **Mouse** global monitors (`.mouseMoved`, `.leftMouseDragged`, `.scrollWheel`) need no AX or Input Monitoring permission. This repo already depends on that ([Verified] comment and usage at `ExplanationScreenContext.swift:285-290`; **[Verify]** against Apple's `addGlobalMonitorForEvents` doc).
- **`CGEvent.tapCreate`**: `.listenOnly` needs Input Monitoring (`CGPreflightListenEventAccess`/`CGRequestListenEventAccess`). An active `.defaultTap` that can modify or drop events needs Accessibility. **[Rec]** Use it only if measurement shows dropped or late monitor events. `NSEvent.timestamp` stays accurate even when delivery is late, so trace timing is not affected by main-thread delay.
- Permission checks: `AXIsProcessTrusted()`, `CGPreflightListenEventAccess()`, `CGPreflightScreenCaptureAccess()`. No scripted prompts (AGENTS.md).

**Defaults and conflicts ([Verified] in repo unless marked):**
- Talk default is Option+Command. The original Control+Option default was deliberately migrated away (`Shortcut.swift:153-164`). Dictation defaults to Right Command (`:168`). The Chat hotkey defaults to Control+Option+Space (`ChatHotkey.swift:13`). Show-me uses a left-Command hold (`AnnotationController.swift:4-12`). Control+Option is VoiceOver's modifier and is already blocked when VoiceOver is on (`HotkeyMonitor.swift:197,211`).
- **[Rec]** Make the pointing key configurable (`pointing.shortcut`). Offer Control+Option as the [Observed] preset, and make it the default only when VoiceOver is off; otherwise use the existing "record another shortcut" flow. Start listening on key-down immediately. If any key joins the chord (`ShortcutState.isHeld(exact:)` returns false, `Shortcut.swift:324-336`), the turn is **cancelled with no request and the audio discarded**. That keeps Ctrl+Opt+Space (Chat) and other Ctrl+Opt shortcuts working.
- Double Control (text entry): **[Verify]** macOS offers "Press Control key twice" as a Dictation shortcut option in System Settings > Keyboard. Detect and warn.
- Fn+Control (dictation): this is a preset for the *existing* dictation key, not a new dictation system. Fn is the Globe key (`Shortcut.swift:203`). **[Verify]** current Globe+Control system bindings on macOS 15 and 26.
- **[Rec]** Pointing and show-me must never arm at the same time (shared arbitration flag).

### 2.6 Data contracts (Swift, ZeusCore, all `Sendable`)

```swift
public struct PointerSample: Equatable, Sendable, Codable {
    public var time: Double            // NSEvent.timestamp (seconds since boot, same clock as systemUptime)
    public var global: ExplanationVector3   // AppKit global points, z = 0
    public var displayID: UInt32
    public var buttons: UInt8          // 0 = hover, 1 = drawing stroke
}
public struct PointingStroke: Equatable, Sendable, Codable { public var id: String; public var samples: [PointerSample] }
public struct PointingDwell: Equatable, Sendable, Codable { public var at: PointerSample; public var duration: Double; public var candidateID: String? }

public struct PointingTrace: Equatable, Sendable {
    public static let maxSamples = 4096, maxStrokes = 32, maxDwells = 16
    public private(set) var samples: [PointerSample]; public private(set) var strokes: [PointingStroke]
    public private(set) var dwells: [PointingDwell]
    public mutating func add(_ s: PointerSample)          // drops oldest beyond cap, records truncation
    public func sample(atAudioOffset t: Double, audioStart: Double) -> PointerSample?
}

public struct PointingTargetCandidate: Equatable, Sendable, Codable {
    public var id: String                     // "t0".."t15", app-issued
    public var role: String; public var subrole: String?; public var label: String?  // AX, truncated 128 B
    public var imageRect: ExplanationRect     // delivered-image pixels; app-computed, never model-supplied
    public var isSecure: Bool                 // AXSecureTextField -> never act, never echo value
    public var source: Source                 // .axHitTest, .axDwell, .strokeBounds, .pointerOnly
    public enum Source: String, Codable, Sendable { case axHitTest, axDwell, strokeBounds, pointerOnly }
}

public struct PointingContext: Equatable, Sendable, Codable {
    public var version = 1
    public var captureID: UUID?               // nil if no Screen Recording / consent off
    public var imageSize: ExplanationSize2?
    public var frontmostBundleID: String?; public var windowTitle: String?   // untrusted data
    public var pointerImagePath: [ExplanationVector3]   // downsampled <= 256, image px
    public var strokes: [[ExplanationVector3]]          // image px, <= 8 x 256
    public var dwellImagePoints: [ExplanationVector3]
    public var deixis: [Deixis]               // word -> candidate, from real ASR segment timing
    public var candidates: [PointingTargetCandidate]    // <= 16
    public struct Deixis: Equatable, Sendable, Codable { public var word: String; public var candidateID: String? }
}

public struct PointingProposal: Equatable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable { case guidance, action }
    public enum Tool: String, Codable, Sendable {
        case awaitClick, awaitScroll                          // guidance
        case openApp, openURL, clipboardWrite, insertText     // action (allowlist)
    }
    public var id: String; public var kind: Kind; public var tool: Tool
    public var targetID: String?; public var arguments: [String: String]  // closed per-tool keys
    public var summary: String                                 // <= 200 B, shown on confirmation card
}
```

Rules ([Rec]): geometry in the model's world is always image px tied to `captureID`. AppKit conversion happens only in the app, through `ExplanationCaptureGeometry.globalPoint/imagePoint` (`ExplanationCoordinates.swift:56,65`). AX frames arrive in Quartz global space (`CoordinateMapper.swift:13-15`), so they go `.ax -> .screen` through `ScreenCoordinateMapper.convert` and then to image px. The flip uses the primary display height (`NSScreen.screens[0]`). The comment in `CaretLocator` (`CursorPresenceController.swift:146-150`) calls this flip approximate on secondary displays; **[Rec]** confirm with a test against `CGDisplayBounds` that it is exact for every display.

### 2.7 JSON scene protocol v2 (strict superset of v1)

v1 events stay valid for Chat. v2 is accepted only when the app requested it (pointing turns). It is decoded by the same closed-schema scanner with these additions:
- `version: 2`
- optional `proposals` (at most 2 per event, at most 4 per turn)
- optional `claims` (at most 8 per event)
- object field `targetID` (references an app-issued candidate; the app supplies the rect)
- geometry kinds `flow` (directional energy/data flow along `points`, `direction: forward|reverse|both`) and `equation` (plain text, monospaced, no TeX engine)

Annotation conditions: a capture-space annotation that has neither `targetID` nor a point inside a candidate rect or within 48 px of a dwell is **dropped before render**. It is counted in diagnostics and a caption notes "not grounded". The speech is unchanged.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "zeus:explanation-event:v2",
  "type": "object", "additionalProperties": false,
  "required": ["version","sessionID","turnID","sceneID","sequence","baseRevision","revision","beatID","speech","cues","isFinal"],
  "properties": {
    "version": {"const": 2},
    "sessionID": {"type":"string","format":"uuid"}, "turnID": {"type":"string","format":"uuid"},
    "sceneID": {"type":"string","format":"uuid"},
    "sequence": {"type":"integer","minimum":0,"maximum":63},
    "baseRevision": {"type":"integer","minimum":0}, "revision": {"type":"integer","minimum":1},
    "beatID": {"$ref":"#/$defs/id"},
    "speech": {"type":"object","additionalProperties":false,"required":["chunkID","text"],
      "properties":{"chunkID":{"$ref":"#/$defs/id"},"text":{"type":"string","maxLength":1600}}},
    "cues": {"type":"array","maxItems":16,"items":{"type":"object","additionalProperties":false,
      "required":["id","anchor","operations"],
      "properties":{"id":{"$ref":"#/$defs/id"},
        "anchor":{"type":"object","additionalProperties":false,"required":["kind"],
          "properties":{"kind":{"enum":["start","end","word"]},"wordIndex":{"type":"integer","minimum":0}}},
        "operations":{"type":"array","maxItems":128,"items":{"$ref":"#/$defs/operation"}}}}},
    "proposals": {"type":"array","maxItems":2,"items":{"$ref":"#/$defs/proposal"}},
    "claims": {"type":"array","maxItems":8,"items":{"type":"object","additionalProperties":false,
      "required":["id","scope","text"],
      "properties":{"id":{"$ref":"#/$defs/id"},"scope":{"enum":["generic","brandSpecific"]},
        "text":{"type":"string","maxLength":280},
        "sourceIDs":{"type":"array","maxItems":4,"items":{"$ref":"#/$defs/id"}}},
      "if":{"properties":{"scope":{"const":"brandSpecific"}}},
      "then":{"required":["sourceIDs"],"properties":{"sourceIDs":{"minItems":1}}}}},
    "isFinal": {"type":"boolean"}
  },
  "$defs": {
    "id": {"type":"string","pattern":"^[A-Za-z0-9_-]{1,64}$"},
    "operation": {"description":"v1 closed operations (create, update, remove, move, recolor, highlight, group, label, connect, camera, animate, clear) exactly as ExplanationOperation; objects may add targetID (pattern ^t[0-9]{1,2}$) and geometry.kind may add flow|equation"},
    "proposal": {"type":"object","additionalProperties":false,"required":["id","kind","tool","summary"],
      "properties":{"id":{"$ref":"#/$defs/id"},"kind":{"enum":["guidance","action"]},
        "tool":{"enum":["awaitClick","awaitScroll","openApp","openURL","clipboardWrite","insertText"]},
        "targetID":{"type":"string","pattern":"^t[0-9]{1,2}$"},
        "arguments":{"type":"object","additionalProperties":false,
          "properties":{"bundleID":{"type":"string","maxLength":255},"url":{"type":"string","maxLength":2048},
                        "text":{"type":"string","maxLength":2000}}},
        "summary":{"type":"string","maxLength":200}}}
  }
}
```

The JSON Schema is documentation and a portable test fixture. The authoritative validator remains the Swift scanner plus reducer (`ExplanationStream.swift`, `ExplanationReducer.swift`), which also enforces per-tool argument keys, the `kind`/`tool` pairing, revisions and limits.

**Example response** (NDJSON, two beats). Scenario: the user points at Preview's Share button and asks "how do I send this as a PDF?". Candidate `t0` is the AX button "Share" supplied by the app.

```json
{"version":2,"sessionID":"6F1C2B9E-3A51-4C0D-9B7E-2D5F8A1C4E90","turnID":"0B7D4E21-8C3F-4A6B-B2E9-71F0C5D3A812","sceneID":"C4A9E7F2-15D8-4B63-9E0A-3F82B6D1C057","sequence":0,"baseRevision":4,"revision":5,"beatID":"b0","speech":{"chunkID":"b0-s","text":"That button is Share. It sends the document as it is, not as a PDF."},"cues":[{"id":"c0","anchor":{"kind":"start"},"operations":[{"op":"create","object":{"id":"ring-share","space":"capture","captureID":"9D3E5A17-6B2C-4F81-A0D4-E7C29B58F316","targetID":"t0","geometry":{"kind":"ring","radius":22},"style":{"fill":"clear","stroke":"orange","lineWidth":3,"opacity":1,"dashed":false,"material":"matte"},"accessibleDescription":"Ring around the Share button"}}]},{"id":"c1","anchor":{"kind":"end"},"operations":[{"op":"create","object":{"id":"label-share","space":"capture","captureID":"9D3E5A17-6B2C-4F81-A0D4-E7C29B58F316","targetID":"t0","geometry":{"kind":"label"},"text":"Share (not PDF)","accessibleDescription":"Label: Share, not PDF export"}}]}],"isFinal":false}
{"version":2,"sessionID":"6F1C2B9E-3A51-4C0D-9B7E-2D5F8A1C4E90","turnID":"0B7D4E21-8C3F-4A6B-B2E9-71F0C5D3A812","sceneID":"C4A9E7F2-15D8-4B63-9E0A-3F82B6D1C057","sequence":1,"baseRevision":5,"revision":6,"beatID":"b1","speech":{"chunkID":"b1-s","text":"Open the File menu, then choose Export as PDF. Click File now and I will continue."},"cues":[{"id":"c2","anchor":{"kind":"start"},"operations":[{"op":"recolor","id":"ring-share","color":"secondary"},{"op":"create","object":{"id":"ring-file","space":"capture","captureID":"9D3E5A17-6B2C-4F81-A0D4-E7C29B58F316","targetID":"t3","geometry":{"kind":"ring","radius":18},"style":{"fill":"clear","stroke":"green","lineWidth":3,"opacity":1,"dashed":true,"material":"matte"},"accessibleDescription":"Dashed ring around the File menu: click here"}},{"op":"create","object":{"id":"badge-1","space":"capture","captureID":"9D3E5A17-6B2C-4F81-A0D4-E7C29B58F316","targetID":"t3","geometry":{"kind":"badge","radius":10},"text":"1","accessibleDescription":"Step 1"}}]}],"proposals":[{"id":"p0","kind":"guidance","tool":"awaitClick","targetID":"t3","summary":"Wait for your click on File"},{"id":"p1","kind":"action","tool":"clipboardWrite","arguments":{"text":"Quarterly-report.pdf"},"summary":"Copy a suggested file name to the clipboard (asks first)"}],"isFinal":true}
```

The app ignores any model geometry for objects with `targetID` and uses the candidate's `imageRect`. `p1` always shows a confirmation card (`DrivePlan.Risk` puts `writeClipboard` above safe, `DrivePlan.swift:131`).

---

## 3. Renderer and 3D decision

**[Rec] Native SwiftUI/AppKit for 2D, keeping the existing `ExplanationCanvasLayout`/`ExplanationCanvasPainter` path, with SceneKit for 3D in Phases 1 to 4 behind a renderer seam. No WKWebView/Three.js.**

Justification, grounded in the code:
1. The existing renderers already consume validated presentation snapshots and have no autonomous clock (`ExplanationSceneView.swift:13-14`, `docs/VISUAL-EXPLANATIONS.md`). That is exactly the A/V-sync property the spec requires. They are bound to native tests (`F09.ExplanationRendererTests`, 12 cases).
2. The desktop overlay already reuses the same layout for capture-space marks (`ExplanationOverlay.swift:36-43`), so one projection serves hit testing and drawing.
3. A WKWebView adds a JS engine, CSP, an asset/IPC bridge and a second memory pool. It also weakens the "data only, never scripts" boundary that the wire decoder enforces (`ExplanationStream.swift:29-45`). Bundling Three.js would need licensing notices and an IPC schema, while giving no capability that SceneKit primitives lack for this demo.
4. **SceneKit status [Verified via secondary sources]:** at WWDC25 Apple soft-deprecated SceneKit. It is in maintenance mode with critical fixes only, existing apps keep working, no removal date has been given, and migration to RealityKit is encouraged ([WWDC25 session 288](https://developer.apple.com/videos/play/wwdc2025/288/), [Apple migration guide](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit.md), [summary](https://dev.to/arshtechpro/wwdc-2025-scenekit-deprecation-and-realitykit-migration-a-comprehensive-guide-for-ios-developers-o26)). **[Verify]** whether SwiftUI `RealityView` on macOS requires macOS 15. Zeus's floor is macOS 14.2 (`Package.swift:6`).
5. **[Rec]** Add an `ExplanationWorldRendering` protocol now, keep `ExplanationSceneView` as the SceneKit implementation, and schedule a RealityKit implementation (Phase 6) when the floor moves to macOS 15 or later. The protocol data (primitives, groups, materials, camera, animation) is renderer-neutral, so no wire change is needed.

Additions to the 3D renderer:
- `flow` geometry: dash-phase motion along a tube or path, driven only by `presentation.sample(at:)` time. Under Reduce Motion it becomes static arrowheads.
- Cutaway: an app-owned preset sets the housing to `glass` material at 0.25 opacity and enables double-sided rendering. No model-supplied shaders.
- Labels: billboarded `label` children, as today.

Images: keep the `retrievedPhoto` vs `generatedImage` provenance distinction (`ExplanationProtocol.swift:98`). Add a visible provenance chip ("Photo: source X" vs "Generated illustration"). Approved IDs come only from an app registry (`:335`). No photo or generation service is attached until the owner picks one.

---

## 4. Voice provider evaluation

Every latency, price and capability figure below is **[Verify] against current docs** unless it is marked as already in the repo. No figures were fetched.

### ASR

| Provider | In repo? | Streaming partials / word times | Privacy | macOS fit | Check |
|---|---|---|---|---|---|
| Apple `SFSpeechRecognizer`, `requiresOnDeviceRecognition` | Yes (`ExplanationMicrophone`, `SpeechInput`) | Partials yes. `SFTranscriptionSegment.timestamp/duration` per segment. | On-device, free | Native, existing permissions | https://developer.apple.com/documentation/speech/sfspeechrecognizer |
| Apple `SpeechAnalyzer`/`SpeechTranscriber` | No | [Verify] streaming with timing; macOS 26 only | On-device | Needs a macOS 26 runtime check | https://developer.apple.com/documentation/speech/speechanalyzer |
| WhisperKit (local) | Yes (`WhisperKitEngine`) | Chunked, not true streaming in the current integration | On-device | Model must already be loaded (cache-only rule) | https://github.com/argmaxinc/argmax-oss-swift |
| FluidAudio Parakeet (local) | Yes (dependency) | [Verify] streaming support in 0.18 | On-device | ANE | https://github.com/FluidInference/FluidAudio |
| ElevenLabs Scribe realtime | Yes (`ZeusCore/Dictation/CloudTranscription.swift:142-150`) | [Verify] partials and word timestamps | Cloud, key in Keychain | WebSocket | https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime |
| OpenAI realtime transcription | Partial (batch `OpenAITranscription`, `:87-91`) | [Verify] | Cloud | WebSocket | https://platform.openai.com/docs/guides/realtime-transcription |
| Deepgram / AssemblyAI streaming | No | [Verify] | Cloud | New adapter and key | https://developers.deepgram.com/docs/live-streaming-audio , https://www.assemblyai.com/docs/speech-to-text/universal-streaming |

**Default:** Apple on-device. It already exists, needs no key, is private and provides segment timing for deixis. **Alternative:** ElevenLabs Scribe realtime, which already exists in the repo.

### TTS

| Provider | In repo? | Streaming | Word/char timing | Barge-in | Check |
|---|---|---|---|---|---|
| `AVSpeechSynthesizer.write` to PCM (installed voices) | Yes (`ExplanationAudio.swift:140`) | Per beat | Currently none ("no verified word alignment", VISUAL-EXPLANATIONS.md). **[Verify]** `write(_:toBufferCallback:toMarkerCallback:)` provides `AVSpeechSynthesisMarker` word ranges, and its OS availability. | Yes, owned player `stopAll` | https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:tomarkercallback:) |
| ElevenLabs streaming (`eleven_flash_v2_5`) | Yes (`Voice/ElevenLabsVoice.swift:11,117`) | Yes | [Verify] `/stream/with-timestamps` and WebSocket alignment | Yes | https://elevenlabs.io/docs/api-reference/text-to-speech/stream-with-timestamps |
| OpenAI TTS (`tts-1` default) | Yes (`Voice/OpenAITTSVoice.swift:9`) | [Verify] | [Verify] likely none | Yes | https://platform.openai.com/docs/guides/text-to-speech |
| Kokoro local worker | Yes (`KokoroWorker*`) | Per utterance | No | Yes | repo `KokoroWorkerSession.swift` |
| Cartesia Sonic | No | [Verify] | [Verify] word timestamps | Yes | https://docs.cartesia.ai |

**Default:** installed system voice. It already exists and is offline. Phase 2 adds marker-callback alignment if that is verified. **Alternative:** ElevenLabs streaming with timestamps (adapter exists; add timestamp parsing into `ExplanationAlignmentMark`, `ExplanationProtocol.swift:308`).

### Reasoning (vision, streaming)

The existing seam is the "Any LLM" OpenAI-compatible endpoint (`ExplanationProvider.swift:35-111`). It needs streamed chat completions with `image_url`. **[Rec]** Keep it as the default. Add native adapters behind `ExplanationModelProviding` only on the owner's decision (section 8). Model choice and pricing: [Verify] with each vendor.

### Audio handling rules ([Rec])
- Half duplex: key-down stops TTS first, so no echo cancellation is needed for push-to-talk. Hands-free barge-in later requires `AVAudioEngine.inputNode.setVoiceProcessingEnabled(true)` ([Verify]).
- Output-device change: observe `AVAudioEngineConfigurationChange` or the Core Audio default-device change, stop the current beat, rebuild the player, and resume from the beat start. This is never a silent clock.
- Formats: keep the existing PCM conversion (`AudioSamplesConversionTests`).
- Cancellation goes through `ExplanationController.stop()` (`:300-345`), which already freezes only admitted cues.

---

## 5. Security model

1. **Allowlist, data only.** The model can emit only v2 events: closed operations, closed geometry kinds, closed proposal tools with closed per-tool argument keys. No JS, shell, AppleScript, Swift, URLs in scene objects, shaders or callbacks (`ExplanationStream.swift:29-45` already rejects these; v2 keeps that).
2. **Limits.** All v1 limits (`ExplanationProtocol.swift:366-381`), plus: proposals at most 2/event and 4/turn; candidates at most 16; context pointer path at most 256 points; `targetID` must match an app-issued candidate in the current `captureID`; `sessionID`/`turnID`/`sceneID` copied exactly (identity check already in the reducer); coordinates within `imageSize`; text 1,024 B per object; speech 1,600 B per beat.
3. **Injection boundary.** Screen pixels, AX labels, window titles, web and terminal text are wrapped as untrusted reference data in the user message, never in system text (existing pattern `ExplanationProvider.swift:71,81,86-89`). Proposals are only *proposals*. Execution needs app-side validation, risk classification (`DrivePlan.Risk`) and, where required, the user's confirmation. A proposal whose `summary` or `arguments` echo screen text is still only data.
4. **Hard refusals.** No action on any `isSecure` candidate or focused `AXSecureTextField`. Values are never read (`AXSnapshotter.swift:55` already drops secure values). Never type passwords, card numbers or CVV (`DrivePlan.secretWords`, `:94`). Never press Return on insert (`TextInserter.insert(pressReturn: false)`). Send, delete, purchase and publish always ask (reuse `DrivePlan.isDestructive`). `openURL` is https only, the host is shown, it asks the first time per host, and there are no `file:`, `javascript:` or custom schemes. `openApp` takes a bundle ID resolved by `NSWorkspace.urlForApplication(withBundleIdentifier:)` and shows the app name. `clipboardWrite` always asks and can be restored.
5. **Visible agency.** While any action tool runs: an indicator next to the marker plus a menu-bar Stop; Esc cancels (global Esc is available only with key-listen access); long jobs appear as visible background jobs (**[Rec]** reuse the existing agent job cards in `ZeusCore/AgentCards.swift`, [Verify] fit).
6. **Credentials.** Keychain only (`Keychain.get(AnyLLMConfig.keyAccount)` pattern, `AppDelegate.swift:576`). No environment-variable secrets. The no-redirect delegate is kept (`ExplanationProvider.swift:150-155`).
7. **Consent and retention.** Feature on by default since 2026-11-11 (`pointing.enabled=true`, owner decision; it only listens for the keys the owner's own Input Monitoring or Accessibility grant allows and captures nothing until the keys are held). `pointing.drawWhileHeld` (default on) controls whether drags are ink while held. Screenshot upload requires `pointing.sendScreenshot` (default off, with a disclosure sentence naming the endpoint host) plus OS Screen Recording granted by the user. Capture covers only the display under the pointer, excludes Zeus, and happens only at key-down, or once more at key-up if a change was observed. Session memory is RAM only: at most 3 snapshots and 10 minutes, cleared at session end, quit, feature-off or delete. Transcripts are kept in `ExplanationHistory` like Chat explanations (50 records / 64 MiB / 30 days); **[Rec]** pointing sessions default to a 24 h TTL (owner decision). Durable preferences ("speak slower", "prefer simpler") go in `UserMemoryStore` (`ZeusCore/UserMemory.swift:4`), which is never filled from screen OCR and already has inspect/delete. Add a `pointing.memory.enabled` toggle.

---

## 6. Phases

Milestones are tracked separately in every phase: **M1 code written, M2 tests passing (portable and native), M3 packaged launch (`scripts/bundle.sh` app, TCC granted by the owner), M4 demo working.** Passing tests never imply M3 or M4.

### Phase 1: vertical slice (about 1.5 to 2 days)

Goal: hold Ctrl+Opt, see the marker and pointer capture, take an event-driven screenshot of the pointer's display, send it to the existing Any LLM provider via v2 with `targetID`, render a ring and label on the pointed control with system speech, and support interruption.

Add:
- `Sources/ZeusCore/Pointing/PointingKeyGesture.swift`: began on exact hold, spoiled to cancelled, ended. Double-tap Control is detected but not acted on yet.
- `Sources/ZeusCore/Pointing/PointingSession.swift`: states and generation from section 2.3 (guiding stubbed).
- `Sources/ZeusCore/Pointing/PointingTrace.swift`: bounded; uses `SpatialTrail` dwell constants.
- `Sources/ZeusCore/Pointing/PointingContext.swift`: candidate and context types, plus `imageRect(fromAX:)` built on `ScreenCoordinateMapper` and `ExplanationCaptureGeometry`.
- `Sources/Zeus/Pointing/PointingController.swift`: orchestration from section 2.2, using Buddy `listen()`/`think()`/`idle()` as the marker.
- `Sources/Zeus/Pointing/PointingHotkeyMonitor.swift`: same monitor pattern as `HotkeyMonitor.start()`, gated by `KeyListenAccess.whenGranted`.
- `Sources/Zeus/Pointing/PointingTargetProbe.swift`: `AXUIElementCopyElementAtPosition` on the system-wide element, 0.1 s timeout, role/label/frame/secure only.

Modify:
- `ExplanationProtocol.swift`: `ExplanationObject.targetID: String?`; event `version` 1 or 2.
- `ExplanationStream.swift`: v2 schema branch, accepting `targetID` only when version is 2.
- `ExplanationReducer.swift`: validate `targetID` against a candidate set passed in the registry.
- `ExplanationController.swift`: `beginDesktopTurn(prompt:context:snapshot:)`; resolve `targetID` to a ring/label rect before `presentation.apply`.
- `ExplanationScreenContext.swift`: `captureDisplay(containing:)` plus `LeasePolicy.renewing(max:120)`.
- `ExplanationProvider.swift`: request carries `PointingContext` JSON as untrusted data, plus pointing instructions.
- `AppDelegate.swift`: wiring near `:260` under a new `StartupService.pointingHotkey` and `pointing.enabled`.
- `SettingsCatalog.swift`: `pointing.enabled`, `pointing.shortcut`, `pointing.sendScreenshot`.
- `ZeusCore/StartupPolicy.swift`: the new case, denied in QA.

Tests (exact files):
- `Tests/ZeusCoreTests/PointingKeyGestureTests.swift`: `holdStartsImmediately`, `chatHotkeySpaceSpoilsAndCancelsWithoutSubmit`, `commandJoiningCancels`, `voiceOverBlocksControlOption`.
- `Tests/ZeusCoreTests/PointingTraceTests.swift`: cap, dwells, `sampleAtAudioOffset`.
- `Tests/ZeusCoreTests/PointingSessionTests.swift`: every transition, late-generation drop, barge-in.
- `Tests/ZeusCoreTests/PointingCoordinateTests.swift`: AX Quartz to AppKit to image px on 1x/2x, negative origins, a display above the primary, crop+resize, outside-crop returns nil.
- `Tests/ZeusCoreTests/ExplanationProtocolV2Tests.swift`: v1 still accepted; v2 `targetID` accepted only with a matching candidate; unknown field rejected; partial line not rendered.
- `Tests/ZeusAppTests/PointingControllerTests.swift`: synthetic mic, provider, capture and probe; key-down, key-up, ring rect equals candidate rect; key-down during speaking stops audio and freezes the pose; denied Screen Recording continues with AX-only context and a visible notice.
- `Tests/ZeusAppTests/PointingHotkeyMonitorTests.swift`: fed `ShortcutEvent`s.
- Extend `Tests/ZeusAppTests/ExplanationScreenContextTests.swift`: renewing lease, change invalidates, pointer-display selection.
- `qa/feature-map.json`: `F09.pointing-contracts` (portable), `F09.PointingControllerTests` (native-fixture), `F09.pointing-device` (unimplemented until evidence exists).
- `qa/portable-core/prepare.py`: `pointing` group.

Acceptance:
- Portable plus the native suites above pass.
- Packaged app (M3) launches with the feature off and has no new prompts.
- With the feature on and permissions granted by the owner: holding the keys over the Finder toolbar "Share" and asking "what is this" draws an orange ring at the AX frame within 2 pt and speaks; pressing the keys again mid-speech stops speech and animation within one frame of the stop call.

### Phase 2: full input surface and sync (3 to 4 days)

- Strokes on `MarkOverlay`, the `drawing` state, stroke bounds as candidates, multiple dwells.
- Deixis from `SFTranscriptionSegment` timing.
- Double-Control text entry (`PointingTextEntry.swift`). Fn+Control preset for the existing dictation key. Conflict warnings in `ShortcutConflicts` for pointing vs talk, dictation, chat and show-me.
- Reduce Motion and Reduce Transparency variants of the marker and ink.
- Word alignment from the system TTS marker callback, if verified.
- Off-main SSE reader.
- Stale detection: `AXObserver` `kAXMovedNotification`/`kAXResizedNotification`/`kAXUIElementDestroyedNotification` on the target's window, and a per-beat re-read of the target's position/size (more than 2 pt drift hides it).

Tests:
- `PointingStrokeTargetingTests.swift`, `PointingDeixisTests.swift`, `ShortcutConflictsPointingTests.swift` (Core).
- `PointingOverlayTests.swift` (app, owned windows): ignores mouse when not drawing, nonactivating, never key, excluded from capture, Reduce Motion is static.
- `PointingStaleTargetTests.swift`.

### Phase 3: guidance and actions (3 days)

- v2 `proposals`; `PointingGuidance.swift` (real-click await via `GuidedPresent.clickHits`, settle on an AX notification or a 500 ms labelled timeout, recapture, follow-up turn).
- `PointingActionTools.swift` with confirmation cards, indicator and cancel. Focused-field insert via `TextInserter`. Secure-field refusal.

Tests:
- `PointingProposalValidationTests.swift` (Core: allowlist, argument keys, risk, secure refusal, URL schemes).
- `PointingGuidanceTests.swift` (app: wrong click ignored, double click advances once, late click after replacement ignored, window moved means re-resolve).
- `PointingActionToolsTests.swift`: injected sinks only, never real typing (AGENTS.md).

### Phase 4: teaching cards, 3D, Tesla demo (4 to 5 days)

- `flow` and `equation` geometry; cutaway preset; card beats; `claims` with a brand-specific sources requirement.
- Curated source registry JSON (owner-approved URLs) mapped to `ExplanationRegistry.sourceIDs`.
- Procedural EV assets: battery as a grid of boxes in a group; inverter as a box with a label; motor as stator and rotor cylinders; drivetrain as gear cylinders plus an axle tube; wheels as cylinders. Energy flows battery to inverter to motor to wheels (`forward`), and regeneration runs `reverse`.
- Follow-ups use stable IDs: "show the motor" is camera plus highlight on `motor`; "rotate it" animates rotation on `motor`; "simpler" sends speech plus `remove` of detail objects; "highlight the battery" is `highlight`.

Tests:
- `ExplanationFlowGeometryTests.swift` (Core).
- `ExplanationClaimsTests.swift` (Core: a brand-specific claim without a source is rejected or downgraded).
- `ExplanationEVSceneFixtureTests.swift` with `docs/examples/pointing/tesla.ndjson` (reducer and renderer, owned host).

### Phase 5: alternate providers, memory controls, hardening (3 days)

- ElevenLabs timestamps adapter; optional Scribe realtime ASR selection.
- Session memory inspector (list, delete, disable); retention TTL.
- Output-device change handling.
- Network loss and model-unavailable UX.

Tests: `ExplanationElevenLabsAlignmentTests.swift`, `PointingSessionMemoryTests.swift`, `PointingFailureRecoveryTests.swift`.

### Phase 6 (later): RealityKit renderer when the floor is macOS 15 or later; a CGEventTap fallback only if measurements require it.

---

## 7. Testing and measurement

**Matrix (where each concern is covered):**
- Coordinates: `PointingCoordinateTests`, existing `ExplanationCoordinatesTests` and `CoordinateMapperTests`.
- Gesture targeting: `PointingStrokeTargetingTests`, `PointingDeixisTests`.
- Key conflicts: `PointingKeyGestureTests`, `ShortcutConflictsPointingTests`.
- Click-through: `PointingOverlayTests` plus an owned-window event driver (`OwnedWindowEventDriver.swift`) sending a click through the overlay to an owned button.
- Protocol: `ExplanationProtocolV2Tests` (fuzz partial chunks at every byte boundary; malformed ops never reach the presentation).
- A/V sync: extend `ExplanationPlaybackTests` with an alignment-anchored cue; cue lateness from the existing diagnostics.
- Interruption: `PointingControllerTests` barge-in, plus `PointingSessionTests`.
- Stale UI: `PointingStaleTargetTests` and the lease tests.
- Permission denial and revocation: injected `hasPermission` flips mid-turn, so marks hide and the turn continues as text/AX only.
- Packaged resources: the lint keeps forbidding `Bundle.module`; any new asset goes through `ZeusResources`.
- Crash regression: extend `test_source_lint.py` with:
  - `Task.sleep` forbidden under `Sources/Zeus/Pointing` except in `PointingGuidance.swift` (labelled settle timeout);
  - `SpeechDrawingTimeline.estimate` forbidden under Pointing;
  - `installTap(`, `requestAccess(`, `CGEvent.tapCreate` under Pointing must be inside `nonisolated` functions, checked by matching a `nonisolated` declaration in the enclosing function (lint plus fail-first sample lines, mirroring `test_lint_detects_the_original_crash_shapes`).

Add a `qa/regressions.json` entry for each defect found.

**Measurement (device, recorded in a receipt):**
- Key-down to marker on screen: `CADisplayLink` timestamp minus `NSEvent.timestamp`; target 1 frame or less, measured.
- Key-down to mic running.
- Key-up to first audio: existing `recordFirstAudioStart`.
- Key-up to first visual: existing metric.
- Cue lateness: existing.
- Stop latency: existing bracket.
- Idle CPU with the feature on but not held (only the key monitor is installed; the mouse monitor exists only during a hold).
- CPU and memory during a 30 s explanation (`ProcessEnergy.sample`).
- Snapshot memory ceiling: 3 x 8 MiB.
- Dropped-sample count in the trace.

### Manual acceptance: Tesla demo (owner-supervised, after M3)

1. Feature on, Any LLM with vision configured, system voice selected, Reduce Motion off.
2. Hold the keys and say "Explain how a Tesla electric car works". Release.
3. Speech starts. The battery pack builds first, then the inverter, motor, drivetrain and wheels, each appearing as its sentence plays (not before the audio).
4. Energy flow animates battery to wheels on "accelerate", then reverses on "regenerative braking". Both directions are labelled.
5. Generic EV facts carry no source chip. Tesla-specific statements show a source chip from the approved registry, or the phrase "varies by model" with a "needs reference" badge.
6. "show the motor": the camera moves to the same `motor` object and nothing is rebuilt.
7. "rotate it": the motor rotates.
8. "explain that more simply": shorter speech, detail objects removed, IDs stable.
9. "highlight the battery": the existing battery is highlighted.
10. Barge in mid-sentence: speech stops and the pose freezes. A new request starts.
11. Turn on Reduce Motion: flows become static arrows and objects snap in.
12. Disconnect the network mid-stream: a visible failure, and the committed scene is kept.
13. Quit and relaunch: no screenshot persisted; the scene is available in Chat history.

### Manual acceptance: on-screen button walkthrough

1. Open Preview with a document. Hold the keys and point at the Share button: "how do I send this as a PDF?"
2. A ring and label appear on Share (AX frame), followed by a dashed ring and badge "1" on the File menu, plus a confirmation card for the clipboard proposal.
3. Click elsewhere: nothing advances. Click File: after the menu opens, recapture happens and the next beat rings "Export as PDF…".
4. Move or resize the window mid-beat: marks hide, and "the window moved, point again" is shown.
5. Scroll: marks hide.
6. Decline the clipboard card: the clipboard is unchanged. Accept: it is written; undo restores it.
7. Focus a password field and ask Zeus to type it: refused with an explanation.
8. Revoke Screen Recording in System Settings mid-session: marks hide; the next turn works from AX/transcript only and says so.
9. Ctrl+Opt+Space opens Chat with no pointing turn and no capture.
10. VoiceOver on with Ctrl+Opt: blocked message, no listening.

---

## 8. Risks and open questions (owner decisions)

1. **Paid providers and keys:** keep Any LLM only, or add native Anthropic or OpenAI vision adapters? Use ElevenLabs (key exists for voice) for timestamped TTS and Scribe ASR? Approve any new vendor (Cartesia, Deepgram)?
2. **Default key:** use Control+Option as the default even though Zeus migrated talk away from it and it collides with VoiceOver and the Chat hotkey prefix (handled by cancel-on-spoil)? Or ship a different default, with Control+Option as a preset?
3. **Mouse during hold:** this plan captures the mouse on an ink overlay while the keys are held, so drags become scribbles and clicks don't reach apps (consistent with `AnnotationController`). Confirm, or prefer hover-only pointing with no capture.
4. **Screenshot consent:** `pointing.sendScreenshot` default off with disclosure. Confirm the default and the wording.
5. **Retention:** 24 h TTL for pointing session history vs the existing 30 days. Session snapshots RAM-only for 10 minutes.
6. **Tesla sources:** who curates and approves the source registry (URLs, review date)? Without it, Tesla-specific claims show "needs reference".
7. **Guided-state naming:** keep `guiding` as an explicit state or fold it into `speaking`.
8. **Risks:**
   - AX off-main safety ([Verify]).
   - System TTS marker callback availability ([Verify]).
   - SceneKit soft-deprecation (mitigated by the renderer seam).
   - Main-thread load from the SSE loop (Phase 2 fix).
   - Lease renewal can still miss keyboard-driven content changes, as the existing doc already states; keep the "hide on doubt" posture.
   - Double-Control may collide with a user's macOS Dictation shortcut ([Verify]).
   - TCC grants tied to signing identity reset on rebuilds (`KeyAccessNotice`), which affects M3/M4 repeatability.
   - SceneKit or other changes must not regress `F09.ExplanationRendererTests`.

### Critical Files for Implementation
- /Users/tony/Library/CloudStorage/OneDrive-MantuGroup/Documents/Chief of Staff/Apps Built/Zeus/Zeus-native/Sources/Zeus/Explanation/ExplanationController.swift
- /Users/tony/Library/CloudStorage/OneDrive-MantuGroup/Documents/Chief of Staff/Apps Built/Zeus/Zeus-native/Sources/Zeus/Explanation/ExplanationScreenContext.swift
- /Users/tony/Library/CloudStorage/OneDrive-MantuGroup/Documents/Chief of Staff/Apps Built/Zeus/Zeus-native/Sources/ZeusCore/Explanation/ExplanationProtocol.swift (with ExplanationStream.swift and ExplanationReducer.swift)
- /Users/tony/Library/CloudStorage/OneDrive-MantuGroup/Documents/Chief of Staff/Apps Built/Zeus/Zeus-native/Sources/Zeus/Voice/HotkeyMonitor.swift (with Sources/ZeusCore/Shortcut.swift)
- /Users/tony/Library/CloudStorage/OneDrive-MantuGroup/Documents/Chief of Staff/Apps Built/Zeus/Zeus-native/Sources/Zeus/App/AppDelegate.swift (wiring at :260 and :558), plus qa/feature-map.json and qa/closed-loop/tests/test_source_lint.py

Sources: [WWDC25 session 288](https://developer.apple.com/videos/play/wwdc2025/288/), [Bringing your SceneKit projects to RealityKit](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit.md), [DEV Community summary of the SceneKit deprecation](https://dev.to/arshtechpro/wwdc-2025-scenekit-deprecation-and-realitykit-migration-a-comprehensive-guide-for-ios-developers-o26), [Fatbobman weekly 090](https://fatbobman.com/en/weekly/issue-090/). The AVSpeechSynthesizer marker-callback page returned no content, so that fact stays marked [Verify].