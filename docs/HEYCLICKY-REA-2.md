# HeyClicky second pass: deep static teardown and Zeus parity matrix

Date: 2026-11-11. Builds on `HEYCLICKY-REA.md` (evidence E-001..E-040, same labels). Scope: HeyClicky 1.1.1 build 66 installed at `/Applications/HeyClicky.app` on Tony's Mac, inspected read-only: bundle files, strings in the main binary, Info.plist, defaults key names, the app's own runtime data (schema and timing numbers only), and secondary study material Tony downloaded. Nothing launched, modified, re-signed, injected or executed. No keys, tokens, voice IDs, prompts or code are reproduced; findings are paraphrased. This is competitive and interoperability analysis of an app Tony owns a copy of, not legal advice.

Labels: **Observed** (seen in an artifact), **Inferred** (reasoned from evidence), **Unknown**. Confidence H/M/L.

## 0. Evidence index (continues the first doc)

| ID | Evidence |
|---|---|
| E-041 | `Resources/clicky-draw-engine.js` (250 KB, header and API surface read as data; "lab engine 1.6"). Copy under `~/AI-Brain-build/heyclicky-rea/bundle-assets-1111/`, never run. |
| E-042 | `Resources/clicky-draw-native.js` (header and host function list). Same folder. |
| E-043 | `Resources/clicky-draw-pieces.js` (header, helper names). Same folder. |
| E-044 | `Resources/clicky-three.js` (header: a slice of three.js 0.186.1) and `clicky-three-parts.js` (header and recipe contract). Same folder. |
| E-045 | Main binary `Contents/MacOS/HeyClicky`: linked frameworks (`otool -L`) and Swift class names found in its strings (`strings-main.txt` in the heyclicky-rea folder). |
| E-046 | Main binary strings: realtime voice client (events, config names, log lines). |
| E-047 | Main binary strings: visual tag names and their regex patterns, guided-walkthrough follow-up wording. |
| E-048 | Main binary strings: hostnames and route names (host names only here). |
| E-049 | Fresh read of `Info.plist` (secrets omitted) and `codesign` output. |
| E-050 | `~/Library/Application Support/Clicky/OneBrain/*/*.jsonl` and `threads/*.json`: record schema and timing/cost numbers only, no content. |
| E-051 | `defaults read com.humansongs.clicky`: key names and value types only; two non-personal values read (hotkey config, remote-config link keys). |
| E-052 | `~/Library/Caches/com.humansongs.clicky/Cache.db` (copied to a temp dir, queried read-only): request hosts and path shapes only. |
| E-053 | Main binary strings: the agent "note" card markup spec (object names). |
| E-054 | Tony's Downloads study material (secondary, untrusted): `HeyClicky_Complete_Rebuild_and_Project_Handoff`, `Metis-2 3.0-Upgrade-Kit-r11/clicky-study`, `Metis_2_12_Rebuild 2/CLICKY_METIS_2_12_EXTENSION.md`. |
| E-055 | Zeus code survey (headers, greps) under `~/AI-Brain-build/zeus-work-1111/Sources`. Not run. |
| E-056 | `Resources/ClickyModelInstructions.md` and the bundled skill folders (names, purpose). |

Version caution (Observed, E-051, E-052): the app holds a pending update record from 1.1.1 to 1.1.3 and a 192 MB downloaded updater image in the Sparkle cache. Everything below is 1.1.1 build 66 only. The study material in E-054 was made from an older build (1.0.51, build 61) per its own text.

## 1. Answers to the main questions

### 1.1 How drawings and screen annotations are rendered

**Observed (H, E-041, E-042, E-043, E-045).** Drawings are native, not a web view. A drawing engine written in JavaScript (an SVG-painting library) runs inside JavaScriptCore in the app process. There is no browser: a small shim file supplies the slice of the SVG DOM the engine uses (elements, attributes, CSS animation strings, bounding-box and path-length queries) and records what the engine paints. The Swift app drains those records after each call and draws them with Core Animation layers, using the same geometry, easing curves and colours a browser would. Text widths come from Core Text. The Swift class names match this design (a canvas view, scene, node, renderer and a pen mask, plus a native painter, a stale-watch, a pen-follower, a photo loader, pinned cards and a live caption). The JS context has no network or file access beyond a few host functions, because the program is model-written code.

