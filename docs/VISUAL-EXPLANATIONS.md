# Native voice-driven visual explanations

This is the local implementation of the two November 10 visual-explanation requests. It extends the existing SwiftUI/AppKit Chat window. It is not a replacement app, a browser renderer, or release acceptance. The feature is off by default.

## Current behavior and boundaries

Settings → Assistant → Visual explanation enables the Chat surface. Type a request or use the native hold-to-speak control. The in-app shortcut toggles a spoken request and is configurable. The microphone never starts when this surface opens. Apple recognition requires on-device support and the owner's microphone/Speech permissions; the alternate WhisperKit route requires a model already loaded by Zeus through its existing explicit preparation flow.

Generation uses the selected **Any LLM** OpenAI-compatible endpoint, with the existing model cap and Keychain account. It has a dedicated data-only streaming adapter. It does not call the ordinary action-capable Chat send path, agent CLIs, `VoiceTurnController.runTurn`, browser actions, or `FastActions`. A configured model must actually support streamed chat completions and follow the scene protocol; refusal, incompatible endpoints, cut-off output, malformed events and network failures are visible failures, not fallback providers.

The composer displays the selected endpoint host. The optional Local-only control refuses non-loopback endpoints and stops an active turn when changed; it never chooses a replacement provider. This constrains the configured endpoint, not the internals of a locally hosted service: a local proxy can itself use remote inference.

Installed macOS voices synthesize short beats into bounded private temporary PCM files. The owned audio player supplies measured duration and current playback position. Scenes appear incrementally while the corresponding audio plays. No estimated words-per-second clock is used. System synthesis currently supplies no verified word alignment, so word-anchored cues use the documented beat-boundary fallback. Caption mode creates no speech audio and advances only through an explicit control.

Explanation options lists the voices actually installed on the Mac and a System default choice. Changing the selected voice, microphone or recognition engine stops the current turn; each new render snapshots the choice before suspension. A saved voice that has disappeared remains visibly unavailable and fails without an implicit replacement or download.

The Canvas renderer draws native 2D shapes, paths, labels, connectors, charts and cards. SceneKit draws bounded procedural 3D primitives, groups, materials, meshes and labels, with explicit camera controls. Stable object IDs support follow-up edits. Selection has an accessible object list and keyboard edit controls. The renderers consume validated presentation snapshots; neither owns model code, shaders, scripts or an independent animation clock.

Stop cancels model work, synthesis, pending input and playback. Session/turn/capture identities and generation checks discard late completions. Only admitted cues survive; interruption freezes the last safe visible pose. Undo returns to the pre-beat scene rather than an unseen future animation target. Replay is read-only and regenerates narration for completed beats; temporary audio is not a persistent replay cache. Scrubbing previews the current narration beat, then returns through the separate scene control.

## Files and responsibilities

| Boundary | Implementation |
| --- | --- |
| Typed protocol, bounds, strict JSON/NDJSON | `Sources/ZeusCore/Explanation/ExplanationProtocol.swift`, `ExplanationStream.swift` |
| Atomic graph validation and revisions | `ExplanationReducer.swift` |
| Bounded SSE envelope | `ExplanationCompletionStream.swift` |
| Actual-clock cue admission, interpolation, replay | `ExplanationPlayback.swift` |
| Delivered image, scene, display and AppKit transforms | `ExplanationCoordinates.swift` |
| Applied history, undo/redo, bounded atomic local store | `ExplanationHistory.swift` |
| Provider request and cancellation/backpressure | `Sources/Zeus/Explanation/ExplanationProvider.swift` |
| Native TTS, PCM ownership, playback | `ExplanationAudio.swift` |
| Permissioned push-to-talk and verified cache-only ASR | `ExplanationMicrophone.swift`, narrow existing `SpeechInput`/`WhisperKitEngine` changes |
| Integrated orchestration and Chat surface | `ExplanationController.swift`, `ExplanationPane.swift`, existing Chat/AppDelegate bindings |
| Canvas, SceneKit, native input control | `ExplanationCanvas.swift`, `ExplanationSceneView.swift`, `ExplanationTalkButton.swift` |
| Explicit one-display snapshot and passive annotation windows | `ExplanationScreenContext.swift`, `ExplanationOverlay.swift` |

