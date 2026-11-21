# Sweep 07 — Performance, memory, and energy

Lens: work on the main thread, timers and display links that run while idle, unbounded buffers, allocation inside a frame, polling beside an existing notification, the always-visible top bar, the launch path, audio copies, and budget tests for the numbers already named.

Read first: `specs/bugs/ledger.md` on `zeus-bot/bug-ledger` at `255e52aba94234e2b194fd81b2cf4b93e628cc93` (PR #54). Integration base: `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`.

This file is a static reading. This host cannot run the Mac app, Instruments, or a Metal device. Impacts below are what the source does on each cited line. The measurement plan is the check that confirms the size on a Mac. `ci_motion_profile.py` was not run.

## Heads read

| PR | Branch | SHA |
| --- | --- | --- |
| integration | `codex/integration-20261111` | `2722dcb7497d5415fbc1fcb1f65c49629966a281` |
| #54 | `zeus-bot/bug-ledger` | `255e52aba94234e2b194fd81b2cf4b93e628cc93` |
| #30 | `zeus-bot/local-voice-contract` | `329bfc2045ed2e7802331ef052468bfdc436f779` |
| #52 | `zeus-bot/companion-persona-orb` | `665b9167303f9596d5222b77a663e36f780d60d7` |
| #53 | `zeus-bot/voice-providers` | `16c2d697dcd479f6cbe510ad65fda731b82194fa` |
| #56 | `zeus-bot/media-playback-control` | `563a462830199b557e5cdecc9761d17e674f4ef9` |
| #64 | `zeus-bot/hub-03-transcript` | `0e4111c3abf5c906db5b7aef213f1bb13cebd2cf` |
| #65 | `zeus-bot/hub-07-experience` | `48b32bfef8e76362f280e6919784ec65150620a0` |
| #85 | `zeus-bot/topbar-idle-black` | `69f74b2f03ee5bba1259794012e76ffba334327f` |
| #87 | `zeus-bot/haru-companion` | `583c3dcc00e5e9456f9b3027765e2228e5409783` |

Findings cite that SHA plus the path and line `git grep` returned on that commit.

## Ledger rows re-read and not reopened

- **ZB-022** described unbounded electron spawn arrays on #52 at `762d5e47`. On #52 at `665b9167303f9596d5222b77a663e36f780d60d7`, `updateElectrons` keeps spawn times and speeds only for electrons that are still travelling (`Sources/ZeusCore/Companion/OrbSimulation.swift:450-465`). Not reopened.
- **ZB-023** described engines and temp files that were never stopped, on #53 at `30253774`. On #53 at `16c2d697dcd479f6cbe510ad65fda731b82194fa`, `WavFinish.complete` stops the engine, drops it, and deletes the file (`Sources/Zeus/Voice/PluginVoiceBridge.swift:83-91`). The leak is not reopened. The main-thread write that remains is **S07-13**.
- **ZB-033** is still present. It is **S07-12**, marked duplicate.

## Counts

| | Rows |
| --- | ---: |
| Findings | 16 |
| New | 15 |
| Duplicate of a ledger id | 1 (ZB-033) |
| P1, new | 8 |
| P2, new | 5 |
| P3, new | 2 |

## Findings

### S07-01

- **Severity:** P1
- **Where:** `zeus-bot/topbar-idle-black` `69f74b2f03ee5bba1259794012e76ffba334327f` `Sources/Zeus/TopBar/TopBarViews.swift:1459` and `Sources/Zeus/Companion/Orb/OrbMascotView.swift:24-26`
- **Owner:** #85, drawing the renderer from #52
- **What the source does:** The quiet bar's only mark, when the orb character is selected, is `OrbMascotView(visualState: .idle, reduceMotion: Motion.reduced, paused: false)`. The view sets `preferredFramesPerSecond = 120` and `isPaused = paused`. The quiet state is the always-visible bar (`Sources/Zeus/Notch/NotchView.swift:482-490` on the same commit). `PerformanceBudget.notchFPS` on integration is 60 (`Sources/ZeusCore/Performance/PerformanceBudget.swift:7` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`).
- **Expected impact:** With the orb character selected, the menu-bar process keeps a Metal view drawing at 120 Hz for the life of the session, including while the pointer is away and the panel is closed. That is the idle CPU and GPU of the always-visible bar. The companion idle budget is 1% of one core (`PerformanceBudget.idleCPUPercent`). A 120 Hz clear-and-present of the particle cloud sits above that budget on its own, before the solver cost in S07-02.
- **Measurement:** On a Mac, Instruments Time Profiler and Metal System Trace for 60 s. Pointer in the middle of the display, panel closed, no approval, no recording, no music, no dictation. Record two sessions: Reduce Motion off, then on. Report average CPU percent of one core (`ProcessEnergy.cpuPercent` over the same 60 s) and GPU time in `OrbMetalRenderer.draw`. Pass is at or under 1% of one core and a paused drawable. A unit test can assert the idle character passes `paused: true` while `TopBarIdleChrome` resolves `.idle`, and that the requested rate is at or under `PerformanceBudget.notchFPS`.

### S07-02

- **Severity:** P1
- **Where:** `zeus-bot/topbar-idle-black` `69f74b2f03ee5bba1259794012e76ffba334327f` `Sources/ZeusCore/Companion/OrbSimulation.swift:330`, `:384`, and `:400-428`. The same lines are on #52 `665b9167303f9596d5222b77a663e36f780d60d7`.
- **Owner:** #52. #85 is what leaves the solver running while the bar is quiet (S07-01).
- **What the source does:** Every fixed 60 Hz step calls `rebuildLines`. The idle target sets `lineAmount` to 0.15 (`OrbStateTargets` idle case, `:60-61`), and `rebuildLines` searches pairs while `lineAmount > 0.01`. The Reduce Motion branch returns early from particle motion and still calls `rebuildLines(bass: 0)` at `:330`. The search walks 2000 particles with stride `particleCount / 600` (3) and may allocate up to 8000 `OrbLine` values.
- **Expected impact:** About `(2000 / 3)² / 2` distance tests per step, 60 steps a second, on the thread that calls `renderFrame`. With S07-01 that thread is the view's draw callback, held under `NSLock` (S07-03). Reduce Motion does not remove the search. A quiet bar with the orb character selected spends main-thread time building a line list the idle pose barely shows.
- **Measurement:** A Swift test that calls `renderFrame` 60 times at `1/60` s for `.idle` and for Reduce Motion, and records `ContinuousClock` per call (the bench in `qa/orb-e2e/BenchMain.swift:161-173` already times `renderFrame` and does not fail on a millisecond budget). Fail a step whose wall time exceeds 2 ms, and fail a Reduce Motion step that still assigns `lines`. On a Mac, Time Profiler for 10 s on the quiet bar, sample weight in `rebuildLines`.

### S07-03

- **Severity:** P1
- **Where:** `zeus-bot/topbar-idle-black` `69f74b2f03ee5bba1259794012e76ffba334327f` `Sources/Zeus/Companion/Orb/OrbMetalRenderer.swift:137-152` and `:209-223`. Same lines on #52 `665b9167303f9596d5222b77a663e36f780d60d7`.
- **Owner:** #52, shown for the life of the bar by #85
- **What the source does:** `draw(in:)` runs on the view callback. It takes `CACurrentMediaTime`, locks, calls `renderFrame` (S07-02), then `let snapshot = simulation`, then unlocks. `upload` writes every particle and every live line into shared Metal buffers with a per-element loop. `MTKView` presents at the 120 Hz preference from S07-01, so the upload runs twice as often as the 60 Hz solver.
- **Expected impact:** One draw copies the particle storage (2000 particles, 7 `Double` fields) once the snapshot and the next mutation diverge, then writes 6000 floats, plus the line floats. That allocation and the lock sit on the main thread for every presented frame. The notch's other lights deliberately tick at 24 Hz (`Sources/Zeus/Notch/NotchLights.swift:57-78` on integration `2722dcb7497d5415fbc1fcb1f65c49629966a281`) so a soft glow stays cheap. The orb does not share that cap.
- **Measurement:** Instruments Allocations, filter to `OrbParticle` and `OrbLine`, 10 s quiet bar. Time Profiler, weight of `OrbMetalRenderer.draw` and `upload` on the main thread. A test can keep one `MTLBuffer` and write particles in place, and assert `draw` does not construct a second `OrbSimulation` value per frame.

### S07-04

- **Severity:** P1
- **Where:** `zeus-bot/topbar-idle-black` `69f74b2f03ee5bba1259794012e76ffba334327f` `Sources/Zeus/Companion/Orb/OrbMetalRenderer.swift:112-118`. `OrbMascotView.makeNSView` constructs the renderer (`Sources/Zeus/Companion/Orb/OrbMascotView.swift:16-19`). Same lines on #52 `665b9167303f9596d5222b77a663e36f780d60d7`.
- **Owner:** #52. On #85 the first quiet frame of an orb character is this call.
- **What the source does:** `init` calls `device.makeLibrary(source:options:)` with the shader string in `OrbMetalLibrary.source`. `makeNSView` runs on the main thread. The comment in the file says the library is compiled at runtime so `Package.swift` gains no Metal build step.
- **Expected impact:** The first time the quiet bar shows the orb character, the main thread compiles two vertex functions and two fragment functions before the first drawable. That interval is inside the cold-launch path: `applicationDidFinishLaunching` starts the notch at `Sources/Zeus/App/AppDelegate.swift:143` (`2722dcb7497d5415fbc1fcb1f65c49629966a281`), and #85 then builds this view for the closed bar. The companion launch budget is 800 ms to the notch being ready (`specs/007-companion-parity/perf-budgets.md` on #38). A source compile is a single hitch on that budget and on the first frame.
- **Measurement:** `os_signpost` around `OrbMetalRenderer.init` on a cold launch with the orb character already selected. Record 10 launches. Fail when the compile interval exceeds 100 ms. Ship a compiled `.metallib` in the bundle and keep the source path for the missing-device disc only.

### S07-05

- **Severity:** P1
- **Where:** `zeus-bot/companion-persona-orb` `665b9167303f9596d5222b77a663e36f780d60d7` `Sources/Zeus/Voice/UltronAudioChain.swift:230-255` and `Sources/ZeusCore/Companion/OrbAudio.swift:43-71`
- **Owner:** #52
- **What the source does:** `schedule` converts the buffer, then `publishOrbBands` before `scheduleBuffer`. For the orb persona it reads `PersonaCatalog.current()` (UserDefaults, `Sources/ZeusCore/Companion/Persona.swift:53`), allocates a new `[Float]` of up to 256 samples, copies them one by one, and calls `OrbAnalyser.smoothed`. `magnitude` is a direct transform: for each of 24 bins it walks every sample with `sin` and `cos`. `fadeEdges` (`UltronAudioChain.swift:260-267`) also copies a whole buffer into an `Array` and writes it back when a sentence edge is faded.
- **Expected impact:** Every playback buffer pays a heap copy and about `24 × 256` trig calls on the actor that schedules audio, before the buffer is queued. During speech that is the voice path the first-audio budgets are written against. Classic skips the transform. The orb persona does not.
- **Measurement:** A unit test feeds 256 samples and asserts `smoothed` stays under 0.5 ms on `ContinuousClock`, with the persona flag passed in so the test does not touch `UserDefaults`. On a Mac, a signpost `orb.bands` around `publishOrbBands` during a 10 s spoken reply. Time Profiler weight must sit under the scheduling of the buffer itself. Replace the direct transform with one real FFT of size 256, and publish bands from the meter the render thread already reads.

### S07-06

- **Severity:** P1
- **Where:** `zeus-bot/voice-providers` `16c2d697dcd479f6cbe510ad65fda731b82194fa` `Sources/ZeusCore/Providers/VoiceProviderSession.swift:343-368` and `Sources/Zeus/Voice/PluginVoiceBridge.swift:146-152`. The cloud adapter's body is one payload at `Sources/ZeusCore/Providers/GoogleCloudTTSAdapter.swift:63-79`, while the descriptor claims `.streamingSynthesis` at `:21`.
- **Owner:** #53. The budgets it misses are named on #38 and in `Sources/ZeusCore/Voice/VoiceLatencyTrace.swift` (voice leg 600 ms, direct stream p95 on the companion sheet).
- **What the source does:** `speak` appends every chunk into one `Data` and returns only after the stream finishes. `signposter.end` runs when the first chunk arrives, and `metDirectStreamP95` is computed from that timestamp. `PluginVoiceBridge.speak` then calls `PluginAudioPlay.play` with the finished buffer. `GoogleCloudTTSAdapter` waits for `transport.send` (the whole HTTP body), base64-decodes `audioContent` into a second `Data`, and yields one chunk.
- **Expected impact:** The number recorded as first audio is the first network byte. The speaker hears nothing until the full clip has been concatenated, copied again into the player, and started. A turn can pass `metDirectStreamP95` and still miss the heard-audio budget by the rest of the download plus the main-actor start in S07-13. `audio.append` also grows by copying.
- **Measurement:** A fake transport that yields two chunks 200 ms apart. Assert `PluginAudioPlay.play` is entered after chunk 1, while chunk 2 is still pending, and that a new signpost `voice.first-sample` ends inside `play`, not inside the collector loop. On a Mac, Instruments time profile of one spoken sentence: the gap from `voice.first-audio` to the first render callback of the player. Fail the voice-leg budget on the render callback, not on the first chunk.

### S07-07

- **Severity:** P1
- **Where:** `zeus-bot/companion-persona-orb` `665b9167303f9596d5222b77a663e36f780d60d7` `qa/orb-e2e/reportlib.py:136-151` and `qa/orb-e2e/runner.py:241-242`. The frame timer is `qa/orb-e2e/BenchMain.swift:161-173`.
- **Owner:** #52. The 1% and 150 MB numbers are `PerformanceBudget` on integration and the companion sheet on #38.
- **What the source does:** `sample_idle` starts `sleep`, samples that process, and returns subject `"sleep"`. `case_idle` requires `percent < 1.0` and stores the result. The Swift bench times 30 calls of `renderFrame` and writes the durations. It does not run `OrbMetalRenderer`, does not construct `IdleCharacterMark`, and does not compare a duration to a fail threshold. The spec (`specs/007-companion-parity/e2e-mac-orb.md`) says a host that cannot launch the app records `subject: sleep`.
- **Expected impact:** The idle-CPU case passes while Zeus is not the process under the sample. A green `budget.idle_cpu_and_memory` does not bound the quiet bar in S07-01 or the solver in S07-02. The frame report can show multi-millisecond `renderFrame` times and still exit 0, because only the journey assertions gate the process.
- **Measurement:** Point `sample_idle` at the Zeus pid from the clone's built binary. Fail the case when `subject` is `sleep`. Add an assertion in `BenchMain` that every idle and Reduce Motion sample at 60 Hz is under 2 ms (S07-02). On a Mac, run `scripts/check-perf-budget.sh` with that pid for 60 s after the bar has been quiet for 10 s. The script already compares to the 1% budget. It is not called by `qa/orb-e2e/run.sh`.

### S07-08

- **Severity:** P1
- **Where:** `zeus-bot/hub-07-experience` `48b32bfef8e76362f280e6919784ec65150620a0` `Sources/ZeusCore/AgentHub/HubExperience.swift:70-75` and `:164-186`, tests at `Tests/ZeusCoreTests/AgentHub/HubExperienceTests.swift:60-98`. Integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` `Tests/ZeusCoreTests/PerformanceTests.swift:36-38` and `Sources/ZeusCore/Performance/PerformanceBudget.swift:5-7`. The companion sheet that names the same 1%, 150 MB, and 800 ms launch figures is `specs/007-companion-parity/perf-budgets.md` on #38, which states that no number in that file was measured.
- **Owner:** #65 for the hub open and idle figures. The shared 1% and launch figures belong to the top bar and the companion, on integration and #38.
- **What the source does:** `openBudgetMilliseconds` is 100 and `idleBudgetPercentOfOneCore` is 1. `meetsOpenBudget` and `meetsIdleBudget` compare a number the caller passes in. The tests pass `100` and `1` and expect the predicate to hold. `PerformanceTests.energySampleReadsThisProcess` checks that a synthetic 0.5% difference computes as 0.5. It never samples a 60 s idle window, never opens a hub, and never compares a live percent to `idleCPUPercent`. #65's file comment says the type does not draw, move focus, schedule a timer, or read a socket. The one-second clock and the wave display link exist only as fields on `HubIdleSample`.
- **Expected impact:** The hub can take longer than 100 ms to open, and a closed hub can sit above 1% of one core, with these tests still green. The idle predicate is ready for a sample nobody collects. The same gap covers the companion launch budget of 800 ms: no test signposts `applicationDidFinishLaunching`.
- **Measurement:** A Mac test host opens the hub from a click and records `os_signpost` `hub.open` until the first frame. Fail above 100 ms. With the panel closed, no approval, no socket read, sample `ProcessEnergy` twice 60 s apart and fail when `cpuPercent` is over 1 or when a one-second timer or a wave display link is scheduled. Add the same 60 s sample to `PerformanceTests` behind a Mac-only tag. Cold-launch signpost `companion.launch` from process start to notch ready, 10 launches, fail p95 above 1200 ms.

### S07-09

- **Severity:** P1
- **Where:** integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` `Sources/Zeus/App/AppDelegate.swift:122`, `:179`, and `:318`; `Sources/Zeus/Dictation/DictationController.swift:370-374` and `:483-485`; `Sources/ZeusCore/Dictation/DictationCore.swift:243-246` and `:263-277`; `Sources/Zeus/Brain/PersonalityAssets.swift:17-23`; `Sources/Zeus/App/CommandCenter.swift:597-606`
- **Owner:** launch path on integration. Dictation history is the part that grows with use.
- **What the source does:** `applicationDidFinishLaunching` calls `PersonalityAssets.installDialogue()` on the main thread before the status item. That reads `ultron_dialogue.json` (28368 bytes in the tree) and decodes it. After the notch starts, `dictation.start()` calls `reloadModesAndHistory()`, which calls `loadHistory`. `loadHistory` lists every history folder, reads every `meta.json`, and builds a new `JSONDecoder` per file (`decoder()` at `:243`), then keeps 50 records. `CLIInstaller.install()` copies the helper binary on the main thread when the installed copy differs.
- **Expected impact:** Launch stalls on the main thread in proportion to the dictation history, not in proportion to the 50 rows the bar shows. A directory of a few hundred meetings decodes that many JSON files before the run loop is free to draw. The dialogue decode and the helper copy are smaller and still sit on the same critical path as the 800 ms launch budget.
- **Measurement:** Signposts `launch.dialogue`, `launch.dictation-history`, and `launch.helper-copy` inside `applicationDidFinishLaunching`. A fixture directory of 500 `meta.json` files, timed on the caller of `loadHistory`. Fail when the call exceeds 50 ms, and move the scan off the main actor, stopping once 50 valid records are in hand. Reuse one `JSONDecoder`. On a Mac, 10 cold launches with an empty history and 10 with the 500-file fixture. The p95 of `companion.launch` stays under 1200 ms on the empty fixture. The fixture's extra time must show up in `launch.dictation-history` and not in the first frame of the bar.

### S07-10

- **Severity:** P2
- **Where:** integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` `Sources/Zeus/TopBar/TopBarServices.swift:92-96` and `:118-137`
- **Owner:** top bar on integration. `start()` is called from `AppDelegate.swift:159-162` and the timers live until the process exits.
- **What the source does:** `observeClipboard` schedules `every(0.5)` on `RunLoop.main` in `.common`. Each fire reads `NSPasteboard.general.changeCount`. When the count changes, `checkClipboard` reads types and calls `ClipboardMedia.read` on the main actor, including the image branch.
- **Expected impact:** The always-visible bar wakes the main thread twice a second for the life of the process, including while the bar is quiet and the pasteboard is unchanged. A copied image is decoded on that same wake. Volume changes in the same file use an audio property listener (`:208-240`). The pasteboard path does not.
- **Measurement:** Instruments Time Profiler, 60 s, quiet bar, no copies. Count main-thread wakes whose stack includes `checkClipboard`. A quiet minute should show zero pasteboard work. Then copy a large image and confirm the decode is off the main actor. A test can drive `checkClipboard` from a change callback and assert the 0.5 s timer is absent while the bar is idle.

### S07-11

- **Severity:** P3
- **Where:** integration `2722dcb7497d5415fbc1fcb1f65c49629966a281` `Sources/Zeus/TopBar/TopBarServices.swift:72-79` and `:272-293`, beside `Sources/Zeus/TopBar/PowerMonitor.swift:31-44`
- **Owner:** top bar on integration
- **What the source does:** `start()` calls `pollBattery()` immediately and again from `every(60)`. `pollBattery` copies the power-source blob and walks the list. `PowerMonitor.start` already installs `IOPSNotificationCreateRunLoopSource` and refreshes on that callback. The top-bar timer does not use that source.
- **Expected impact:** One extra main-thread wake a minute, plus a full power-source copy, for a value `PowerMonitor` already updates when IOKit posts. The cost is small next to S07-01. It is a poll standing next to a notification the process already knows how to take.
- **Measurement:** After `TopBarServices.start`, assert a single IOPS run-loop source and no `Timer` whose body calls `pollBattery`. Instruments, 5 quiet minutes, confirm the battery line changes when the adapter is plugged and that no 60 s timer fires `pollBattery`.

### S07-12

- **Severity:** P2
- **Duplicate of ZB-033**
- **Where:** `zeus-bot/media-playback-control` `563a462830199b557e5cdecc9761d17e674f4ef9` `Sources/Zeus/TopBar/MediaCommandCoordinator.swift:172-197` and `:249`. ZB-033 cites this function on the same SHA.
- **Owner:** #56
- **What the source does:** `openAndWait` is `@MainActor` via the coordinator. It starts the budget with `Date()`, waits on `NSWorkspace.openApplication`, and also `Task.sleep`s for `budget + 1` seconds without cancelling that sleep when the open callback wins. The clock used by the router is `Date().timeIntervalSinceReferenceDate` at `:249`. After the app opens, a loop calls `NSRunningApplication.runningApplications(withBundleIdentifier:)` every 50 ms until the launch budget (8 s) expires.
- **Expected impact:** A launch can fail because the wall clock jumped, which is the defect ZB-033 already records. On top of that, the wait polls the process list from the main actor up to about 160 times, and the uncanceled sleep keeps a task alive past the callback. The top bar is the always-visible window those main-actor wakes share.
- **Measurement:** The ledger's sketch stands: a monotonic clock for `started` and `clock()`, and cancel the sleep when the open callback arrives. Add a count of `runningApplications` calls. Time Profiler during one cold player launch: main-thread time in `openAndWait` should be the callback, not a 50 ms poll. A forward jump of the wall clock larger than 8 s must still accept a launch whose monotonic elapsed time is inside the budget.

### S07-13

- **Severity:** P2
- **Where:** `zeus-bot/voice-providers` `16c2d697dcd479f6cbe510ad65fda731b82194fa` `Sources/Zeus/Voice/PluginVoiceBridge.swift:6` and `:37-46`
- **Owner:** #53. This is the residual of ZB-023 after the finish handler started cleaning up. It is not a second copy of the leak.
- **What the source does:** `PluginAudioPlay` is `@MainActor`. `playWithEngine` builds a UUID temp URL, `wav.write`s the whole clip, opens it with `AVAudioFile`, creates an `AVAudioEngine`, and `engine.start()`s, all before the function returns.
- **Expected impact:** The first sample of a WAV reply waits on a file write and an engine start on the main thread. The notch cannot draw during that write. A multi-megabyte clip adds its disk time to the heard-audio gap in S07-06. MP3 uses `AVAudioPlayer(data:)`, which still constructs the player on the main actor.
- **Measurement:** Signpost `voice.play-start` from `play` entry to `engine.start` returning, recorded on a background queue. A test writes a 2 MB WAV and asserts the main actor's `play` call returns before the file hits disk, or that the write is inside `Task.detached`. Instruments File Activity during one provider sentence: the write should not sit on the main thread.

### S07-14

- **Severity:** P3
- **Where:** `zeus-bot/voice-providers` `16c2d697dcd479f6cbe510ad65fda731b82194fa` `Sources/ZeusCore/Providers/ProviderLog.swift:46-72`
- **Owner:** #53
- **What the source does:** `ProviderSignposter.end` appends a `ProviderSignpostSample` and never drops one. The session in `PluginVoiceBridge.sharedSession` keeps that poster for the life of the process (`PluginVoiceBridge.swift:125-143`). `sanitize` also compiles the metadata regular expression on every end (`:78`).
- **Expected impact:** One small struct per spoken turn, kept until quit. A long session of short replies grows the array without a bound. The regex compile is a smaller extra alloc on the same call. Neither dominates S07-06. Both are unbounded relative to a ring.
- **Measurement:** A test calls `end` 1000 times and asserts `samples.count` stays at a fixed cap (the flight recorder's ring is 2000, `Sources/ZeusCore/Diagnostics/FlightRecorder.swift:64` on integration). Hoist the regular expression to a stored value and assert `sanitize` does not construct one per call.

### S07-15

- **Severity:** P2
- **Where:** `zeus-bot/hub-03-transcript` `0e4111c3abf5c906db5b7aef213f1bb13cebd2cf` `Sources/ZeusCore/AgentHub/HubTranscript.swift:192-214`
- **Owner:** #64. ZB-030 on the same file is the permission and lock row. This row is the rewrite cost. It is not a duplicate of ZB-030.
- **What the source does:** `write` creates a directory, builds a new `JSONEncoder` with `.prettyPrinted` and `.sortedKeys`, encodes the whole transcript, and atomically replaces the file. `HubTranscript` has no line cap. `HubTranscriptDriver.apply` calls `write` whenever the effect says to.
- **Expected impact:** A finished turn rewrites every earlier line. Cost grows with the transcript, on whatever thread calls `apply`. Pretty-printed sorted JSON is larger and slower than a compact append. A long session keeps the full array in memory and writes it again at the next effect.
- **Measurement:** A test writes transcripts of 10, 100, and 1000 lines and records bytes written and `ContinuousClock` time. Fail when the 1000-line write exceeds 20 ms or when the byte count is the whole history rather than the new line. Call `apply` off the main actor from the hub. Instruments File Activity during a 200-line session: one write per finished turn, sized to the new line.

### S07-16

- **Severity:** P2
- **Where:** `zeus-bot/local-voice-contract` `329bfc2045ed2e7802331ef052468bfdc436f779` `Sources/ZeusCore/Voice/DuplexVoiceBackend.swift:6-17` and `:57-64`. `zeus-bot/haru-companion` `583c3dcc00e5e9456f9b3027765e2228e5409783` `native/haru-companion/src/engine.rs:247` and `native/haru-pipe/src/resample.rs:147-157`.
- **Owner:** #30 for the contract, #87 for the host that encodes a frame. The resampler is the pipe on #87.
- **What the source does:** `VoiceFrame` owns a `[Float]` of 3200 samples (133 ms at 24 kHz). `push` takes another `[Float]` and constructs a `VoiceFrame` to check the length, then returns a `VoiceFrame` by value. The Rust host, on every push, clones `frame.samples` into `ServerMessage::Frame` before encode. `resample_poly` calls `Polyphase::new` on every invocation, which designs the Kaiser window with a Bessel series (`firwin_kaiser`) and allocates the phase banks, then `process` allocates the output. `to_24k` of an already-24 kHz buffer still `to_vec`s it.
- **Expected impact:** Each duplex step copies 3200 floats across the Swift boundary and again into the encoded reply (about 12.8 KB of payload, plus the heap header, twice). A 48 kHz capture converted with `to_24k` per step redesigns the filter every 133 ms. For 44100→24000 the tap length is `10 × max(up, down)` after the gcd, which is hundreds of taps and a fresh design. The live engine does not call `to_24k` per push today. The public function is the one a duplex adapter will call, and it is not reusable.
- **Measurement:** A Rust bench of `to_24k` on 6400 samples at 48 kHz, once with a new `Polyphase` per call and once with a stored `Polyphase`. Fail the per-call design when it is more than a small fraction of the stored-bank time. A Swift test of `push` asserts the returned frame's storage is the backend buffer, not a third copy, by keeping the contract on `UnsafeBufferPointer` or a shared ring. Instruments Allocations during 30 s of duplex: persistent growth per step fails the turn memory ceiling on the companion sheet (400 MB with no local model, named on #38).

## Coverage notes

Surfaces read for this lens and left without a new row:

- Music notifications on integration (`MusicPlayerFeed.observeMusic`) already use player notifications and workspace launch/terminate notifications. The launch-time scripted read is bounded by a few delayed tries. The open-wait poll is S07-12.
- Volume in `TopBarServices` already uses a property listener. The clipboard and the battery timer are the two that do not (S07-10, S07-11).
- `DisplaySynchronizedView` drops its link when `wantsLink` is false (`paused`, Reduce Motion, or a reached deadline). The quiet notch outline uses that pause. The orb view does not (S07-01).
- `GlassBloom` ticks only for the open fade.
- `NotchLights` is absent unless something is lit, and then at 24 Hz.
- `FlightRecorder` is a fixed ring of 2000. It is the pattern S07-14 lacks.
- `AudioProcessMonitor` installs Core Audio listeners only while the equaliser is started.
- `ModelResidency` unloads on one idle timer. `PerformanceTests` covers that policy and not the 1% CPU figure (S07-08).
- Hub list, transcript view, and sound on #66, #68, and #63 are label and state machines. They do not schedule a timer. The missing measurement is S07-08. The transcript file rewrite is S07-15.
- ZB-027 (playback depth on #53) is a stuck-playing correctness bug. It is not restated here.
