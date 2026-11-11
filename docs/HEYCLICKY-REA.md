# Clicky and HeyClicky: Reverse Engineering Analysis for Zeus

Date: 2026-11-10. Scope: inform an independent Zeus implementation. No Zeus source edited. HeyClicky.app was inspected from outside only (file names, Info.plist, signature entitlements). Nothing decompiled, extracted, copied or run. Secrets in Info.plist are redacted and not reproduced.

Labels: **Observed** (seen in source or artifact), **Documented** (stated by the author or a writeup), **Inferred**, **Proposed** (for Zeus), **Unknown**. Confidence: H/M/L.

## 0. Evidence index

| ID | Evidence |
|---|---|
| E-001 | `https://github.com/farzaa/clicky` pinned at commit `e71105ce091d71dff4d89cf5d8d37ea1df460961` (2026-10-28T14:41:49-07:00, branch main). Shallow clone read locally. Paths below are relative to `leanring-buddy/` unless stated. |
| E-002 | `LICENSE` at that commit: MIT, "Copyright (c) 2026 Farza". |
| E-003 | `README.md`, `AGENTS.md` (CLAUDE.md is a symlink to it) at that commit. |
| E-004 | `CompanionManager.swift` (prompt `:556-580`, pipeline `:586-720`, transient hide `:732-757`, parser `:784-824`). |
| E-005 | `CompanionScreenCaptureUtility.swift` (whole file). |
| E-006 | `OverlayWindow.swift` (window `:15-45`, tracking `:411-445`, navigation `:456-570`, return flight `:635-660`). |
| E-007 | `GlobalPushToTalkShortcutMonitor.swift`; `BuddyDictationManager.swift:16-90, 219, 491-510`. |
| E-008 | `AssemblyAIStreamingTranscriptionProvider.swift`, `BuddyTranscriptionProvider.swift`. |
| E-009 | `ElevenLabsTTSClient.swift`. |
| E-010 | `ClaudeAPI.swift` (SSE `:155-205`, `max_tokens` `:144`). |
| E-011 | `worker/src/index.ts`, `worker/wrangler.toml`. |
| E-012 | `ElementLocationDetector.swift` (Computer Use coordinate path; no call site found). |
| E-013 | `leanring-buddy.entitlements`, `Info.plist` keys, `WindowPositionManager.swift:36,80,124`. |
| E-014 | `appcast.xml` (Sparkle feed titled "makesomething", hosted under a different GitHub account). |
| E-020 | `/Applications/HeyClicky.app/Contents/Info.plist` (v1.1.1, build 66). |
| E-021 | `codesign -d --entitlements -` on the app (read-only). |
| E-022 | Bundle directory listings: `Frameworks/`, `Helpers/`, `MacOS/`, `Resources/` (names and sizes only). |
| E-023 | `Resources/ClickyBrowserExtension/manifest.json` (MV3, version 0.6.3). |
| E-024 | `Resources/ClickyBuildInfo.plist` (short git sha `5c6081997`). |
| E-030 | Isaac Flath, "Point and talk: how Clicky's AI interface works", `https://isaac-flath.kit.com/posts/point-and-talk-how-clicky-s-ai-interface-works`. |
| E-031 | Product Hunt / directory results (search 2026-11-10): `https://www.producthunt.com/products/clicky-2-0`, `https://www.ycombinator.com/companies/heyclicky`, `https://www.everydev.ai/tools/hey-clicky`. Secondary sources. |
| E-040 | Zeus `docs/POINTING-ASSISTANT-PLAN.md` (560 lines); `Sources/Zeus/Explanation/ExplanationOverlay.swift:51-60`; `Sources/Zeus/Overlay/BuddyController.swift:14,200,247,453-460`. |

## 1. License verdict

**MIT, Copyright (c) 2026 Farza (Observed, H, E-002).** The author also says in the README "Go crazy with this repo", and that new work stays private (Documented, E-003).