**Observed (H, E-041).** The engine's own header says the model sends a drawing either as data (marks) or as a tiny program that makes marks. Features seen: tapered hand-drawn pen strokes, wobbly shapes, watercolour washes, handwriting, highlighter, a pen-reveal animation in drawing order, dashed lines, a layout check that nudges overlapping labelled boxes, anchored pieces (graph, timeline), pacing of strokes to speech, `finishNow`, per-mark placement times, parts with ids and an edit API (recolor, restyle, move, moveTo, scale, erase, redraw, add, highlight, undo), and pause/resume for a barge-in. Erasing runs the pen backwards.

**Observed (H, E-043).** The helper vocabulary that model programs use sits on top of the engine: marks for a real screen (ring, frame, underline, point, label, highlight, trace, connect, spotlight, typeText, onScreen), paper-style cards (paper, sticky, receipt, clipping, tape, photo), and bits like button, check, cross, sources, nextQuestions, waitForUser, lessonTitle, plan. The file says the API is described to the model in a server-side file that is not in the bundle (Unknown: its text).

**Observed (H, E-043).** On the real screen, marks are drawn in the user's cursor colour (the defaults key shows a red hex) with a soft glow, names in solid pills, steps as numbered badges, regions as dashed tinted frames. Sizes are in screen points, so the look matches across displays. A host hook picks white or dark ink per background spot.

**Observed (M, E-043, E-042).** Several host switches (`hostDrawsPointers`, buttons, windows, marquee) show that the app itself draws pointer, button and window chrome as native views while the engine only reports marks with a role. Click-wait rings are native.

### 1.2 Charts

**Observed (H, E-041).** The engine API has `graph()` and `timeline()` pieces (axes, curves, shifts, crossings, marked points) drawn in the same hand-made style. **Observed (H, E-053).** Separately, background-agent "note" cards have a chart object (one number per option, drawn as hand bars) and figures, tables, tickets, receipts and so on, composed by the app from a small markdown dialect. So charts are native drawings, not a chart library or a web chart. The Charts framework is linked (E-045) but Unknown whether it is used for charts; the hand-drawn evidence says the visible charts are engine drawings. Bounded negative: no Chart.js, D3 or Vega string was searched exhaustively in the 115 MB binary; the only JS in the bundle is the five files above.

### 1.3 3D scenes

**Observed (H, E-044, E-045).** 3D is native Metal fed by a three.js geometry kernel running in a separate JavaScriptCore context on a background queue. `clicky-three.js` is a bundled slice of three.js 0.186.1 (MIT, credited in its header). `clicky-three-parts.js` builds each part a `figure()` program asks for (sizes, axis, stretch, bevelled lathes, springs and so on) into vertex, normal, uv and index arrays plus samples, with a hard vertex cap per part. The header says these arrays are what "the Metal stage draws". Swift classes `ScreenDrawing3DStage`, `ScreenDrawing3DRenderers`, `ScreenDrawing3DHandle` and `ClickyThreeKernel` exist. Metal and MetalKit are linked; SceneKit and RealityKit are not in the linked list. So three.js here is used as a geometry builder only, not as a renderer, and there is no WebGL.

**Observed (M, E-041, E-044).** The engine exposes `figure`, `scene3d` and a 3D card path; recipes are plain JSON (kind plus numeric options) that the part builder consumes. The onboarding prompt text mentions building the third card as a 3D figure when the subject has real shape (paraphrase). Exact recipe kinds list: Unknown beyond what the parts file shows; the file is readable and listed in the heyclicky-rea folder.

### 1.4 Photos

**Observed (H, E-047, E-053).** An `[IMAGES:...]` tag and a `photo(...)` drawing helper exist. The strings show a log line that a Brave request was fired for the query, a count of results, and a card widget for images, stock prices and places. The agent card dialect has a photo object with a search query. So photos are retrieved by web image search (Brave host family, not verified by a request here: **Inferred** M from log strings; Observed hostname list in E-048 does not include a Brave host, so the call likely goes through the first-party worker route, Unknown). A `ScreenDrawingPhotoLoader` class exists. Favicons come from a public icon service (host in E-048).