## Protocol and ordering

Each version-1 event contains application-issued session, turn and scene UUIDs; sequence; base/revision; a stable beat ID; one speech chunk; ordered visual cues; and a final flag. The first sequence is zero, every new event advances by one, and every beat reserves exactly one scene revision. A follow-up begins with an application-owned monotonic revision bump before accepting new model edits.

The wire decoder rejects unknown fields, duplicate JSON keys, executable operations, nonfinite values, malformed UTF-8, unsafe geometry, unauthorized assets and citation IDs, identity changes, gaps and conflicting duplicates. A complete LF/CRLF frame is necessary before decoding. Stream completion requires both a final scene event and a complete provider stop/DONE sequence; EOF alone is failure.

Limits include 64 KiB/event, 512 KiB/turn, 64 events, 16 cues/event, 128 operations/event, 256 objects, 1,024 points/object, 4,096 mesh vertices/object, 12,288 triangle indices/object, 1,024 UTF-8 bytes/object text and 1,600 speech bytes/beat. Aggregate geometry, ancestry depth, composed transforms, camera values, animation durations and interpolated poses are validated too. The SSE envelope has independent byte/line bounds. Synthesis/playback retains at most two prepared clips and applies backpressure to generation.

Future events are validated against a projected graph. They do not mutate the visible or saved scene. Actual playback start reserves the beat revision; admitted cues commit in order under an ephemeral history token. Replay/seek never acquire that token. Long visual transitions are clamped to actual remaining media duration, not a fabricated speech estimate. Reduced Motion snaps admitted motion and preserves intentionally hidden static objects.

Complete examples live in [examples/visual-explanation](examples/visual-explanation/README.md).

## Capture and data handling

Screen context is optional. Choose a display and explicitly capture it once. The owner must grant Screen Recording permission in macOS; Zeus does not automate the consent prompt. The producer captures only that display, excludes Zeus windows, bounds image dimensions/bytes, and rejects stale/cancelled completions. A separate one-shot checkbox authorizes including those pixels in the next model request. An endpoint without image support fails visibly; images are never silently sent through a different provider.

Capture coordinates are the **delivered cropped/resized image pixels**, top-left origin. Full image dimensions, crop, delivered dimensions, display identity/frame and backing scale remain application-owned metadata. A model cannot supply a screen transform. Canvas rendering on the frozen snapshot uses the same projection as hit testing. Desktop annotation panels are nonactivating, pass through input and never request Accessibility permission merely to draw.

Desktop annotations have a five-second, nonrenewing lease with conservative invalidation on observed foreground/Space/display/window metadata and input changes. **This does not prove live pixel equality:** keyboard-driven or programmatic page changes can escape passive observation. If verification is unavailable, desktop marks hide and the frozen snapshot remains in Chat. Saved capture IDs or geometry cannot restore a live lease.

No microphone audio, synthesized audio, screenshot bytes, credentials or provider payload logs are persisted in explanation history. Local records contain the bounded visible conversation, applied scene snapshots and revision metadata. The store rejects symlinks, hard links, nonregular/oversized files, stale replacement receipts and unsupported versions. Writes use a private temporary file plus atomic replacement; directory-sync and retention failures remain visible. Default retention is 50 records, 64 MiB and 30 days. Temporary synthesis file deletion is best-effort on owner release; deletion failure is not currently a surfaced product diagnostic.

Meaningful scenes retain their Chat link even if local storage is unavailable. Failed writes remain owned in memory and retry in checkpoint order; switching conversations cannot silently replace that unsaved record. Retention eviction invalidates the saved checkpoint before the still-open record is edited again. Deleting a visual conversation joins its pending writes and removes its exact linked history UUID without recreating the sidebar link. Unreadable unrelated records are left untouched and unverifiable deletion stays a visible failure.