- Zeus may copy, modify, merge and sublicense the open-source code. The single condition: the copyright line and the permission notice must be included in all copies or substantial portions of the Software. If Zeus copies no code and reimplements behavior independently (the stated Zeus approach), no notice is legally required. Ideas, algorithms and behaviors are not covered by copyright anyway.
- Recommended: add a credit line in Zeus's acknowledgments ("pointing interaction pattern inspired by Clicky, MIT, Farza"), and if any snippet is ever pasted, add the full MIT text in `THIRD-PARTY-NOTICES`. Not legally required for reimplementation.
- **MIT covers only the repo at that commit.** It says nothing about HeyClicky 1.1.1. The commercial app's code, prompts, JS, sounds, videos, fonts and assets are not granted (the bundle ships its own `LICENSE` and `ATTRIBUTION.md`, names seen only, not read or relied on). Zeus must not reuse any bundle asset, and the OFL fonts in the bundle carry their own license.
- Not licensed by MIT and not to be reused: the "Clicky/HeyClicky" name, icon, onboarding video URL, ElevenLabs voice ID, the Sparkle feed and EdDSA key, analytics keys. Also keep the real HeyClicky strings out of Zeus (the plan already forbids this).
- This is not legal advice.

## 2. Capability map and critical journey

### 2.1 Capability map

| Capability | Open-source Clicky (E-001) | HeyClicky 1.1.1 (bundle, E-020..E-023) | Class |
|---|---|---|---|
| Push-to-talk global hotkey (ctrl+option default) | Yes | Not inspectable | Observed / Unknown |
| Screenshot of all displays + transcript to a vision LLM | Yes | Info.plist declares Anthropic Messages and OpenAI chat completions URLs | Observed |
| Trailing point tag, flying triangle cursor, bubble | Yes | Not inspectable; the writeup says the product adds clicking | Observed / Documented |
| Spoken reply (ElevenLabs) | Yes | Many `voice-preview-*` and `realtime-voice-preview-*` mp3 names | Observed / Inferred |
| Menu-bar-only app (LSUIElement) | Yes | Yes | Observed |
| Backend proxy | Cloudflare Worker, 3 routes | `WorkerBaseURL` and `CodexWorkerBaseURL` at a first-party API host; Supabase and PostHog entries | Observed |
| Background agents, browser control, integrations | No | Codex runtime dir, 126 MB `clicky-harness`, browser extension, integration skills | Inferred |
| Drawing and 3D | No | `clicky-draw-*.js`, `clicky-three*.js`, spatial demo mp4 | Inferred |
| Reading the open document | No | Desktop/Documents/Downloads usage strings | Observed (strings) |

### 2.2 Critical journey as a state machine (open-source, Observed H)

```
idle ──ctrl+opt down (CGEvent flagsChanged)──► listening
  (cancels prior response Task, stops TTS, clears pointer target, shows overlay if transient)
listening ──ctrl+opt up──► finalizing transcript (ForceEndpoint, fallback timer 2.4 s)
finalizing ──final text──► processing   [spinner; screenshots captured NOW, not at key-down]
processing ──SSE complete──► parse trailing [POINT:..] tag from the FULL text
  if point: voiceState=idle, set target (pointer flight starts immediately)
  then TTS request for the stripped text (whole mp3 fetched, then played)
  ──audio starts──► responding ──audio ends──► idle
pointer: following ──target set──► flying (bezier, 0.6-1.4 s) ──► pointing (bubble, 3 s hold)
         ──► flying back (cancelable if the real cursor moves > 100 px) ──► following
new key-down at any time: cancels the response Task and TTS, clears the target
errors/cancel: CancellationError ignored; any other error → fixed system-TTS apology
```

Observed ordering consequence (H, E-004): the pointer flight is triggered before the TTS request even begins, so the cursor usually arrives and shows its bubble before the first spoken word. There is no speech-to-pointer alignment. The bubble text is a random canned phrase unless a custom one is set (E-006 `:175,586`). The pointer overlay's own timeline is fully independent of audio.

## 3. Mechanisms