### 1.5 Input stack and shortcuts

**Observed (H, E-045, E-046).** The push-to-talk monitor uses a modifier and mouse event tap (error strings name an event tap run loop source) with global NSEvent monitors also present. A double-tap-of-a-modifier trigger exists. The hands-free dictation default stored on this Mac is a double-tap of a two-modifier mask equal to Control plus Fn (E-051, mask value decoded: **Inferred** M). Distinct shortcut slots by name: voice hold, dictation hold, hands-free dictation, text trigger. Whether the voice-hold default is Control+Option as in the open-source app: **Unknown** (the key is absent from defaults, so it is at default; a code default was not read).

### 1.6 Capture API and window exclusion

**Observed (H, E-045).** ScreenCaptureKit is linked and strings show `SCContentFilter` with window exclusion, `SCScreenshotManager` capture-with-filter and `SCStream` delegates. A Settings compatibility mode for screenshots exists, with a log line that a hotkey summon exits it (issue number in the string). `sharingType` appears in the strings (set on some window). Which windows get `sharingType`: **Unknown**; the live kit logs each overlay window's sharing state. Screenshots are sent to the model as images, and the realtime path prunes stale screenshots and keeps only the latest (log string, E-046).

### 1.7 STT and TTS providers

**Observed (H, E-046, E-048, E-045).**
- Speech to text: a WebSocket to a streaming provider whose host is in the binary (api.deepgram.com, model name nova-3 present), with a short-lived token minted by the first-party worker (route `/v2/dictation/deepgram-token`); a fallback transcription route on the worker; Apple Speech is linked. A server-side cleanup route for dictation also exists.
- Voice out and in for conversation: OpenAI Realtime over WebSocket (host api.openai.com, model names with "realtime" in the binary), with an ephemeral session minted by the worker (route `/agent/realtime/session`). Voices are the realtime voice names (ten preview clips in Resources); the app also has other named preview clips (Inferred L: a second TTS source for non-realtime lines; **Unknown** which).
- Streaming formats: the realtime WebSocket carries JSON events with audio deltas and transcript deltas (event names in E-046). The agent link is a local HTTP server-sent-events stream on loopback (383 cached `/events` requests in the cache database, E-052) plus POST routes `/turn` and `/steer`. The first-party brain route streams too (first-token log lines), format **Unknown** (SSE vs NDJSON; both strings exist, so no inference).

### 1.8 How the model's output becomes drawing commands

**Observed (H, E-050, E-043, E-046).** There is a "one brain" model path (route `/brain/turn`, reported model in the runtime data is a GPT-family name for all 26 recorded rounds) that returns, per round, a short fact line, a words field, and a `code` field that is a JavaScript program. Function names in 28 stored programs (call counts, no content): `step`, `say`, `box`, `arrow`, `seen`, `cyl`, `rect`, `text`, `label`, `frame`, `typeText`, `cone`, `button`, `lessonTitle`, `figure`, `photo`, `capsule`, `torus`, `pipe`, `pulse`, `view`, `sources`, `paper`. So the contract is: the model writes code in the engine's tiny vocabulary; `step(n)` starts a beat, `say("...")` is the spoken line for that beat, drawing calls are the marks, and `seen(...)` is a note of what the model saw on screen. Threads also store a `drawing_code` list and the canvas size (E-050).

**Observed (H, E-047).** For simple pointing and click-guidance turns there is a second, cheaper text protocol: a single leading or trailing tag. Tags: `[POINT:x,y:label[:screenN]]`, `[POINT:none]`, `[HOVER:x,y,r:label]`, `[TARGET:x,y,r:label]`, `[HIGHLIGHT:...]`, `[SHAPE:line|arrow|circle|curve|polygon:...]`, `[TYPE:x,y:label]<<< text >>>`, `[IMAGES:query]`. `TARGET` means "the user should click this" and the app observes the click, recaptures, and asks the model for the next step. The end-anchored `POINT` regex matches the open-source app's (E-004), so Clicky's tag lineage persists. Snap behaviour: logs say the app snaps the model's box to a detected control when it can, else keeps the model's box (E-047).

