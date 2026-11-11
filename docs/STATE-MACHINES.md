# Implicit state machines in Zeus

Audit date 2026-11-10, branch `codex/explicit-state-machines`, based on `codex/native-polish-20261110` (7b83c9f).
Line numbers are from the base commit unless a row says "now".

An implicit state machine is lifecycle state spread over independent Bools, optionals, timers or tasks that
must change together. The fix pattern used here: a pure `State` / `Event` / `Effect` reducer in `Sources/ZeusCore`,
a controller that holds one `state` value and performs the effects, a token on every async completion, and
Swift Testing tests in `Tests/ZeusCoreTests`.

Summary: 20 machines inventoried in the first audit; 6 fixed then. Second pass (branch `codex/state-machines-20261111`,
2026-11-11) fixed items 12 to 17 and 19, the Automation Allow more bug and a new overlap-flag class (21); Insomnia is
reviewed and left, Pointing is explicit (22). Nothing could be compiled in the authoring sandbox; CI is the first compile.

## Fixed

### 1. Dictation job phase (live, file, history re-run). FIXED, severity high
- Where: `Dictation/DictationController.swift` (`topBar.dictationPhase` written at about 20 sites: 479, 515, 524, 583, 653, 663, 713, 719, 741, 863, 1016, 1092, 1119, 1128-1191), `TopBar/TopBarModel.swift:47`.
- State: `topBar.dictationPhase` + `ownership.generation` + `turnContext` + `turnStream` + `escapeMonitor` + `pausedMedia`.
- Real states: idle, listening, transcribing (live or file), rewriting (live or history), done, failed.
- Bugs: `transcribe(file:)` had no guard. Scenario: hold the dictation key, then pick a file from the notch. The phase flips from `.listening` to `.transcribing`, `finish()` now refuses (it needs `.listening`) while the recorder keeps capturing. Two files overlapped, and the first to end showed "done" while the second ran. A cancelled file still copied its text to the clipboard (no token). Two history re-runs shared one token, so one could clear the other's `.rewriting`.
- Fix: `ZeusCore/Dictation/DictationFlow.swift` (`DictationFlow.reduce`), tests `DictationFlowTests.swift`. The controller holds `flow`; the top bar phase mirrors it.

### 2. Parakeet download and load. FIXED, severity high
- Where: `DictationController.prepareModel` (389-415), `Dictation/SpeechEngineSettings.swift:8` (`SpeechEngineStatus.progress`), `SpeechEngines.swift:49-82`.
- State: `status.progress` (doubled as the "already running" flag) + `status.problem` + an unowned `Task`.
- Bugs: progress callbacks hop through the main queue, so a late one could land after `progress = nil` and stick the bar and refuse every later download. No cancel. After a failure each dictation key press started the download again (retry with no terminal state). `ParakeetEngine.loadedManager` let a finished older load clear a newer one.
- Fix: `ZeusCore/Dictation/ModelPreparation.swift`, tests `ModelPreparationTests.swift`. Settings gets a Cancel button; automatic retries stop after a failure.

### 3. Consent prompts (voice, camera, calendar, reminders). FIXED, severity medium
- Where: `Voice/VoicePermissions.swift:13` (`asking`), `App/PermissionsModel.swift:131-143` (`requestVoice`, no guard), `requestCamera`, the Calendar and Reminders `Task` in `request(_:)`.
- State: a static `asking` Bool in one place, nothing in the others.
- Bugs: double click on "Turn on" asked macOS twice (mic and speech). A second `ensure(explicit:)` while asking returned immediately with an undetermined answer.
- Fix: `ZeusCore/Permissions/RequestFlight.swift` (`RequestFlight`, `RequestFlights<Key>`), `App/PermissionPrompts.swift`, tests `RequestFlightTests.swift`.

### 4. Chrome per-site consent. FIXED, severity medium
- Where: `Chrome/ChromeActions.swift:12, 161-167` (`allowedHosts` plus `consent`).
- Bug: two steps on the same site in flight at once raised two approval cards.
- Fix: same `RequestFlight` through `PermissionPrompts` keyed by `chrome:<host>`.