### 3.1 Global hotkey (Observed, H, E-007)
- Listen-only `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly)` on `.flagsChanged/.keyDown/.keyUp`, run-loop source on the main loop in common modes. The callback re-enables the tap on `tapDisabledByTimeout/UserInput`.
- Press/release transitions come from a pure function over event type, key code and modifier flags (modifier-only chords such as ctrl+option; options include shift+fn, shift+control, and chords with Space).
- Permission: the app polls `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess` and requests screen access via `CGRequestScreenCaptureAccess` (E-013). A listen-only tap is gated by Input Monitoring on current macOS (Documented by Apple, M). The writeup says Accessibility is needed only for the hotkey (E-030). The permission poller calls `start()` repeatedly, so `start()` is idempotent (a restart would reset the pressed flag and kill the waveform).
- A short press-release before async mic startup finishes cancels the pending start task, to avoid a stuck overlay.

### 3.2 Screen capture (Observed, H, E-005)
- `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`, then `SCContentFilter(display:excludingWindows:)` excluding the app's own windows (matched by bundle id), then one `SCScreenshotManager.captureImage` per display. No `SCStream`.
- Output size: long side forced to 1280 px (aspect of the display preserved), JPEG quality 0.8 via `NSBitmapImageRep`. Retina is therefore downscaled, not captured at native pixels.
- **When:** after the final transcript, inside the response task, not at key-down. Latency between speaking and capture equals the end-of-turn delay. The writeup says "on hotkey release" (E-030); the source shows after transcript finalization. All displays every turn; the cursor display is sorted first.
- Each image is preceded by a text label: "screen N of M, cursor is on this screen (primary focus)" plus "(image dimensions: WxH pixels)".

### 3.3 Coordinate protocol (Observed, H, E-004, E-005, E-006)
- Model-facing space: **pixels of the delivered image, origin top-left**, with dimensions stated in the label. Display selection by a 1-based `:screenN` suffix matching the image order; omitted means the cursor display.
- Map-back: clamp to the image bounds; scale by `displayPoints / imagePixels` per axis; flip Y with the display height (AppKit bottom-left); add `NSScreen.frame.origin` for the global AppKit point. Frames come from `NSScreen` (via `NSScreenNumber` to `CGDirectDisplayID`), because `SCDisplay.frame` is top-left CG space, which breaks secondary displays (code comment).
- Overlay side: one overlay window per screen; each view converts global to local (`y = origin.y + height - point.y`); only the screen whose frame equals the target display frame animates. Target is offset +8 px right and +12 px down and clamped 20 px inside the screen.
- Weaknesses (Observed): silent clamping can mark the wrong edge element; no grounding check on the model's point; no staleness check (the screen can change during the several seconds between capture and flight); no use of AX to refine.
- Alternative never wired in: `ElementLocationDetector` uses the Computer Use tool definition and picks 1024x768, 1280x800 or 1366x768 by aspect ratio to improve X accuracy. No call site was found in the tree (bounded negative: grep for the constructor across `leanring-buddy/` found none, M). Authors' claim only that it is more accurate (Documented in a code comment, not measured).

### 3.4 Model prompt and output format (Observed, H, E-004, E-010)
- Request: Anthropic Messages, `stream: true`, `max_tokens` 1024, default Sonnet 4.6, Opus 4.6 selectable. Content: for each display an image block then a text label; the user text is the transcript. History: last 10 exchanges as text only (prior screenshots are not resent).
- Prompt (described, not copied): a lowercase, casual, spoken-style persona; one or two sentences by default, longer on request; no markdown or lists; no abbreviations; reference the labeled "primary focus" screen first; end with a seed for a bigger idea rather than a yes/no question; an element-pointing section saying to point whenever it helps and to say none otherwise, with four short examples (including a cross-display example).
- **Output format:** free text, then at the very end one tag `[POINT:x,y:label]`, `[POINT:x,y:label:screenN]` or `[POINT:none]`. One target per reply. The tag is outside the speech and carries a 1-3 word label.

### 3.5 Streaming parser (Observed, H)
- The SSE reader handles `content_block_delta` / `text_delta` and delivers chunks, but the chunk callback is a no-op in the voice path. The tag is parsed once, after the stream completes, by an end-anchored regex (`...\]\s*$`). Spoken text is the string before the tag.
- So Clicky does **not** parse while streaming and starts neither TTS nor pointing before the model finishes. Time to first sound = model finish + full TTS render. There is no incremental or mid-text pointing.
- Failure modes (Inferred from the regex): a tag not at the end, a decimal coordinate, or a screen label other than `screenN` yields no pointing and leaves the tag text in the spoken string.