**Observed (M, E-046).** The visible words are spoken by a separate realtime "mouth" session, told to speak the drawing's lines verbatim, with a note to the voice that it should say nothing more. In drawing mode screenshots are not attached to the voice session, only to the brain.

### 1.9 Beat and speech sync, cancellation, barge-in

**Observed (H, E-041, E-045, E-046).**
- Sync: the engine can pace strokes to speech (strokes after a `say()` line are released while that line plays and spread across it) and the host can supply line times. A native class `RealtimeWalkthroughSync` logs "beat fractions", a draw lead and a release threshold at a playback fraction. So ink is released against real audio playback fraction (Inferred H from names and logs, not measured).
- Staleness: logs state that if the screen changed before a step showed, the step is dropped or re-asked ("screen changed before the step showed"), and `ScreenDrawingStaleWatch` exists. Actions wait until the drawing is told.
- Cancellation/barge-in: realtime logs show a cancel of the in-flight response, a clear of the input buffer, a truncate of the assistant item to match what was heard, separate gates for always-on speech versus barge-in speech (thresholds, speech-like seconds, peak), an echo-cancel (AEC) duplex engine probe with cached "zombie topology" verdicts, and demotion to a legacy pipeline when echo cancellation is not proven. Server VAD is configured with threshold, prefix padding, silence duration and interrupt-response flags. The drawing pen can pause for a barge-in and resume (engine header). Mouth connection health: a silent socket on line 1 triggers a reopen.
- Follow-ups: a guided click follow-up has a freshness rule (user acted while the model was thinking: recapture), a capped count of remaining click-to-advance turns, a rule not to re-point at an opener already shown, and "step away" when the foreground app changes.

### 1.10 Everything else in the bundle (map)

| Item | Finding | Label |
|---|---|---|
| App shell | Swift/SwiftUI/AppKit, universal Mach-O, LSUIElement true, min macOS 14.2 | Observed H (E-049) |
| Frameworks dir | Sentry, Sparkle only | Observed H |
| Helpers | `ClickyBrowserHost` (small, loopback and CFNetwork), `clicky-harness` (126 MB, universal) | Observed H |
| Agent runtime | `CodexRuntime/` plus `clicky-harness`; loopback local server with `/turn`, `/steer`, `/events`; Codex home under Application Support with SQLite, sessions, skills, auth file (not read) | Observed H (E-052), E-056 |
| Model catalog | `ClickyCodexModelCatalog.json` (722 KB) and model names in the binary including Claude and GPT families | Observed (names only) |
| Skills | `ClickyBundledSkills` (browser control, deploy), `ClickyIntegrationSkills` (11 SaaS apps), 30-odd markdown skill files (GitHub, Notion, Obsidian, Blender, Excalidraw, Maps, Spotify, Reminders, Notes, iMessage and more) | Observed H |
| Browser | MV3 extension plus native-messaging host; extension has a bubble and mark script (not studied here) | Observed (names) |
| URL schemes | `clicky`, `heyclicky` (auth) | Observed H |
| Usage strings | mic, speech, screen capture, Desktop/Documents/Downloads (reads the open document) | Observed H |
| Entitlements | `codesign` reports the entitlement blob invalid on this OS and says the OS ignores it; the first doc recorded a specific set at another time. Treat the set as **Unknown / conflicting**: re-read with `codesign -d --entitlements :- --xml` on a clean shell | Observed conflict |
| Updater | Sparkle, hourly checks, feed on a GitHub Pages host named under the open-source author's account (host `farzaa.github.io`) | Observed H |
| Third parties | Sentry, PostHog (US and EU hosts), a hosted auth and storage project, Mux (video), an icon service | Observed (hosts) |
| Sounds | about 80 short wavs: pen, highlighter, stamp, paper, whoosh, target ping, handwriting beds, agent launch/done | Observed H. Drawing has its own sound player class. |
| Fonts | two bundled OFL families named for the draw engine (handwriting and a sans) | Observed H |

## 2. Findings that change Zeus decisions

