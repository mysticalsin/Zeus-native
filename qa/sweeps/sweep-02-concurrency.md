# Sweep 02 — concurrency and lifecycle

Lens: MainActor isolation, data races, Sendable gaps, actor reentrancy, unstructured tasks and missing cancellation, retain cycles, observers and audio taps that are never removed, double start and stop, sleep and wake, display reconfiguration, and teardown order.

Base: `codex/integration-20261111` at `2722dcb7497d5415fbc1fcb1f65c49629966a281`.

Ledger read first: `specs/bugs/ledger.md` on `zeus-bot/bug-ledger` at `255e52aba94234e2b194fd81b2cf4b93e628cc93` (PR #54). Rows that are the same defect are marked `duplicate of ZB-xxx`. A ledger row whose cited head has since changed is noted in the crosswalk and is not re-filed.

## How this was established

This VM is Linux. The Zeus package does not build here (`mach`, CryptoKit, CoreGraphics). No finding was executed on a Mac, and no throwaway package was compiled: the defects sit in AppKit, AVFoundation, Core Audio, or actor code that is only reachable through that package.

Every row below was established by reading the named file at the named commit. "Needs a Mac" means the control flow is visible in source and the crash, stuck pump, or overlapping capture still has to be run on macOS.

Heads read for this lens:

| PR | Branch | SHA |
| --- | --- | --- |
| integration | `codex/integration-20261111` | `2722dcb7497d5415fbc1fcb1f65c49629966a281` |
| #30 | `zeus-bot/local-voice-contract` | `329bfc2045ed` |
| #33 | `zeus-bot/glass-settings-shell` | `d8fb8c2df661` |
| #39 | `zeus-bot/settings-general` | `2ef01f4a543d` |
| #51 | `zeus-bot/companion-turn-machine` | `ab0880462e65` |
| #52 | `zeus-bot/companion-persona-orb` | `665b9167303f` |
| #53 | `zeus-bot/voice-providers` | `16c2d697dcd4` |
| #56 | `zeus-bot/media-playback-control` | `563a46283019` |
| #57 | `zeus-bot/fix-topbar-core` | `3cde0156a0cf` |
| #58 | `zeus-bot/fix-license` | `10faecc83b32` |
| #59 | `zeus-bot/hub-01-types` | `c311990162db` |
| #62 | `zeus-bot/hub-02-session` | `b780b0b34312` |
| #63 | `zeus-bot/hub-06-sound` | `fcd6f3cebdbd` |
| #64 | `zeus-bot/hub-03-transcript` | `0e4111c3abf5` |
| #65 | `zeus-bot/hub-07-experience` | `48b32bfef8e7` |
| #66 | `zeus-bot/hub-09-transcript-view` | `12cb3137417c` |
| #67 | `zeus-bot/hub-05-screen` | `8babfef2818d` |
| #68 | `zeus-bot/hub-08-list` | `a0c853638b75` |
| #69 | `zeus-bot/hub-10-decision-view` | `837a34d37131` |
| #70 | `zeus-bot/hub-04-decision` | `7c000d3a8d58` |

## Ledger crosswalk

| Ledger | This sweep |
| --- | --- |
| ZB-011 | S02-19, duplicate. Shared `UserDefaults` under the parallel scribe package. |
| ZB-012 | S02-20, duplicate. `NSRegularExpression` built on every use from `SensitiveInfoScanner.wordList`. |
| ZB-014 | Not re-filed. On #51 `ab0880462e65`, `CompanionSystemClock` uses `ProcessInfo.processInfo.systemUptime`. |
| ZB-015 | S02-15, duplicate. Integration `NotchController.requestApproval` still leaves the timeout task unstored. #57 `3cde0156a0cf` adds `ApprovalWait` and tells the controller to keep and cancel that sleep. |
| ZB-022 | Not re-filed. On #52 `665b9167303f`, `OrbSimulation.updateElectrons` copies spawn times and speeds only for electrons that are still travelling. |
| ZB-023 | Not re-filed as the original defect. On #53 `16c2d697dcd4`, `WavFinish.complete` stops the engine and deletes the file, and `PluginAudioPlay.stop` resets the gate. The remaining hole is S02-09: nothing ends the gate when that completion never runs. |
| ZB-027 | S02-16, duplicate. `end` and `endPlayer` still no-op unless the token is the latest generation. |
| ZB-030 | S02-18, duplicate. `HubTranscriptStore.write` still has no lock and no `0o700` / `0o600`. |
| ZB-033 | S02-17, duplicate. `openAndWait` still times the launch with `Date()` and does not cancel the sleep task. |

ZB-024 and ZB-025 are license integrity, not this lens. #58 `10faecc83b32` adds `LicenseCredentialCommit`. On integration, `LicenseManager.syncWithServer` captures `credentialRevision` before its network await and drops the result when the revision moved. No new race was filed there.

## Findings

| ID | Sev | Where | Owner | Established |
| --- | --- | --- | --- | --- |
| S02-01 | P1 | integration `2722dcb7497d` `Sources/Zeus/Voice/WakeWordListener.swift:72` | Wake word | read, needs a Mac |
| S02-02 | P1 | #53 `16c2d697dcd4` `Sources/ZeusCore/Providers/VoiceProviderSession.swift:316` | #53 voice providers | read |
| S02-03 | P2 | integration `2722dcb7497d` `Sources/Zeus/Voice/UltronAudioChain.swift:279` | Voice output | read, needs a Mac |
| S02-04 | P2 | integration `2722dcb7497d` `Sources/Zeus/Scribe/ScribeLiveCapture.swift:86` | Scribe capture | read, needs a Mac |
| S02-05 | P2 | integration `2722dcb7497d` `Sources/Zeus/Voice/Speaker.swift:74` | Voice output | read |
| S02-06 | P2 | integration `2722dcb7497d` `Sources/Zeus/TopBar/TopBarServices.swift:238` | Top bar volume | read, needs a Mac |
| S02-07 | P2 | integration `2722dcb7497d` `Sources/Zeus/TopBar/TodayController.swift:236` | Reminders and alerts | read |
| S02-08 | P2 | integration `2722dcb7497d` `Sources/Zeus/Polyglot/PolyglotAudio.swift:133` | Polyglot capture | read, needs a Mac |
| S02-09 | P2 | #53 `16c2d697dcd4` `Sources/Zeus/Voice/PluginVoiceBridge.swift:50` | #53 voice providers | read, needs a Mac |
| S02-10 | P3 | integration `2722dcb7497d` `Sources/Zeus/Voice/HotkeyMonitor.swift:142` | Talk and dictation keys | read, needs a Mac |
| S02-11 | P3 | integration `2722dcb7497d` `Sources/Zeus/BrowserAgent/MCPStdioClient.swift:73` | Browser agent | read |
| S02-12 | P3 | integration `2722dcb7497d` `Sources/Zeus/Notch/NotchController.swift:104` | Launch observers | read |
| S02-13 | P3 | integration `2722dcb7497d` `Sources/Zeus/Notch/NotchController.swift:135` | Notch capture boost | read |
| S02-14 | P3 | integration `2722dcb7497d` `Sources/Zeus/FacePresence/FaceCamera.swift:100` | Face camera | read, needs a Mac |
| S02-15 | P3 | integration `2722dcb7497d` `Sources/Zeus/Notch/NotchController.swift:352` | Top bar approvals | read, needs a Mac. duplicate of ZB-015 |
| S02-16 | P1 | #53 `16c2d697dcd4` `Sources/ZeusCore/Providers/ProviderPlaybackGate.swift:36` | #53 voice providers | read. duplicate of ZB-027 |
| S02-17 | P2 | #56 `563a46283019` `Sources/Zeus/TopBar/MediaCommandCoordinator.swift:184` | #56 music | read, needs a Mac. duplicate of ZB-033 |
| S02-18 | P2 | #64 `0e4111c3abf5` `Sources/ZeusCore/AgentHub/HubTranscript.swift:192` | #64 hub transcript | read. duplicate of ZB-030 |
| S02-19 | P2 | integration `2722dcb7497d` `Tests/ZeusCoreTests/ScribeAutoStartOptInTests.swift:58` | Scribe | read. duplicate of ZB-011 |
| S02-20 | P2 | integration `2722dcb7497d` `Sources/ZeusCore/Wiki/SensitiveInfoScanner.swift:226` | Wiki export | read. duplicate of ZB-012 |

### S02-01 — Wake-word tap stays installed when the engine is already stopped

Severity: P1. Owner: wake word, integration.

`WakeWordListener.stop` (`WakeWordListener.swift:72-76`) removes the input tap only inside `if engine.isRunning`. `start` (`:65-69`) installs the tap before `engine.start()`. `WakeWordController.startListener` (`WakeWordController.swift:164-175`) catches a thrown start and never calls `stop` on that listener, then drops it. A later `stopListener` (`:193-196`) has the same hole once the system has already stopped the engine (sleep, unplug, route change).

The listener also never observes `AVAudioEngineConfigurationChange`. After a route change, `listener` stays non-nil, so `evaluate` (`:107`) does not start a new one, and the status stays "Listening".

Repro sketch: install a tap, throw from `engine.start()`, release the listener. On a Mac, releasing an `AVAudioEngine` that still has a tap is the crash to record. Second sketch: start listening, unplug the input, and assert the status is no longer "Listening" and a new `start` can install a tap. Needs a Mac.

### S02-02 — A provider speak keeps running after stop, and the next speak clears its cancel

Severity: P1. Owner: PR #53.

`VoiceProviderSession.speak` (`VoiceProviderSession.swift:316`) sets `speakCancelled = false` on entry. The only cancel check inside the chunk loop is that flag (`:347-348`). It does not read `Task.isCancelled`. `Speaker.stop` on that head (`Speaker.swift:182-189`) cancels the sentence pump and calls `PluginAudioPlay.stop()`, and does not call `VoiceProviderSession.cancel()`.

`PluginVoiceBridge.speak` (`PluginVoiceBridge.swift:149-152`) awaits the session and then calls `PluginAudioPlay.play` with no cancellation check. A cancelled pump task still runs the code after the await. Stop can tear the player down, and the in-flight speak can start it again.

A second `speak` can enter the actor while the first is suspended on `for try await`. The second call clears `speakCancelled`, so the first loop no longer observes the cancel that was meant for it.

Repro sketch: a session whose chunk stream yields across an await. Call `speak`, cancel the calling task, and call `speak` again before the first returns. Assert the first call returns `.cancelled` and does not call `play`, and that `speakCancelled` for the first call stays true. The actor interleaving does not need a device. Hearing the late audio needs a Mac.

### S02-03 — Stopping speech leaves the output engine running

Severity: P2. Owner: voice output, integration.

`UltronAudioChain.stop` (`UltronAudioChain.swift:279-285`) stops the player node and resets the pending count and the ledger. It never calls `engine.stop()`. The only `engine.stop()` in this file is the offline renderer (`:364`). `Speaker.prewarm` (`Speaker.swift:170-172`) says the output engine must not be open while capture opens, because that pulls a headset into its playback profile. After the first spoken answer, `stop` leaves that engine running into the next listen.

The configuration observer (`:191-194`) stops the player and resets counters, and it does not restart or stop the engine. The next `prepare` restarts only when `isRunning` is already false (`:221`).

Repro sketch: schedule one buffer, call `stop`, assert `engine.isRunning` is false before the next capture `start`. Needs a Mac.

### S02-04 — The next scribe capture opens the microphone before the previous one releases it

Severity: P2. Owner: scribe capture, integration.

`ScribeLiveCaptureProvider.start` (`ScribeLiveCapture.swift:80-87`) swaps `current` and calls `previous?.abandon()` and `run.begin()` back to back. `abandon` (`:265`) and `begin` (`:191`) each hop to their own serial queue. The new `startMic` (`:337`) installs a tap without waiting for the old `stopMic` (`:395`).

Two engines can hold the input until the old queue runs. A configuration-change notification on the old engine can then call `startMic` again (`:408-414`) after the new session has already started.

Repro sketch: start session A, start session B before A's queue has run `teardown`, and count live `AVAudioEngine` instances that have a tap installed. Expect one. Needs a Mac.

### S02-05 — Every speaker registers for the talk key and never unregisters

Severity: P2. Owner: voice output, integration.

`Speaker.init` (`Speaker.swift:74-76`) adds a `talkKeyPressed` observer and does not store the token. There is no `deinit`. The block is `[weak self]`, so the speaker can be released, and the observer stays in `NotificationCenter` for the process. Each press still schedules `Task { self?.prewarm() }`.

`GSVoiceCards.previewSpeaker` (`GSVoiceCards.swift:283`) is a second live `Speaker`. After the voice card is first touched, every talk-key press prewarms the turn speaker and the preview speaker. `prewarm` (`Speaker.swift:155-166`) starts cloud warm-up and `KokoroWorkerSession.shared.prewarm` for whichever route is first.

Repro sketch: create a `Speaker`, release it, post `talkKeyPressed`, and assert the observer count did not grow. Then load `previewSpeaker` and post the name once. Assert `prewarm` ran once, on the turn speaker. The observer count is readable without playing audio.

### S02-06 — Volume listeners are added for every output device and never removed

Severity: P2. Owner: top bar, integration.

`TopBarServices.observeVolume` (`TopBarServices.swift:208-214`) adds a default-device listener and never removes it. `attachVolumeListener` (`:217-241`) adds up to four `AudioObjectAddPropertyListenerBlock` listeners on the new device whenever `device != volumeDevice`. Nothing calls `AudioObjectRemovePropertyListenerBlock`. `stop` (`:87-90`) stops the music feeds and leaves these listeners in place.

Plug in headphones, then a display, then unplug them. Each old device still calls `volumeChanged` (`:262`), which reads the current default device. The HUD can flash for a volume change on a device that is no longer the output. Needs a Mac.

### S02-07 — A slower fetch writes reminders and alerts over a newer result

Severity: P2. Owner: reminders and alerts, integration.

`RemindersController.refresh` (`TodayController.swift:137-156`) starts `fetchReminders` with no generation. The callback assigns `items` on the main actor. `complete` (`:162-168`) removes a row only after the store accepts it. A fetch that started earlier puts that row back.

`NotificationsController.refresh` (`:232-248`) has the same shape. `enabled.didSet` (`:220-224`) calls `refresh()`. Turning the mirror off clears `items` in the synchronous branch, and an in-flight detached task then assigns `items` again.

`TopBarServices` (`TopBarServices.swift:376-381`) writes `model.reminders` from the same unguarded callback.

Repro sketch: start `refresh`, set `enabled = false`, resume the detached task, and assert `items` is empty. For reminders, complete one id while a fetch is in flight and assert that id stays absent. The notification sketch can be driven with a fake mirror; the reminder sketch needs EventKit on a Mac.

### S02-08 — Polyglot system capture stop does not finish before the next start

Severity: P2. Owner: polyglot, integration.

`PolyglotSystemCapture.stop` (`PolyglotAudio.swift:128-134`) nils `stream` and starts an unstructured `Task` that calls `stopCapture`. `PolyglotController.stop` (`PolyglotController.swift:149-159`) calls that `stop`, sets `system = nil`, and marks the run inactive. `start` (`:135`) is then allowed. The new `SCStream` can be capturing while the old `stopCapture` is still running.

`PolyglotMicCapture` (`:68-75`) and `PolyglotSystemCapture` have no `deinit`. Dropping either without `stop` leaves the tap or the stream up. The mic path does remove its tap when `stop` runs and `running` is true. A configuration change (`:63-65`) reports `onStopped` and does not itself remove the tap or clear `running`.

Repro sketch: `stop()` then `start()` on a system capture, and assert the previous stream's `stopCapture` has returned before `startCapture` on the next stream. Needs a Mac.

### S02-09 — Provider playback has no sleep or route teardown

Severity: P2. Owner: PR #53. This is the hole left after ZB-023's "engine is never stopped" on the older head. It is not the generation check in S02-16.

`PluginAudioPlay.play` (`PluginVoiceBridge.swift:13-22`) replaces `player` without stopping the previous `AVAudioPlayer` or ending that player's gate token. `playWithEngine` (`:37-52`) appends another `AVAudioEngine` and arms the gate with `begin()`. The token is ended only from `WavFinish.complete` (`:83-92`), which runs if the scheduled file's completion runs. There is no `AVAudioEngineConfigurationChange` observer and no sleep or wake observer.

Sleep or a route change can stop the engine without that completion. `Speaker`'s pump waits while `ProviderPlaybackGate.shared.isPlaying` (`Speaker.swift` on that head, the `holds` loop). The gate stays raised until some later `PluginAudioPlay.stop` calls `reset`. The rest of the answer does not start.

Repro sketch: `begin()` one WAV, stop the engine without calling `complete`, and assert `isPlaying` is false within one sentence gap. Needs a Mac for the engine. The missing observer is visible in the source.

### S02-10 — A second `HotkeyMonitor.start` delivers every key twice

Severity: P3. Owner: talk and dictation keys, integration.

`start` (`HotkeyMonitor.swift:142-156`) appends a local key monitor and a local mouse monitor on every call. `observeConsumedKeys` and `observeSleep` are guarded. `startGlobal` (`:162-170`) is not. `KeyListenAccess.whenGranted` (`:34`) runs the work immediately when access is already on, so a second `start` registers a second pair of global monitors.

Launch calls `start` once (`AppDelegate.swift:344`, `DictationController.swift:388`). A second call, or a future restart of those features, feeds each key-down to the talk machine twice. Needs a Mac to install the monitors. The unguarded append is visible in source.

### S02-11 — Releasing the browser client drops in-flight replies

Severity: P3. Owner: browser agent, integration.

`MCPStdioClient` is an actor. `request` (`MCPStdioClient.swift:197-211`) stores a `CheckedContinuation` in `pending` and starts an unstructured write task. `close` (`:156-164`) does resume those continuations through `failAll`. `deinit` (`:73-77`) stops the pipes and starts `finishChild`, and it does not resume `pending`.

`BrowserUseBackend.launch` closes a failed client (`BrowserUseBackend.swift:42`). A backend that is released without `close` while `callTool` is suspended drops the continuation. In a debug runtime that is a continuation misuse on the waiting task.

Repro sketch: start a client against a fake pipe, call `request`, release the actor without `close`, and assert the caller resumes with an error instead of hanging. The continuation path is Foundation and can be sketched without AVFoundation. This package still does not build on Linux.

### S02-12 — Several launch starts install observers every time, and some tokens are thrown away

Severity: P3. Owner: launch wiring, integration.

These starts are each called once from `AppDelegate.applicationDidFinishLaunching`. None of them is safe to call again, and the ones that discard the token cannot be torn down.

| Site | What a second call does |
| --- | --- |
| `NotchController.start` `NotchController.swift:75-120` | Appends more event monitors and installs screen, workspace, and distributed observers whose tokens are not stored. |
| `WakeWordController.start` `WakeWordController.swift:57-78` | Appends another lock, session, and sleep observer set, and schedules another timer without invalidating the first. |
| `RoutineRunner.start` `RoutineRunner.swift:45-48` | Overwrites `wakeObserver` without `removeObserver` on the previous token. Wake runs `runDue` once per leaked observer. |
| `ProactiveController.start` `ProactiveController.swift:39-50` | Appends another unlock and calendar observer. A second wake can file the morning brief twice. |
| `BuddyController.start` `BuddyController.swift:59-77` | Adds another `didChangeScreenParameters` observer on `self`, so one reconfiguration calls `screensChanged` twice, and appends more mouse monitors. The display link itself is replaced. |

`ScreenCornerOverlay.start` (`ScreenCornerOverlay.swift:29-30`) already refuses a second observer. These starts do not.

Repro sketch: call each `start` twice and assert one observer token and one timer. The notch, wake-word, routine, and buddy paths need a Mac for the real centers. The missing `removeObserver` is visible in source.

### S02-13 — The capture-visibility boost is an unstored task

Severity: P3. Owner: notch, integration.

`NotchController.boostCaptureVisibility` (`NotchController.swift:131-144`) sets every panel to `.readOnly` and sleeps in a new `Task` that is not stored. A second boost, or a settings change during the sleep, can be overwritten by the earlier task when it wakes and calls `applyScreenSharePolicy`. `Task.sleep` is cancelled only if that task is cancelled. Nothing holds it.

Repro sketch: boost for 5 seconds, then boost for 1 second. When the short task finishes, assert the panels are still in the boosted sharing mode until the long boost ends.

### S02-14 — A second face-camera start leaves interruption events on the old run

Severity: P3. Owner: face presence, integration.

`FaceCamera.start` (`FaceCamera.swift:97-102`) opens the gate for a new run, then on the camera queue returns without doing anything when `session != nil`. `open` (`:145-149`) captures the run id from the first `start`. After the second `gate.open`, `gate.isCurrent(oldRun)` is false, so runtime errors, interruptions, and device-lost notices are dropped. Frames still flow, because the sample-buffer delegate uses the gate rather than the run id. `stop` then `start` is ordered on the same queue. `start` while the session is already up is the hole.

Repro sketch: `start`, `start` again without `stop`, post `AVCaptureSession.wasInterruptedNotification`, and assert the new run's `report` was called. Needs a Mac for the session. The early return is visible in source.

### S02-15 — duplicate of ZB-015

Severity: P3, as in the ledger. Owner: top bar approvals, integration. #57 is the repair branch.

`NotchController.requestApproval` (`NotchController.swift:352-355`) still starts `Task { try? await Task.sleep(for: timeout); finish(onTimeout) }` and does not keep the task. `finish` is idempotent (`:319-324`), so a late timeout does not resume twice. The task holds the continuation for the full timeout after the person has answered.

On #57 `3cde0156a0cf`, `ApprovalWait.reduce` returns `.armTimeout` and `.resolve`, and the comment says the controller cancels the stored sleep. That head is not on integration.

Repro sketch: the ledger's. Answer the card at once and assert the timeout task is cancelled. Needs the approval card on a Mac.

### S02-16 — duplicate of ZB-027

Severity: P1, as in the ledger. Owner: PR #53.

`ProviderPlaybackGate.end` (`ProviderPlaybackGate.swift:36-39`) returns without decrementing unless `token == generation`. `endPlayer` (`:42-46`) removes the player and then applies the same check. `begin` and `begin(player:)` (`:20-33`) bump `generation` every time.

`playWithEngine` uses `begin` / `end`. `play` for a compressed buffer uses `begin(player:)` / `endPlayer`. Two overlapping clips leave `depth` high after the older completion, so `ProviderSentencePump.canDequeue` stays false.

Repro sketch: the ledger's. `begin(); begin(); end(first); end(second);` assert `isPlaying == false`. This type is Foundation-only. It was not executed here because it lives in the package that does not build on Linux.

### S02-17 — duplicate of ZB-033

Severity: P2, as in the ledger. Owner: PR #56.

`MediaCommandCoordinator.openAndWait` (`MediaCommandCoordinator.swift:175-189`) measures the launch with `Date()` and `timeIntervalSince`. `clock()` (`:249` on that head) is `timeIntervalSinceReferenceDate`. A forward wall-clock jump larger than `launchTimeout` fails a launch that a monotonic clock would still accept. The sleep task at `:184-187` is not cancelled when the open callback resumes `LaunchOnce`.

Repro sketch: the ledger's. Resolve the open callback at 1 second and assert the sleep task is cancelled. Jump the injectable clock past 8 seconds during a launch that is still in progress and assert the router still accepts it. The `Date()` calls need a Mac only for `NSWorkspace.openApplication`. The uncancelled `Task` is visible in source.

### S02-18 — duplicate of ZB-030

Severity: P2, as in the ledger. Owner: PR #64.

`HubTranscriptStore.write` (`HubTranscript.swift:192-195`) calls `createDirectory` and `Data.write` with the process umask. Two overlapping `write` calls on the same id have no lock. A torn read is possible on `load` (`:199-203`) because the atomic write replaces the file while another writer creates it.

Repro sketch: the ledger's. Two tasks call `write` on one id and `load` returns one of the two complete transcripts, never a mix. Directory mode `0o700`, file mode `0o600`.

### S02-19 — duplicate of ZB-011

Severity: P2, as in the ledger. Owner: scribe, integration. #61 is the repair branch and was not in this lens's fetch list.

`ScribeAutoStartOptIn.reconcile` (`ScribeAutoStartOptIn.swift:40-41`) does remove the stamp for `.ask`. The full `portable-scribe` run in the ledger observed the stamp surviving `aStaleStampWithAskMeIsRemovedAtLaunch`, and a later single-filter run passed. The suite shares `UserDefaults` across threads.

Repro sketch: the ledger's parallel scribe package. This VM did not re-run it.

### S02-20 — duplicate of ZB-012

Severity: P2, as in the ledger. Owner: wiki export, integration. #61 is the repair branch.

`SensitiveInfoScanner.healthWords` and `financeWords` (`SensitiveInfoScanner.swift:226-231`) build a new `NSRegularExpression` on every read. The comment at `:154` says the expression is built per use because it is not treated as sendable. The ledger's `portable-wiki-export` run died in `NSRegularExpression.init` on this path. A 32-thread replay of the health pattern alone survived, so the crash is the shared construction under the package's parallelism.

Repro sketch: the ledger's wiki-export package, kept with the crash report. This VM did not re-run it.

## File-disjoint fix clusters

Each cluster names files that one change should touch. Clusters do not share files, so they can land separately. Duplicates point at the branch that already owns the ledger row.

| Cluster | IDs | Files | Where to fix |
| --- | --- | --- | --- |
| Wake-word teardown | S02-01 | `Sources/Zeus/Voice/WakeWordListener.swift`, `Sources/Zeus/Voice/WakeWordController.swift` | integration, wake word |
| Provider speak cancel | S02-02 | `Sources/ZeusCore/Providers/VoiceProviderSession.swift`, `Sources/Zeus/Voice/PluginVoiceBridge.swift`, `Sources/Zeus/Voice/Speaker.swift` on #53 | #53 `16c2d697dcd4` |
| Output engine stop | S02-03 | `Sources/Zeus/Voice/UltronAudioChain.swift` | integration, voice output |
| Scribe handoff | S02-04 | `Sources/Zeus/Scribe/ScribeLiveCapture.swift` | integration, scribe |
| Talk-key observers | S02-05 | `Sources/Zeus/Voice/Speaker.swift`, `Sources/Zeus/Settings/GSVoiceCards.swift` | integration, voice output. Speaker.swift here is the integration file, not the #53 copy |
| Volume listeners | S02-06 | `Sources/Zeus/TopBar/TopBarServices.swift` lines that add the property listeners | integration, top bar. The reminder callback in this file is cluster "stale snapshots" and should land in the same change if both are fixed together; until then treat S02-06 as the listener block only |
| Stale snapshots | S02-07 | `Sources/Zeus/TopBar/TodayController.swift`, and the `fetchReminders` callback in `Sources/Zeus/TopBar/TopBarServices.swift:376` | integration. If S02-06 and S02-07 are fixed in one change, merge these two clusters |
| Polyglot stop | S02-08 | `Sources/Zeus/Polyglot/PolyglotAudio.swift`, `Sources/Zeus/Polyglot/PolyglotController.swift` | integration, polyglot |
| Provider playback lifetime | S02-09 | `Sources/Zeus/Voice/PluginVoiceBridge.swift` on #53 (`PluginAudioPlay`, `WavFinish`) | #53. Keep S02-16's gate change in its own cluster so the generation check does not get mixed with the observer |
| Key monitor start | S02-10 | `Sources/Zeus/Voice/HotkeyMonitor.swift` | integration |
| Browser client lifetime | S02-11 | `Sources/Zeus/BrowserAgent/MCPStdioClient.swift` | integration |
| Launch observers | S02-12 | `NotchController.start`, `WakeWordController.start`, `RoutineRunner.start`, `ProactiveController.start`, `BuddyController.start` | integration. `NotchController.swift` is also S02-13 and S02-15; fix S02-12's `start` without editing `requestApproval` or `boostCaptureVisibility` |
| Capture boost | S02-13 | `NotchController.boostCaptureVisibility` only | integration |
| Face camera rebind | S02-14 | `Sources/Zeus/FacePresence/FaceCamera.swift` | integration |
| Approval timeout | S02-15 | `Sources/Zeus/Notch/NotchController.swift` `requestApproval` | duplicate of ZB-015, owner #57 |
| Playback depth | S02-16 | `Sources/ZeusCore/Providers/ProviderPlaybackGate.swift` | duplicate of ZB-027, owner #53 |
| Launch clock | S02-17 | `Sources/Zeus/TopBar/MediaCommandCoordinator.swift` | duplicate of ZB-033, owner #56 |
| Transcript files | S02-18 | `Sources/ZeusCore/AgentHub/HubTranscript.swift` | duplicate of ZB-030, owner #64 |
| Scribe defaults | S02-19 | scribe test defaults | duplicate of ZB-011, owner #61 |
| Pattern compile | S02-20 | `Sources/ZeusCore/Wiki/SensitiveInfoScanner.swift` | duplicate of ZB-012, owner #61 |

S02-06 and S02-07 share `TopBarServices.swift`. They are listed as separate clusters with that overlap called out. A single change that fixes both should take both ids. Do not split the file across two concurrent changes.

S02-12 and S02-13 and S02-15 share `NotchController.swift`. The functions are disjoint (`start`, `boostCaptureVisibility`, `requestApproval`). One change per function.

## Read and not filed

- #30 `329bfc2045ed`. `FakeDuplexVoiceBackend.start` moves to `.closing` and then `.closed` when `close` arrives during `beforeStarted`. `VoiceSessionState` refuses events from `.closed` and `.failed`. No new row.
- #33 `d8fb8c2df661` and #39 `2ef01f4a543d`. The glass shell and the general section are synchronous registries. No task, observer, or actor was added that this lens can hang a defect on.
- #51 `ab0880462e65`. The turn machine is a pure struct on a monotonic clock. ZB-014 is addressed on this head.
- #52 `665b9167303f`. Electron metadata is trimmed with the live electrons. `OrbMascotView` pauses the metal view when the spark is hidden. `renderFrame` caps a hitch at eight steps. The view comment says the pose still comes from the buddy mode until the turn machine is merged. That is a wiring note, not a race.
- #57 `3cde0156a0cf`. `ApprovalWait` is the repair for ZB-015. No new concurrency defect in the policy types.
- #58 `10faecc83b32`. `LicenseCredentialCommit` is a synchronous function. Integration `syncWithServer` already drops a stale reply when `credentialRevision` changes across the await.
- #59, #62, #63, #65, #66, #67, #68, #69, #70. The hub types, session table, sound table, screen machine, and views are pure or single-threaded drawing. The session-table holes are ZB-028, ZB-029, and ZB-034, which are state-machine rows, not this lens. The sound table does not play audio.
- #64 is filed only as the duplicate S02-18.
- Integration paths that already remove their taps or observers, and that were read for this lens, include `SpeechInput`, `ScribeLiveCapture.stopMic`, `TeleprompterController.stopMic`, `Microphones.releaseCapture`, `SystemAudioTap.stop`, `EqualiserController`'s sleep observers, `PointingController`'s system observers, `FacePresenceController.start` (guarded by `started`), and `HotkeyMonitor.observeSleep`. They are not rows.

## Counts

New defects: 14. Duplicates of a ledger row: 6. Total rows: 20.

| Severity | New | Duplicate | Total |
| --- | --- | --- | --- |
| P1 | 2 (S02-01, S02-02) | 1 (S02-16) | 3 |
| P2 | 7 (S02-03 through S02-09) | 4 (S02-17, S02-18, S02-19, S02-20) | 11 |
| P3 | 5 (S02-10 through S02-14) | 1 (S02-15) | 6 |

Nothing in this sweep was run. The package does not build on Linux.