### 3.6 Overlay window (Observed, H, E-006)
- `NSWindow` (not NSPanel) per `NSScreen`: `.borderless`, `isOpaque=false`, clear background, `level = .screenSaver`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, `hasShadow=false`, `hidesOnDeactivate=false`, `canBecomeKey/Main` false, `orderFrontRegardless()`. SwiftUI via `NSHostingView`. The menu-bar panel is a separate non-activating NSPanel. Own windows are excluded from capture so the model never sees the overlay.

### 3.7 Cursor flight animation (Observed, H, E-006)
- A 60 Hz `Timer` (not CADisplayLink) writes `cursorPosition` each frame; no implicit animation during flight.
- Quadratic Bezier from current position to target; control point = midpoint lifted by `min(0.2*distance, 80)` px; time eased with smoothstep; duration `clamp(distance/800, 0.6, 1.4)` s; rotation follows the curve tangent (+90 degrees); scale pulse `1 + 0.3*sin(pi*progress)`; glow grows mid-flight.
- Arrival: bubble streams characters with variable delay and a scale spring (0.5 to 1.0); holds 3 s; fades 0.5 s; return flight to cursor + (35, 25). Follow mode: a 16 ms timer polls `NSEvent.mouseLocation` (no event monitor) and a spring animation chases it. Only the return leg is cancelable by user mouse movement (more than 100 px from where navigation started); the forward leg and hold are not.
- Idle mode "transient cursor": if the always-visible cursor is off, the overlay fades in at key-down and out 1 s after TTS and pointing are both finished (polling every 200 ms).

### 3.8 TTS and speech/pointing sync (Observed, H, E-009)
- `POST {worker}/tts` with `eleven_flash_v2_5` (stability 0.5, similarity 0.75), response is the **complete mp3 body**, played with `AVAudioPlayer(data:)`. Not streamed, no word timestamps requested. `isPlaying` is polled only to time the overlay fade-out.
- Sync: none beyond ordering (section 2.2). On any TTS error (not just credits), a fixed message is spoken with `NSSpeechSynthesizer`, whose text blames credits (misleading).

### 3.9 Transcription (Observed, H, E-008, E-007)
- Default: AssemblyAI v3 streaming websocket (`speech_model=u3-rt-pro`, `sample_rate=16000`, `encoding=pcm_s16le`, `format_turns=true`, optional `keyterms_prompt`). Short-lived token (480 s) fetched from the worker before each session. Release sends a ForceEndpoint then Terminate. Final text waits for the end-of-turn or formatted turn, with a 2.4 s fallback. Partial text is not shown (waveform only).
- Alternatives behind a protocol: OpenAI upload-based (buffered WAV on release) and Apple Speech. Provider chosen by an Info.plist key. One long-lived shared `URLSession` for all sockets, because per-session sessions corrupted the pool (author note). The token URL in the repo is a placeholder that the builder must replace.

### 3.10 Proxy (Observed, H, E-011)
- Cloudflare Worker, POST only, 3 routes: `/chat` forwards the request body unchanged to Anthropic with the secret key and pipes the SSE back; `/tts` forwards to ElevenLabs with a server-side voice id; `/transcribe-token` mints the AssemblyAI token. Why: keep provider keys out of the app binary.
- Security gaps (Observed): no client authentication, no origin check, no rate limit, no model or `max_tokens` pinning on `/chat`. Anyone who learns the URL can spend the owner's keys with any parameters. Zeus does not need this shape (Keychain-held user key per the plan), but if a proxy is ever added it needs auth, quotas and server-side parameter pinning.

### 3.11 Memory (Observed, H)
- In-RAM array of the last 10 (transcript, spoken text) pairs, tag stripped, text only, not persisted, lost on quit. Each turn resends fresh screenshots.