1. HeyClicky's visuals are native JS-in-JavaScriptCore plus Core Animation, and 3D is three.js geometry plus Metal. The first doc's "web view" guess (M-L) is **resolved**: no web view for drawings (Observed H).
2. The model emits executable code in a tiny DSL for rich scenes, and tags for simple point/click turns. Zeus's closed-schema NDJSON is safer (no code from the model). Parity does not require code execution.
3. A separate low-latency realtime voice does the talking while a slower vision model draws. Zeus has one pipeline: the gap is conversational latency and natural barge-in.
4. Ink is paced against real audio playback and dropped when the screen changed. Zeus already admits cues from real playback; staleness is partly covered.
5. Click-to-advance walkthroughs recapture after each click with freshness rules. Zeus has a walkthrough controller with a global click monitor; check depth against the rules in E-047.
6. Photos come from web search at answer time. Zeus allows only approved assets, so it cannot answer "show me a photo of ..." today.
7. Everything routes through a first-party worker with account sign-in, billing and analytics; Zeus uses user-held keys. Privacy posture can be a differentiator.

## 3. Verification of secondary study material (E-054)

| Claim in study material | Check against bundle | Result |
|---|---|---|
| Pen stroke duration `clamp(0.25 + L/1400, 0.3, 1.4)` s, reveal easing (0.35,0.2,0.55,0.95) | native engine file defines base 0.25, per 1400, min 0.3, max 1.4 and that easing | **Verified** (Observed H) |
| Pen travel: jump under 110 units adds nothing, else `min(0.55, 0.2 + d/2400)` | engine file has exactly this expression | **Verified** |
| Screen pen width 3.5 points | pieces file sets the pen at 3.5 points | **Verified** (value seen) |
| Follow-spring 0.2 s / damping 0.6, offset (35,25), flight lift `min(0.2d,80)` | not in these JS files (Swift side); equals open-source Clicky parameters from the first doc | **Unverified for 1.1.1**; plausible carry-over |
| Gesture trail numbers (8-unit activation, 350 ms dwell, 1 s fade) | Swift-side; not checked | **Unverified** |
| Bundle contains a `cua-driver` helper skill (study of 1.0.51) | not present in 1.1.1 Helpers or ClickyBundledSkills (browser skill and a deploy skill only) | **Not in this build** |
| Native Swift app, not Electron | matches (E-045, E-049) | **Verified** |
| Study date and build | 1.0.51 (61) vs installed 1.1.1 (66) | Older build; do not mix |

The handoff documents (an implementation brief for another repository) are plans, not evidence. Their Windows-derived numbers are used above only where re-observed in the macOS bundle.

## 4. Runtime data on this Mac (structure only, E-050, E-051, E-052)

- Application Support/Clicky: `OneBrain/<account>/` jsonl per session (record kinds `round`, `tools`, `interrupted`), `threads/` json (thread messages, `drawing_code`, canvas size, user-layer signature, token counts), `HeyClickyHistory/` messages and agent handoffs json, `HomeSpaceCache/` thread history, transcripts, a turn journal, `ClickyApps/<slug>/works.json`, `projects/` (agents and jobs with note files), `AgentHarness`, `BrowserBridge/connection.json`, `CodexHome` (SQLite state, sessions, skills, a config file, an auth file not read), a skill library cache, a computer-use policy file (YAML and a managed rego file).
- Round record fields: tool calls, async calls, computer actions, a usage block (input/output/cached/reasoning tokens, web searches, screenshot file reference, first-token ms, total ms, cost, reported model), a fact, words, code. Names only; contents were not read except function-name counts and numbers.
- Numbers, 26 recorded brain rounds on this Mac (Observed): median first token about 1.9 s (range 1.1 to 16 s), median total about 5.7 s (range 2.3 to 64 s), total cost 1.45 over the 26 rounds (about 0.056 each; unit shown as dollars in a format string, Inferred M). Small sample, one user, one day.
- Defaults: about 100 keys, mostly feature flags, migration markers, agent/routine state and permission snapshots. No credentials seen; device fingerprint and cached memory values were not read (value redacted).
- Cache database: 461 cached requests, 383 to a loopback event stream, 58 to the first-party worker (agent, brain, dictation, billing-plan and config routes), 7 to a hosted auth/storage project, favicons, one update feed. No cached JS, HTML or scene files: renderer assets come only from the bundle. 
- No cached 3D or scene file format exists on disk apart from stored program code (E-050).