Quit first disables new explanation work, retries failed Chat links and joins owned saves/deletions. An unresolved failure keeps the app open. The three-second deadline is cooperative: synchronous filesystem work can delay the timer, so this is not a hard I/O timeout. These native quit/window integrations still require macOS execution.

Illustrative geometry is labelled as such. Arbitrary image URLs and fabricated source links are refused. The production registry currently has no external photo/search/generation service attached, so unapproved asset/source IDs fail closed. The schema/renderer support approved image IDs; that is not a claim that photo retrieval or generated-image provenance is delivered.

## Provider and dependency decisions

The deployment floor remains macOS 14.2. No dependency was added. FluidAudio is still pinned to 0.18.0 and Argmax/WhisperKit to the existing 1.1.1 revision.

Pinned FluidAudio's legacy `KokoroAneManager` is a compiled candidate, not silently invoked. Its resource downloader can fetch lexicon/voice-pack assets outside the global offline switch; mutable model-weight revisions and missing per-instance cache-only controls prevent claiming an offline inference boundary. The new feature therefore uses installed system voices while that installation boundary remains unresolved. Argmax TTSKit is a separate macOS 15+ product and was not imported or used to raise the deployment target.

WhisperKit's `download: false` alone is insufficient: tokenizer loading can fall back to a Hub download. The added capability only admits the existing private instance after model loading finished with a tokenizer, then calls the no-loading decode route under shared inference exclusion. Merely finding files on disk does not satisfy this capability. No model download, provider call, real speech recognition or audio playback was performed during Linux verification.

Version-specific reference inventory (source review, not runtime results):