### 3.12 Error handling (Observed, H)
- Task cancellation on new press; `CancellationError` silently ignored; one generic catch with PostHog error event and the fixed spoken apology; permission loss handled by polling and a panel UI. No retry, no timeout beyond the URLSession (120 s request, 300 s resource), no stale detection, no fallback when the tag is malformed.

### 3.13 Drawing and 3D: open-source versus commercial
- Open-source: neither exists (Observed, H). Overlay shows a triangle, waveform, spinner and a bubble.
- HeyClicky 1.1.1: bundle contains `clicky-draw-engine.js` (250 KB), `clicky-draw-native.js`, `clicky-draw-pieces.js`, `clicky-three.js` (416 KB), `clicky-three-parts.js`, two OFL handwriting/sans fonts named for the draw engine, `clicky-spatial-demo.mp4`, and the entitlement `cs.allow-jit` (Observed, E-021, E-022).
- **Inferred (M-L):** drawings and 3D scenes are rendered by JavaScript in a web view or in-process JavaScriptCore canvas, with the model producing structured drawing/scene data. `allow-jit` could equally be for the bundled harness or Codex runtime, so it is weak evidence for the renderer. How the model drives it is **Unknown**. Zeus's plan already chooses native renderers and closed data protocols, which avoids needing this.
- Public sources: a Product Hunt commenter asked whether Clicky could draw circles or arrows on screen; this is a user request, not a documented feature (E-031).

## 4. Open-source Clicky versus HeyClicky 1.1.1 (bundle evidence only)

| Aspect | Open-source (E-001) | HeyClicky 1.1.1 (E-020..E-024) | Class |
|---|---|---|---|
| Bundle id / version | repo project | `com.humansongs.clicky`, 1.1.1 (build 66), min macOS 14.2, hardened runtime | Observed |
| Sandbox | `app-sandbox` false | `app-sandbox` **false** (the brief assumed true; the signature says false) | Observed H |
| Other entitlements | network.client, camera, audio-input, mach-lookup exception | same set, plus `cs.allow-jit`; mach-lookup exception names `com.apple.screencapturekit.picker` | Observed H |
| Network config | worker URL in source | `AnthropicMessagesURL`, `OpenAIChatCompletionsURL`, `WorkerBaseURL`, `CodexWorkerBaseURL` (first-party API host) | Observed |
| Accounts / paywall | none | custom URL schemes `clicky` and `heyclicky` for auth, a hosted auth/db project entry, paywall intro video | Observed / Inferred |
| Analytics / crash | PostHog | PostHog, Sentry framework, PLCrashReporter bundle | Observed |
| Updates | Sparkle feed (E-014) | Sparkle with automatic updates, hourly checks, own appcast host | Observed |
| Helpers | none | `ClickyBrowserHost` (203 KB), `clicky-harness` (126 MB), `HeyClicky` main binary 110 MB | Observed |
| Agents | none | `CodexRuntime/` (bin, vendor), `ClickyCodexModelCatalog.json` (722 KB), `ClickyModelInstructions.md`, `AGENTS.md` | Observed names; background-agent use Inferred (M) |
| Browser control | none | MV3 extension 0.6.3 with `debugger, tabs, nativeMessaging, storage, alarms, tabGroups, downloads`; native-messaging host | Observed; CDP-over-native-messaging Inferred (M) |
| Integrations | none | skill packs for ClickUp, Dropbox, Gmail, Google Docs/Tasks, HubSpot, Jira, Linear, Teams, Outlook, Salesforce; markdown skills for GitHub, Notion, Obsidian, Blender, Excalidraw, Spotify, Maps, etc. | Observed names |
| Documents | none | usage strings for Desktop/Documents/Downloads: reads the open document to answer about the whole file | Observed strings |
| Voice | ElevenLabs flash | ten `realtime-voice-preview-*` mp3 (names match OpenAI realtime voices) and thirteen `voice-preview-*` mp3 | Observed names; provider Inferred (L-M) |
| UI sounds | 3 mp3 | ~80 wav (agent-launch, agent-done, build-3d, boing, ding...) | Observed |
| Draw / 3D | none | see 3.13 | Inferred |
| Pointing prompt/format in 1.1.1 | `[POINT:x,y:label:screenN]` tag | **Unknown** (not inspected; would require reading app internals) | Unknown |