## 5. Parity matrix

Zeus "today" is from code reading only (E-055), not a run. "Gap" ranks 1 (furthest behind) to 17 in the last column.

| # | Capability | HeyClicky: how (label) | Zeus today | Zeus must build | How Zeus can be better | Gap |
|---|---|---|---|---|---|---|
| 1 | Talk shortcut | Modifier event tap plus global monitors; hold-to-talk, double-tap hands-free, text trigger; recorded per-slot config (Observed H/M) | Listen-only CGEvent tap with NSEvent fallback, hold chord, idempotent start, re-enable on disable, spoil rules (Observed in code) | Hands-free double-tap and a typed-instead option; a first-run permission checklist | VoiceOver-safe default, visible permission state, no account needed | 14 |
| 2 | Pointing trail | Flying cursor; pen cursor follows the drawing pen (Observed class names; flight numbers Unverified) | `BuddyController` CADisplayLink bezier, marker flies on real first audio | Pen-following cursor while ink draws; pointer arrival tied to cue | Reduce Motion path; rect-aware landing; no random offsets | 11 |
| 3 | Gesture grounding | Records the user's drawn marks, scribbles and pauses as context ("the user drew ... marks in order") (Observed strings) | Show-me: hold left Command, circle, screenshot with the region outlined (`AnnotationController`); pointing trace type exists | Feed the gesture path (not only an outline) and dwell into the model context with capture ID | Deterministic gesture to AX target resolution and tests | 9 |
| 4 | Capture and window exclusion | ScreenCaptureKit filter with exclusion, screenshot compatibility mode, latest-only screenshot pruning (Observed) | `SCContentFilter` capture in `ExplanationScreenContext`/`ScreenCapture`; only the Notch panels set `sharingType`; explanation overlay level above menus (Observed) | Decide and test sharing state of the drawing overlay for screenshots and screen share (S8 in the kit); stale watch on window move | Overlay excluded by default and proven by a test; per-display capture with scale in context | 12 |
| 5 | Model contract | Code DSL (`step`, `say`, marks, `figure`, `photo`) from a "brain"; separate text tags for point/click turns (Observed H) | Closed-schema NDJSON scene events, no code, bounded stream, protocol v2 (Observed in code) | A short, documented beat/step grammar mapped onto existing events; tag-style fallback for weak models | No model-written code runs on the machine; every mark validated and grounded | 15 |
| 6 | Annotation primitives | ring, frame, underline, point, label, highlight, trace, connect, spotlight, typeText, step badges, click-wait ring; pen look with glow (Observed H) | point, ring, roundedRectangle, region, arrow, connector, underline, highlight, badge, label, card, chart, timeline, path, image (Observed) | `trace` (free path) and `typeText` equivalents; hand-drawn pen reveal style; spotlight dim | Keyboard-accessible hit regions already in canvas; contrast-aware ink; reduced-motion twin | 7 |
| 7 | Cards and layout | Paper cards with a layout checker that nudges overlapping boxes; pinned cards; draggable; agent notes as a markup dialect (Observed H) | `card` kind and `ExplanationPane`/`ExplanationCanvas` with layout, pure geometry (Observed) | Overlap nudging, pin and drag handles, note-card objects (stat, ticket, receipt, quiz) | Layout proven by tests; text measured once natively | 8 |
| 8 | Charts | Hand-drawn `graph()` pieces and bar charts in notes, native (Observed H) | `chart` and `timeline` kinds in the protocol (Observed) | Verify values render exactly; animated update on edit | Show source numbers beside bars; a self-check that heights match values | 13 |
| 9 | Photos | `photo()` and `[IMAGES]` with web image search, cards for images, stock, places (Observed H; search host Unknown) | `image` kind only with an approved `assetID` and provenance; no retrieval (Observed) | An opt-in retrieval adapter with source credit and licence field, hostnames allow-listed | Provenance and consent shown on every photo; no hotlinking of unknown hosts | 3 |
| 10 | 3D | three.js geometry kernel in JSC plus Metal stage; part recipes; orbit/rotate (Observed H for pipeline) | SceneKit renderer, bounded meshes, no actions or physics (Observed) | A part-recipe library (bevelled lathe, spring, pipe, torus, cone) as validated JSON; rotate, cutaway and speed edits by id | Same JSON on SceneKit now, Metal later; deterministic snapshot tests | 6 |
| 11 | Beat sync | `say()` lines paced against playback fraction; staleness drop (Observed H/M) | Cue admission from real playback; ElevenLabs word timings optional; start/end anchors (Observed) | Release strokes within a line across its audio; a drop-on-stale rule | Measured "first audio minus flight start" metric already planned; never estimate from word count | 10 |
| 12 | Barge-in | Realtime: server VAD, AEC duplex probe, always-on gate vs barge-in gate, response cancel plus truncate to heard text, pen pause/resume (Observed H) | New hold during speech stops speech and animation (generation checks); speech attempt policy discards late audio (Observed) | Voice-activity barge-in without a key (needs echo cancellation), pen pause/resume | Cancel proven by tests; no cloud round trip needed for the stop | 2 |
| 13 | Follow-up edits | Same picture edited by part id (recolor, move, scale, erase backwards, redraw, add, highlight, undo); mid-edit cut-in (Observed H, engine header) | Edit ops (update, move, recolor, highlight, label, animate, clear), history with undo/redo and checkpoints (Observed) | Part-id state summary returned to the model each turn; "erase" as reverse-ink; settle on interrupt | Persisted history with checkpoints beats RAM-only; edits validated by schema | 5 |
| 14 | Actions and approvals | Click-guided steps with click observation and recapture; agents act in browser and apps; confirm before delete/send; drafts until approved (Observed instructions, H) | Walkthrough controller with global click monitor; `Hands/` and approval gates exist in places (Observed) | Unify click-wait, wrong-click handling, step cap and freshness into one tested state machine | Every action proposal approved per action; secure-field refusal | 4 |
| 15 | Latency | Separate fast voice; brain first token median 1.9 s, total 5.7 s on this Mac (Observed small sample) | One vision call then per-beat TTS; ElevenLabs optional; no measured numbers yet | A latency harness (key-up to first audio, first ink); speech-first short answer while the picture builds | Publish a measured budget; local Kokoro/system fallback keeps working offline | 1 |
| 16 | Privacy and network | First-party worker for everything, account sign-in, billing, PostHog and Sentry, Mux; screenshots to cloud models; device fingerprint stored (Observed hosts/keys) | Keychain-held user keys, consent toggles, no telemetry intended (per plan; Observed in code seams) | Network allow-list shown in the UI; a "what was sent" log without content | Local-first, no account, no analytics, proof via the same observer kit pointed at Zeus | 16 |
| 17 | Cost | Plans (Pro/Max strings) and a credit system; observed model spend about 0.056 per brain round (small sample) | User pays providers directly; no per-turn cost meter seen | Per-turn cost and token readout; cheaper model for point-only turns | Visible cost, user caps, local models option | 17 |

Rows where Zeus is furthest behind, in order: latency (row 15), barge-in (row 12), photos (row 9), actions and click-walkthrough (row 14), follow-up part-id edits (row 13), 3D recipe library (row 10), annotation primitives and pen style (row 6), cards and layout (row 7), gesture grounding (row 3), beat sync (row 11).

## 6. What was not done / open

- No live behaviour (focus, click-through, real overlay levels, real sync, interrupt feel) was observed. The kit in `~/AI-Brain-build/heyclicky-rea/` (observe.sh, TEST-SCRIPT.md, analyze.py) is for Tony to run; its Swift watcher compiled here, `analyze.py --selftest` passed, observe.sh itself was only syntax-checked.
- Unknown: server-side drawing prompt, the worker's model routing, the photo search host, which TTS speaks non-realtime lines, the entitlement set (the OS reported the blob invalid), whether `sharingType` is used on the drawing overlay.
- Claims about Zeus are from reading code, not running it.