| Reference | Verified revision / license | Decision |
| --- | --- | --- |
| [FluidAudio 0.18.0](https://github.com/FluidInference/FluidAudio/tree/e15287985625dbf544a343df679436789ffb03fb) | `e15287985625dbf544a343df679436789ffb03fb`, Apache-2.0 code | Existing dependency. Legacy Kokoro API candidate stays inert until the model installation/offline boundary is resolved. Individual voice/model assets need their own notices. |
| [Argmax 1.1.1](https://github.com/argmaxinc/argmax-oss-swift/tree/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4) | `1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`, MIT code | Reuse existing WhisperKit. Separate TTSKit requires macOS 15+ and was not selected. Model licenses are separate. |
| [LiveKit Agents](https://github.com/livekit/agents/tree/a77605ee7ad7b0ab6c4cfeefa8708778a5dbe18f) | `a77605ee7ad7b0ab6c4cfeefa8708778a5dbe18f`, Apache-2.0 framework | Playback/event lifecycle reference only. No Python/server/WebRTC dependency added. Separate turn-model license restricts use to LiveKit Agents. |
| [OpenAI Realtime Console](https://github.com/openai/openai-realtime-console/tree/ab8b8f5852b47ec1b9ef73bf566851d0eeafddbb) | `ab8b8f5852b47ec1b9ef73bf566851d0eeafddbb`, MIT | Example and credential-boundary reference only; no browser microphone flow or demo backend imported. |
| [ElevenLabs JS 2.77.0](https://github.com/elevenlabs/elevenlabs-js/tree/e360231b65d4d75f38cf29fc1cfc7103f8b058c1) | `e360231b65d4d75f38cf29fc1cfc7103f8b058c1`, MIT SDK | Optional alignment reference only. No Node SDK or hosted voice calls added. SDK licensing does not grant service or voice rights. |

Configuration uses the existing Settings → Connections → Any LLM endpoint/model and Keychain credential. HTTPS is required except explicit loopback HTTP. Credentials containing header controls, URL user information, redirects, cookies and credential-store fallback are refused. There are no new secret environment variables or automatic model-install commands. The selected endpoint must support the exact streamed chat-completions request; no particular provider/model has been live-certified here.

## Verification and remaining acceptance

The options panel exposes an explicit Refresh/Copy diagnostics view. These fixed-size numeric aggregates stay in memory and are never automatically exported. Request-to-first-audio timing starts when the player reports playback; request-to-first-visual timing ends at scene-state submission, not a verified display frame. Cue lateness compares actual cumulative media position with the due cue position; it is not a measurement of speaker-to-display synchronization. Caption mode does not claim an audio start or audio-clock sample, and replay is excluded from new-generation metrics. Stop timing brackets synchronous cleanup, not completion of asynchronous OS teardown.

Resource samples occur at request, beat completion, stop, and explicit refresh, without an extra polling timer. CPU delta and peak physical memory footprint describe the whole process, not this feature alone. Fixed counters saturate at 4,096 samples; invalid/backwards/nonfinite clocks and stale tokens are refused. Current failure instrumentation covers model-provider, narration and response-validation handling after submission. Microphone, renderer and storage errors remain visible in the product but are not included in these diagnostic counts. No private content, IDs, endpoint URLs, absolute timestamps or error descriptions enter the report. GPU energy, physical audio/display latency, frame pacing and permission cessation still need device instrumentation.

The standard development runner now includes the exact eight pure explanation modules and their tests. Native adapter/controller/provider/renderer/control/screen-context suites are explicitly bound in `qa/feature-map.json`; the renderer/control/screen window suites use the owned AppKit host. The original nineteen feature acceptance rows retain their native/device obligations. A new visual-explanation device obligation stays unimplemented until actual evidence exists. Every newly caught defect is recorded with an executable guard in `qa/regressions.json`.

The [initial local verification receipt](../qa/receipts/20261110/visual-explanation-local.json) retains command logs and source hashes: 91 exact-source Core tests passed across eight suites, 25 Controller tests passed in the documented portable harness, and 154 verification-tooling selftests passed. All 50 changed Swift files passed syntax parsing; that is not an Apple SDK typecheck. The Controller harness omits native adapters, replaces their defaults with inert fakes and removes Observation annotations for the Linux runtime. The map now binds all 192 new explanation test methods, including 100 native test methods awaiting macOS execution. Passing synthetic tests do not establish the real voice, GPU, permissions or native window behavior.

The [first macOS build at `0802bf0`](../qa/receipts/20261110/mac-0802-compile.json) failed before native tests: an ambiguous cancellation tuple, mixed chart numeric types, and a SceneKit options key type. The follow-up supplies explicit SDK types and preserves the failure receipt. These corrections require a new native build; the failed run completed zero native tests. The [separate macOS feature-map result](../qa/receipts/20261110/mac-0802-feature.json) passed 14 checks/682 tests and compiled the explanation subset, where 83 individual tests passed and eight history fixtures failed with `unsafePath`. The fixture-only follow-up uses POSIX `realpath`, following the existing Recordly/Wiki test pattern; production path rejection is unchanged. Its new no-symlink scratch guard and all 21 focused History tests passed on Linux, awaiting macOS confirmation.

Portable commands, from the repository root with Swift 6 and Python 3.11+:

```sh
python3 qa/portable-core/prepare.py --group explanation --run --jobs 2
python3 -m unittest discover -s qa/closed-loop/tests -v
bash scripts/check-settings-catalog.sh
./tools/check.sh development --jobs 2
```

On a supported Mac, compile production and test targets, then use the full gate for the owned AppKit fixture processes:

```sh
swift build --jobs 2
swift test --jobs 2 --filter ExplanationProtocolTests
./tools/check.sh full --jobs 2
```

These commands do not install, sign, notarize or grant capture consent. Full mode is expected to remain red while required device/release obligations are missing. A narrower passing suite must never be relabelled as a complete app test.

For an owner-supervised demo after an exact native build is approved: enable the feature; connect a model; start in typed caption mode; generate and edit a small diagram; advance/stop/replay; switch to a 3D illustration; undo/redo; save and reopen the linked Chat; test unavailable providers and denied permissions; then, only with the owner's OS consent, test microphone input, actual narration interruption and a selected-display snapshot. Automated production-control drivers must assert these visible outcomes; the sequence is not completed manual-QA evidence.

Unverified: the new feature's complete native build and execution; real provider/ASR/TTS quality and latency; native Chat onboarding/accessibility/keyboard journeys; microphone/device revocation and actual window/capture behavior; pixel-accurate motion and multi-display traces; signing/notarization/Gatekeeper; and measured CPU/GPU/memory/energy/frame pacing. The display-linked path requests up to 240 Hz where hardware supports it. A MacBook Pro built-in display cannot establish a 240 Hz minimum. No 240 FPS, Apple-equivalent quality, screen-reference parity or release-ready claim is made.

## Interactive 3D demonstrations (slice S3)

A scene can carry an optional `model` beside its objects: named parts, flows, callouts, one cutaway, and an animation rate. It is additive: scenes and events without it behave exactly as before, and the operations below are version-1 operations. The wire format stays closed (unknown keys and commands, bad numbers and oversized lines are refused) and carries no code, URL or shader.

Operations: `part` (group, box, cylinder, sphere or a `recipe`), `path` and `flow` (markers travelling along a named world-space polyline), `callout` (a text label anchored to a world point or to a part), `view` (camera preset, orbit degrees, zoom), `cutaway` (hide or fade named shell parts), `model` (caption, animation rate) and `edit` (change one part, flow or callout by id). `clear` also clears the model.

Part recipes are pure geometry in `ExplanationRecipes`, built into SceneKit nodes by `ExplanationModelRenderer`: `batteryPack` (eight modules in a floor tray), `inverterBox`, `motor` (stator teeth, rotor, shaft), `reductionGear` (an 8 tooth gear driving a 20 tooth gear), `halfShafts`, `wheel` (tyre, rim, hub, spokes) and `carShell` (body, glass cabin, roof, bumpers). Frame: +X forward, +Y up, +Z right, metres. Dimensions are plausible for a mid-size car and illustrative only; no real vehicle is modelled. Limits: 96 parts, 16 repeats and 160 instances, 1,200 solids, 12 paths of up to 32 points, 12 flows, 96 markers, 24 callouts of up to 60 bytes.

Edit semantics. `edit` and `cutaway` carry `expectedRevision`, which must equal the revision the beat builds on (its `baseRevision`). A missing target id or a stale revision throws `ExplanationFailure.editRejected`; the reducer is transactional, so the scene is unchanged. The controller ends the turn, keeps the last committed scene, counts it in `rejectedModelEdits` and shows a specific notice. A field that does not apply to the target (for example `speed` on a part) is also rejected. Creating an id that already exists is rejected, so a follow-up changes the same part instead of stacking a copy.

Speech sync. Cues use the existing playback admission, so parts appear or change when their beat's audio starts. Motion is separate from cues: `spin` on recipe parts and `flow` run on `ExplanationModelClock`, which integrates timestamps (not frames), caps a step at 0.25 s, scales by `animationRate` and keeps going from the present pose when the rate or a flow direction changes. Propulsion is a forward flow along the battery, inverter, motor path; regeneration is an `edit` that sets the same flow to `reverse`. Direction is defined against the path's point order in world space, and markers are cones aimed along the world tangent, so no camera rotation changes what an arrow means. Wheel spin is checked against rolling without slipping (`omega = n x v / r`).

Rendering. One display link runs only while a model has motion or the camera is turning, the view is visible, not occluded or minimised, and motion is not paused. Reduce Motion shows a static pose with arrows. Callout chips are projected every tick from the real camera pose and placed with the same rule as 2D labels (right, left, above, below; 4 point margins; never over an anchor); a label with no free slot is hidden.

The EV fixture, `examples/visual-explanation/ev-drivetrain.ndjson`, is labelled "Generic EV, explanatory animation, not an engineering simulation". `ExplanationEVReplayTests` decodes it and checks the scene after every beat and every follow-up.