### 5. Update badge refresh. FIXED, severity medium
- Where: `App/UpdateCoordinator.swift:33-52` (`refreshBadge`, one unordered `Task` per call, settings captured at start).
- Bug: turn auto-update off while a slow feed check is in flight, the older check finishes last and brings the badge back. Same for Dismiss.
- Fix: `ZeusCore/Updates/UpdateRefresh.swift`, tests `UpdateRefreshTests.swift`.

### 6. Microphone test. FIXED, severity low
- Where: `Dictation/Microphones.swift:72-136` (`MicrophoneTester`: `running`, `level`, `peak`, `problem`, `engine`, `stopTask`).
- Bugs: the tap only checked `running`, so a level queued from the previous test inflated the next test's peak and verdict. A failed start left the previous peak and verdict on screen.
- Fix: `ZeusCore/Dictation/MicTest.swift`, tests `MicTestTests.swift`.

## Already explicit (skipped)

### 7. Scribe session. EXPLICIT
`Scribe/ScribeController.swift:238` holds `ScribeSessionMachine` (ZeusCore `ScribeSession.swift`, `ScribeLiveLogic.swift`) and routes every command through `run(_:)` with a rollback copy. `ScribeEndWorkflow` models the end flow. Not touched.

### 8. Recordly capture. EXPLICIT
`Recordly/RecordlyController.swift:28-29` uses `RecordlyRecordingSession.Phase`, `ProjectPhase`, `RecordlySourcePicker.State` and `RecordlyCheckpointFlow` (all ZeusCore). `exportGeneration` guards stale exports. Not touched.

### 9. Dictation turn ownership. EXPLICIT (token model)
`DictationController.swift:89-130` (`DictationTurnOwnership`, `DictationPartialUpdateGate`) is a sound generation model. It is now the token source for `DictationFlow`.

### 10. Review card answer. EXPLICIT
`DictationController.swift:240-255` (`ReviewAnswerGate`) resumes its continuation exactly once; `reviewWithTimeout` bounds the wait.

### 11. Wake word gate. MOSTLY EXPLICIT
`Voice/WakeWordController.swift` derives run/pause from the pure `WakeGate` (ZeusCore) on a 2 s poll. The listener itself is one optional. Only the retry loop is open, see item 15.

## Fixed in the second pass (2026-11-11)

Each follows the same shape: a pure reducer in `Sources/ZeusCore`, a controller that applies its effects, Swift Testing
tests in `Tests/ZeusCoreTests`, and a `qa/regressions.json` row (REG-227 to REG-236).

### 16. Onboarding completion. FIXED, severity medium
`ZeusCore/Onboarding/OnboardingProgress.swift` (notStarted, inProgress, dismissed, completed), tests `OnboardingProgressTests.swift`,
App tests in `OnboardingIsolationTests.swift`. Closing the window (`windowWillClose`) or "Set up later" with no step after it records
`zeus.onboarding.dismissed`; `AppDelegate` opens the guide at launch only for an unfinished, undismissed guide
(`OnboardingProgress.opensAtLaunch`). Settings > General > Setup keeps "Show setup guide" (still opens after a dismissal or completion).

### 13. Automation consent cache. FIXED, severity medium
`ZeusCore/Permissions/AutomationConsentCache.swift`: a generation per app. It moves when the consent sheet is raised and when it is
answered; each background check keeps the generation it started in and a result from an older one is dropped (also the "slow" mark and a
late answer). `Automation` in `PermissionsModel.swift` now holds `[bundleID: State]` under the lock. Tests `AutomationConsentCacheTests.swift`
(the race is `olderCheckReportingNeedsConsentCannotOverwriteANewerGrant`) and an App-level test with a blocked provider in
`PermissionsAutomationTests.swift`. Also fixed: a late (slower than 1 s) answer used to be discarded; it is now kept when still current.

### 13b. Settings > Automation "Allow more". FIXED, severity medium
`ZeusCore/Permissions/AutomationAllowPlan.swift`. The button asked every running app, so with only an already-allowed app open it did
nothing visible; closed apps were never named; an app macOS had refused (it never re-prompts) failed silently. Now only apps not yet
allowed are asked, closed ones are named ("Open Spotify, Keynote or PowerPoint, then press Allow more."), a refused or declined app opens
the Automation pane with "Turn on Zeus for Spotify in Automation.", and the status text lists app names from an observable list.
Tests `AutomationAllowPlanTests.swift`.

