# Talk visuals plan: Ultron draws on screen while it answers

Planned 15 November 2026 against `35e0550` (read-only). Owner decision: build it inside the talk turn, with the
owner's Claude login (Claude Code CLI), no API key, screenshots only with consent. Every file:line was re-read.

## 1. Architecture

**The image path exists but the race skips it.** Talk turns already capture every display at key-down
(VoiceTurnController.swift:179) into `BrainRequest.screenshots` (:699-714): 1280 px long side, JPEG 0.8, cursor
display first (ScreenCapture.swift:5, 21-24). The `.claude` race candidate is the app's `ClaudeCLIProvider` only
when `installed[.claude] == nil` (Router.swift:375); otherwise `CLIEngineProvider` (:396-398), which feeds text on
stdin only. `ClaudeCLIProvider` already reuses `PersistentClaudeSession` for voice turns (ClaudeCLIProvider.swift:55-63),
sends base64 images (:181-195) and runs with the lean flags (:158-160).

1. **Route.** With consent on and shots present, the `.claude` candidate is the app's `brain` (`ClaudeCLIProvider`,
   AppDelegate.swift:239): add `preferAppClaude: Bool = false` to `brainEngineCandidates`; test
   `installed[.claude] == nil || preferAppClaude` at Router.swift:375.
2. **Image budget.** Send only `shots.prefix(1)` (cursor display, about 1.4k image tokens). The 8 s first-text budget
   stays (TurnRace.swift:10). Expected +0.5 to 1.5 s to first token, unmeasured: step 7 logs it.
3. **Context growth.** `PersistentCLIPolicy.maxTurns = 5` (VoiceLatencyTrace.swift:148) would pile images across turns.
   Add `carriedImage` to `Slot`; a runner that served an image turn is retired before the next turn. The talk-key
   warm-up refills it (PersistentClaudeSession.swift:188-192).
4. **Scene format.** A compact leading tag `[DRAW:{json}]`, translated by the app into Explanation v1
   `ExplanationObject`s in capture space (ExplanationProtocol.swift:143-160; geometry ring, arrow, path, label at
   :71-72). Not the pointing v2 event: it needs app-issued `targetID`s from the AX probe (not in a talk turn), costs
   tokens before the first spoken word, and `PointingSceneResolver` lowers v2 to v1 anyway (PointingSceneResolver.swift:4-6).
5. **Wire format.**
   `[DRAW:{"s":1,"m":[{"k":"ring","x":412,"y":88,"r":24,"at":0},{"k":"arrow","from":[600,300],"to":[430,100],"at":1},{"k":"ink","pts":[[..],..],"at":1},{"k":"card","x":440,"y":120,"t":"Export as PDF","at":2}]}]`
   Coordinates are screenshot pixels, top-left origin, as `[POINT]` (ZeusPrompt.swift:75). `at` is the 0-based index of
   the spoken sentence the mark appears with. Limits: 6 marks, 24 ink points, 60 characters of text, `at` at most 7.
6. **Parsing.** `ZeusTagStreamParser` recognises leading tags only (ZeusTag.swift:287-299; ResponseSanitizer.swift:3-5).
   Add `"[DRAW:"` to `prefixes` (ZeusTag.swift:131) and reuse the brace-matching JSON path of `[ACTION:` (:171-179).
   Trade-off: about 80 tokens (roughly 1 s) before speech; a mid-stream tag needs sanitizer changes and is deferred.
7. **Mapping.** A pure translator builds an `ExplanationCaptureGeometry` from the `ScreenShot` (`pixelWidth`,
   `pixelHeight`, `displayFrame`; Brain.swift:39-53). The app resolves `displayID` and `backingScale` by matching
   `displayFrame` to `NSScreen.frame` (`ScreenShot` has no display id). Rendering uses
   `ExplanationOverlay.panelTransform` (ExplanationOverlay.swift:91). Pixel to point must equal
   `PresentPointMapping.screenPoint` (PresentPointMapping.swift:20-30; CoordinateMapper.swift:219-224); a test pins it.
8. **Rendering.** Reuse `ExplanationOverlay` and `ExplanationCanvasArtwork`. `present(scene:context:)` needs an
   `ExplanationScreenContext` lease (ExplanationOverlay.swift:27-31): add `present(scene:capture:reduceMotion:)` sharing
   the body. Cards are capture-space `label` objects (whether `geometry.kind == .card` renders in capture space is
   unknown; the hosted test settles it).
9. **Timing.** `Speaker.speak(_:)` has no per-line start hook (Speaker.swift:77-96). Add
   `speak(_ text: String, onStart: (@MainActor () -> Void)?)`, fired in `speakLine` when audio starts. `runTurn` counts
   sentences (VoiceTurnController.swift:837-851) and reveals the marks whose `at` equals that index.

## 2. Consent and privacy

- One setting `talk.drawOnScreen`, default false, in `FeatureSettings` (near FeatureSettings.swift:36) and as a
  `SettingsCatalog` toggle (near SettingsCatalog.swift:164; table in scripts/gen-settings-catalog.py, regenerate).
- Off: no DRAW prompt, no route change, no new capture; byte-identical to today.
- On: capture still needs the OS Screen Recording grant (`CGPreflightScreenCaptureAccess`, ScreenCapture.swift:10).
- Never stored: images stay in memory; the persistent path writes stdin only; `--no-session-persistence`; logs record
  mark counts only, never base64 or label text.
- Out of scope, owner decision pending: talk turns already capture at :179 regardless of this setting and send shots to
  the anthropic-api tier and the `ClaudeCLIProvider` fallback. This ticket does not change that.