## 5. Mapping to Zeus (`docs/POINTING-ASSISTANT-PLAN.md`)

Verdict: the plan is stronger than Clicky on grounding, staleness, cue timing, security and testing. It is missing a handful of concrete items. Zeus code facts verified read-only (E-040): `ExplanationOverlay` panels use `level = .floating`; `BuddyController` already has a CADisplayLink bezier "point(to:label:)" and uses `.screenSaver`.

| Mechanism | Clicky | Plan status | Recommended change |
|---|---|---|---|
| Hotkey | Listen-only CGEvent tap, modifier-only, idempotent start, re-enable on disable | Covered differently: NSEvent monitors (2.5), tap deferred to Phase 6 | Keep. Add to the Phase 1 measurement "dropped or late modifier events"; if a tap is ever added, copy the re-enable-on-`tapDisabled` and idempotent-start behavior (reimplemented). Plan's cancel-on-spoil is an improvement. |
| Capture timing | After transcript, all displays | Better: key-down, display under pointer, one recapture at key-up if changed | Keep. Do not copy Clicky's capture-after-transcript. |
| Capture size | Long side 1280, JPEG 0.8 | Size bounds exist (`ExplanationScreenContext`) | Fix the delivered long side at 1280 px (or similar), declare it, and store the scale factor in `captureID` metadata. |
| Coordinate protocol | Image px top-left in label text; clamp; scale; flip; add origin | Stronger (image px tied to `captureID`, `targetID`, nil outside crop, 48 px grounding) | **Change:** state the delivered pixel size inside the same message as the image and in the context JSON, never points. Add a unit test that an `imagePoint` to `globalPoint` round trip is within 1 pt on a 2x display with a notch, a display above and to the left of primary, and a scaled-resolution display. Do not clamp: reject or snap to the nearest candidate within a fixed pixel budget. Prove the Quartz/AppKit flip against `CGDisplayBounds` as the plan already asks. |
| Point format | One trailing tag per reply, parsed after stream | NDJSON beats, `cues` with `start/end/word` anchors, `targetID` | **Missing:** a first-class `point` cue (target `targetID` or image point, short label) distinct from `ring`, so the marker flies and lands while a ring marks the control. Make the default anchor `start` of the beat's real playback. Optional: a trailing-tag compatibility mode for weak "Any LLM" endpoints, parsed only at stream end, one target, schema-validated. |
| Streaming parser | Whole-text, end-anchored regex | Closed-schema NDJSON, bounded SSE, partial-chunk tolerant | Keep. Bounded negative: Clicky shows no incremental pointing; Zeus's per-beat flow can start TTS and pointer after beat 0 arrives. |
| Overlay window | NSWindow, `.screenSaver`, click-through, `canJoinAllSpaces+stationary+fullScreenAuxiliary`, not key, `hidesOnDeactivate` false | Reuses `ExplanationOverlay` | **Change:** `ExplanationOverlay` is `.floating`, which sits below open pop-up menus, so a ring on a menu item can be covered by the menu itself. Raise the annotation panel to a level above pop-up menus (the buddy already uses `.screenSaver`) and add a test that the ring is visible above an open `NSMenu`. Keep `nonactivatingPanel`, `canBecomeKey false`, `ignoresCycle`. Exclude panels from capture (the plan does). |
| Cursor flight | 60 Hz Timer, quadratic bezier, 0.6-1.4 s, tangent rotation, scale pulse | Reuses `BuddyController` (CADisplayLink bezier exists) | Keep CADisplayLink (better than Timer). Adopt the parameters as defaults: duration `clamp(d/800, 0.6, 1.4)`, arc height `min(0.2 d, 80)`, smoothstep, mid-flight scale 1.3x. Reduce Motion: no arc, a short fade/jump. Never offset the landing by a fixed +8/+12 without checking the target rect: land at the candidate rect's nearest edge or centre. |
| Pointer cancel rules | Mouse move cancels only the return leg | Barge-in by key-down stops everything | Keep the plan's rule (key-down, Esc, Stop). Add: user mouse movement during the hold phase must not cancel the forward flight; during the return leg cancel only past a threshold (Clicky uses 100 px; Proposed). |
| Speech timing drives pointer | None; pointer first, speech after TTS fetch | Cue admission from real playback, no estimated clock; word anchors need alignment (system TTS marker callback is [Verify]) | **Change:** make `start`/`end` anchors the Phase 1 guarantee and drop word anchors until `AVSpeechSynthesisMarker` or ElevenLabs timestamps are verified. Rule: the marker must not leave the cursor before the first audio buffer plays (no flight on TTS fetch). Add a bounded fallback: if audio fails, show the point after a labelled timeout and a visible "no audio" notice. Measure `firstAudio - flightStart` (should be at most 0 ms, or at most 150 ms in Zeus's tuning). |
| TTS | Whole mp3, non-streaming | System voice default; ElevenLabs streaming adapter exists | Keep. Whole-file TTS adds a full render delay; Zeus's per-beat (at most 2 clips) design is right. |
| Transcription | AssemblyAI streaming, 2.4 s fallback, keyterms | Apple on-device default with segment timing | Keep. Add a bounded end-of-speech fallback constant and a test (key-up to final text at most N s, then proceed with the best partial). Keyterms from Zeus app/context names are a cheap accuracy win (Proposed). |
| Proxy | Unauthenticated worker, body passthrough | Direct Keychain-held user key (5.6) | Keep. Do not add a Clicky-style proxy. If one is ever added, require auth and pin model and limits. |
| Memory | 10 exchanges in RAM, text only | RAM sessions, 3 snapshots, 10 min, consent toggles | Keep. Plan is a superset. Add: previous turns resend text only; a new screenshot per turn (avoid stale pixels). |
| Error handling | Single catch, fixed apology | `failed` state with a visible reason, permission loss hides marks | Keep. Add: malformed point, off-crop point and unknown `targetID` each show a caption and a diagnostics count, never a silent wrong position. Clicky's misleading "out of credits" message is the anti-example: classify errors (auth, rate, network, TTS, permission). |
| Permissions | AX poll + Screen Recording poll + Input Monitoring implied | `KeyListenAccess`, no prompt at launch | Keep. Add a first-run checklist that names each permission and what breaks without it. |
| Drawing/3D | Absent / JS web renderer (Inferred) | Native + SceneKit behind a seam, no web view | Keep. HeyClicky evidence does not justify a web renderer for Zeus. |
| Transient cursor | Overlay appears only during interaction | `pointing.enabled` off by default, marker on hold | Add an explicit "hide when idle" fade (Clicky: 1 s after speech and pointing finish) as a setting. |

### Top recommended plan changes
1. Add a first-class `point` cue and make `start` anchored to real first-audio playback the Phase 1 sync guarantee; defer word anchors until alignment is verified.
2. Raise the annotation overlay level above open pop-up menus (currently `.floating`) and add a visibility-over-menu test.
3. Declare the delivered image pixel size in-message, forbid clamping, snap-or-reject off-crop points, and add the multi-display, 2x, notch and negative-origin round-trip tests.
4. Adopt Clicky's flight parameters and rotation/scale cues as the default marker motion on the existing CADisplayLink path, with Reduce Motion and a rect-aware landing point.
5. Add an end-of-speech fallback and error classification, plus a timing metric `first audio minus flight start`.

## 6. Verification matrix for Zeus (finite)

P = positive, N = negative, M = multi-display, I = interruption. Each row states the pass condition and evidence class. Native rows need an owner-supervised packaged run (M3/M4); the rest can run in the portable or owned-window suites.

| ID | Case | Pass condition |
|---|---|---|
| P1 | Hold chord over a known button, ask "what is this" | Marker visible within one frame; ring within 2 pt of the AX frame; speech plays; marker starts only after first audio buffer |
| P2 | Point cue with `targetID` | Flight duration within the clamp 0.6-1.4 s; lands at the rect; label shown; ring present |
| P3 | Point cue with raw image point inside a candidate | Snaps to candidate; within 48 px grounding rule |
| P4 | Retina 2x display | Image-to-global round trip within 1 pt |
| P5 | Menu item targeted while a menu is open | Ring and marker drawn above the open menu |
| P6 | Reduce Motion on | No arc or scale pulse; marker lands with a short fade or cut |
| P7 | Beat 0 arrives before beat 1 | Speech and marker start on beat 0 while later beats still stream |
| N1 | Point beyond image bounds | Not drawn; caption "not grounded"; diagnostics count increments |
| N2 | Unknown or stale `targetID` | Dropped before render; no pointing |
| N3 | Malformed, truncated or duplicate-key JSON line | Rejected by closed-schema scanner; no partial render; session survives |
| N4 | Screen Recording denied or revoked mid-turn | Marks hide; turn continues from AX or text with a visible notice |
| N5 | Screenshot consent off | No pixels sent; the request body contains none (assert on the outgoing payload) |
| N6 | TTS fails | Visible "no audio" notice; pointer shown after a labelled timeout; no wrong-cause message |
| N7 | Secure field under the pointer | No label text or value sent; no action proposal accepted |
| N8 | Chord spoiled by Space (Chat key) | No request, audio discarded, no capture |
| N9 | VoiceOver on with Ctrl+Opt | Blocked message; no listening |
| M1 | Target on non-cursor display | Overlay on that display only animates; coordinates correct |
| M2 | Display arranged above and left of primary (negative origin) | Round trip within 1 pt |
| M3 | Mixed scale factors (1x and 2x) | Same pass condition on each |
| M4 | Display unplugged mid-turn | Marks hidden; no crash; next turn recaptures |
| M5 | Space or full-screen app active | Overlay remains visible, still click-through |
| I1 | Key-down during speech | Speech stops and pose freezes within one frame of the stop call; new listening begins |
| I2 | Esc or menu Stop during flight | Flight stops; overlay hides; no late callback moves the marker (generation check) |
| I3 | Window moves or resizes during the beat | Marks hide with "window moved" notice |
| I4 | Mouse moves during the hold | Forward flight is unaffected; trace records the path |
| I5 | Network drop mid-stream | Committed scene kept; visible failure; no hang |
| I6 | Output device changes mid-speech | Current beat stops and restarts from beat start; no silent clock |

## 7. Open questions and access gaps

- **Unknown:** HeyClicky 1.1.1's prompts, point format, coordinate protocol, animation, TTS/ASR providers, and drawing/3D protocol. Access: outside-only by instruction; no binary or JS inspection; the app was not run. Bounded negative: Info.plist and file names show endpoints and renderer libraries but not behavior.
- **Unknown:** whether `allow-jit` is for the draw/3D renderer or the bundled agent runtime.
- **Unknown:** whether HeyClicky still uses a trailing tag. The writeup (E-030) describes the open-source flow only.
- **Unknown:** the ElevenLabs voice id in `wrangler.toml` and the hosted worker's real config; not relevant to Zeus.
- **Access gap:** GitHub REST API was rate-limited from this host; the repo was read via a shallow `git clone` and raw pages instead. The clone is complete at the pinned sha. The repo wiki was not fetched (only the README and `AGENTS.md` were read); the Issues tab and releases were not read.
- **Access gap:** no public demo videos were watched; Product Hunt and directory pages are secondary, and aggregator upvote counts were not relied on.
- **Unknown (Documented by Apple, not verified here):** that a listen-only CGEvent tap needs Input Monitoring on macOS 15 and 26, and whether AX calls are safe off the main thread; both already marked [Verify] in the plan.
- **Zeus decisions needed:** default hotkey (Control+Option collides with VoiceOver), whether word-level sync is worth an ElevenLabs timestamp dependency, and whether to add a trailing-tag compatibility mode for weaker vision models.
- **Provenance caution:** the repo's `appcast.xml` points at releases under a different GitHub account and the name "makesomething", and the push-to-talk file header still says makesomething (Observed). Treat the appcast and its signature as not belonging to Zeus.