### 12. Polyglot run. FIXED, severity medium
`ZeusCore/Polyglot/PolyglotRun.swift` (idle, starting, listening, stopping) replaces `isStarting`/`isListening`. Real bugs it removes: an input
that ended mid-start was counted as open (the run said Listening on a dead mic); a mic change during the Mac-audio start stopped a two-input
run; a stale start's cleanup did `mic?.stop(); mic = nil` on the newest run's microphone after Stop then Start. Tests `PolyglotRunTests.swift`
(stop during start, double start, error mid-start, late events from an older run).

### 14. SpeechInput recorder. FIXED, severity medium
`ZeusCore/Dictation/SpeechRecorder.swift` (idle, recording, restarting, stopping, all keyed by session). `SpeechInput` keeps its lock and
Swift 6 callback rules (no tap or recognition handler moved; the audited file list is unchanged) and consults the reducer for `stopRequested`,
the error counter and both restart decisions (they were written twice). A second final during a restart no longer opens a second task.
Tests `SpeechRecorderTests.swift`.

### 15. Wake word retry. FIXED, severity low
`ZeusCore/Voice/WakeRetry.swift`: doubling backoff (10 s to 60 s for the mic, 30 s to 120 s for no on-device recognition), 6 and 3 attempts, then
"Needs attention"; one log line per streak; reset by turning it off and on, a pause (permission, call, lock) or a success. Driven by the existing 2 s
gate check. Tests `WakeRetryTests.swift`.

### 17. Accessibility gate. FIXED, severity low
`ZeusCore/Permissions/TrustWait.swift`: waiters are keyed (call site by default), asking twice runs the feature once, `cancelWaiting(key:)` drops one,
and the 3 s poll stops with the last waiter. Tests `TrustWaitTests.swift`.

### 19. Teleprompter. FIXED, severity low
`ZeusCore/TopBar/PrompterRun.swift`: a session number per voice-follow microphone; a level is accepted only from the live session of a running
prompter, so a level queued before `end()` (or before a voice-follow off and on) no longer lights the meter. Tests `PrompterRunTests.swift`.

### 21. Busy flags shared by overlapping calls (Beamer, AI connections). FIXED, severity low
`BeamerModel.busy` was set by `perform` and `install` with no re-entry guard, and `AIConnections.checking` by every `refresh`: the first of two
overlapping calls to finish cleared the flag under the other. `ZeusCore/Lifecycle/OverlapCounter.swift`, tests `OverlapCounterTests.swift`.

## Remaining and reviewed

### 18. Insomnia. IMPLICIT, severity low, not changed
`Insomnia/InsomniaController.swift`: `lidArmed`, `setupBusy`, `armFailure`, `restoreRetry`, `lastHotspotTry`, `nudgeTimer`. Its `session` already is an
explicit model (`session.isActive`) and the remaining flags are re-entry guards that hold; no scenario that loses state was found, so a rewrite
would add risk without removing a bug class.

### 22. Pointing (PointingController, PointingHotkeyMonitor). EXPLICIT
Driven by `PointingSession` and `PointingKeyGesture` in ZeusCore (begin, end, cancel, escape, blocked are all session events with a generation
and `isCurrent` checks after every await); the source lint already bans `Task.sleep` and non-nonisolated callbacks there. One gap: when the event tap
cannot be created (`PointingHotkeyMonitor.startTap`) `onUnavailable` fires once and `isRunning` stays true, so only a stop and start (turning
Pointing off and on) retries. Low severity, not changed.

### Other sweep results (no change)
- `KokoroWorkerSession`, `MCPStdioClient`: actors with several Task handles but one admitted request, a `closed` flag and generation checks; serialized by
  the actor. Explicit enough.
- `LicenseManager.busy`, `WikiMCPExport.busy`, `VoiceSettings.loadingLibrary`, `ProjectScanner.refreshing`, `AppIndex.refreshing`: each guards re-entry
  before setting the flag (single flight), so the overlap bug does not apply.
- `Speaker.isSpeaking` is derived from four sources (synthesizer, pump, player, file pump); read-only, no write races found.
- Scribe and Recordly were out of scope for this pass (other work in progress on those folders); their machines remain the explicit ones in items 7 and 8.

### 20. KeepAwake. EXPLICIT ENOUGH
`TopBar/TeleprompterController.swift`: `isOn` plus the assertion id, both set together in one place. No change needed.