## 3. Failure modes

| Case | Rule |
| --- | --- |
| No tag, malformed JSON | `.complete(nil)` strips it from speech (ZeusTag.swift:156-157); speech plays, nothing drawn |
| Marks outside the image | Dropped; cards clamped inside (pure rule) |
| Stale screen | Clear on the next key press, a screen-parameters change or a frontmost-app change; auto-hide 4 s after the last sentence; skip if `displayFrame` matches no screen |
| Claude loses the race | Draw only when the winner saw pixels (`claude` app provider or `anthropic-api`); winner id from the `firstText` callback (VoiceTurnController.swift:917-923) |
| Reduce Motion | `reduceMotion: Preferences.reduced` (Preferences.swift:68): marks appear without animation |
| Restricted CLI turn | `shots` empty (:699): nothing drawn |

## 4. Files and interfaces

New `Sources/ZeusCore/Present/TalkDraw.swift`:

```swift
public struct TalkDraw: Equatable, Sendable { public var screen: Int; public var marks: [Mark] }
public enum TalkDrawParser { public static func parse(_ json: String) -> TalkDraw? }
public enum TalkDrawScene {
  public static func objects(_ draw: TalkDraw, shot: ScreenShot, captureID: UUID) -> [Int: [ExplanationObject]] // by sentence index
}
public enum TalkDrawPolicy {
  public static func accepts(winner: String?) -> Bool
  public static func wantsImages(consent: Bool, shots: Int) -> Bool
}
```

New `Sources/Zeus/App/TalkVisualPresenter.swift`:

```swift
@MainActor final class TalkVisualPresenter {
  func begin(_ draw: TalkDraw, shot: ScreenShot)
  func reveal(sentence: Int)
  func clear()
}
```

Changed: `ZeusTag.swift` (`case draw(TalkDraw)`); `ZeusPrompt.swift` (`static func drawInstructions() -> String`, appended
in `runTurn` to the stdin context, not the argv persona, so the persistent launch key is unchanged,
ClaudeCLIProvider.swift:49-51); `Router.swift`; `VoiceLatencyTrace.swift` (`Slot.carriedImage`);
`PersistentClaudeSession.swift`; `Speaker.swift`; `ExplanationOverlay.swift`; `VoiceTurnController.swift`;
`FeatureSettings.swift`; settings catalog; `qa/regressions.json`; portable-core lists in `qa/portable-core/prepare.py`
when a Core file or suite is added.

## 5. Sequence (one commit each; failing test first, then the change)

1. REG-700 `ZeusTagStreamParserTests`: a leading `[DRAW:{...}]` (also split across chunks) emits `.tag(.draw)`;
   malformed is stripped, never spoken. Then the prefix and parser.
2. REG-701 `TalkDrawTests`: limits; out-of-bounds dropped; cards clamped; mapped centres equal
   `PresentPointMapping.screenPoint` on 1x, 2x, a downscaled shot and a secondary display at negative x. Then `TalkDrawScene`.
3. REG-702 `TalkDrawPolicyTests`: consent off gives no images; a non-image winner is rejected. Then the policy.
4. REG-703 `RouterRaceTests` (extended): `preferAppClaude` gives the app provider for `.claude`; `PersistentCLIPolicy`
   retires a runner that carried an image. Then the router and policy.
5. REG-704 `SpeakerTests` with a fake engine: `onStart` fires once per line, in order. Then the hook.
6. REG-705 app test, fake `BrainProvider` streaming `[DRAW]` plus three sentences: presenter gets `reveal(0)` before the
   second line starts; consent off gives zero presenter calls and the same screenshots as today; the next key press
   calls `clear()`. Then wire `runTurn`.
7. REG-706 hosted overlay test (pattern of PointingOverlayTests.swift): ring, arrow and label present on the main
   display, `isVisible`, `hide()` leaves no panels. Then the overlay overload; log `first_token_ms` with images.
8. REG-707 settings catalog test: `talk.drawOnScreen` exists, default false. Then the setting and the prompt text.

Gates: build, the full suites, the regression lint, the development gate at head.

## 6. Acceptance criteria

- Setting off: talk-turn requests and output unchanged (REG-705).
- Setting on: Claude receives exactly one JPEG, of the cursor display.
- A ring, arrow or card appears within 150 ms of its sentence's audio start.
- Marks land where `[POINT]` maps, on Retina and on a second display.
- Garbage or no tag: speech only; no bracket text ever spoken.
- Overlays clear on the next press and 4 s after the answer.
- Release to first text stays under 8 s with images; measured and logged.

## 7. Risks

- Latency: image prefill plus the leading JSON may push first speech past 3 s; mid-stream tags next if so.
- Coordinate precision of the model on 1280 px shots is unmeasured.
- Existing mismatch outside this ticket: `CLIEngineProvider` sends no images while `ZeusPrompt.userText` says
  screenshots are attached (ZeusPrompt.swift:158-162).
- Card rendering in capture space unknown; falls back to `label`.
- No irreversible step; gated and off by default.

## 8. On-device checks (owner only)

1. Setting on; hold Right Option in Preview and ask "where do I export this as PDF": ring and card appear with the right sentence.
2. Repeat on a second display and on the built-in Retina screen.
3. Reduce Motion on: marks appear with no animation.
4. Setting off: nothing draws; the log shows no image attached.
5. Compare `first_token_ms` in the voice log with images on and off.
6. Control+Option and Control+Option+Space behave the same.
