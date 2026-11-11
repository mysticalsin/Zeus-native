# Implicit state machines in Zeus

Audit date 2026-11-10, branch `codex/explicit-state-machines`, based on `codex/native-polish-20261110` (7b83c9f).
Line numbers are from the base commit unless a row says "now".

An implicit state machine is lifecycle state spread over independent Bools, optionals, timers or tasks that
must change together. The fix pattern used here: a pure `State` / `Event` / `Effect` reducer in `Sources/ZeusCore`,
a controller that holds one `state` value and performs the effects, a token on every async completion, and
Swift Testing tests in `Tests/ZeusCoreTests`.

Summary: 20 machines inventoried (item 21 was added later, already explicit). 6 were fixed (5 commits, Chrome consent shares the consent commit). 5 were already
explicit or mostly explicit (skipped). 9 remain: 8 ranked at the end, plus KeepAwake which needs no change.

## Added after the audit

### 21. Scribe meeting start and call end. EXPLICIT from the start (2026-11-11)
- Where: `ZeusCore/Scribe/ScribeAutoStart.swift` (`ScribeAutoStartMachine`), driven by `Zeus/Scribe/ScribeAutoStartController.swift`, fed by `ScribeCallWatcher` (poll plus Core Audio wake-ups in `ScribeMicActivity.swift`), banner in `ScribeMeetingBanner.swift`. Setting `scribe.autoStart`: Off, Ask me (default), Start automatically.
- States: idle, armed (seen, debouncing 3 s), prompting (20 s), countingDown (5 s, Cancel), recording, endingSuggested, cooldown.
- Signals: calendar event with a call link within 2 min before to 5 min after its start and its call app open; or a known call app holding the microphone (`kAudioProcessPropertyIsRunningInput`, Zeus excluded). An open app alone is not a meeting.
- Rules: one trigger per meeting (key = calendar event id, else call app; same key stays quiet until it was gone 30 s and 60 s passed); automatic start only when Microphone is already granted (otherwise it asks, and a permission lost during the countdown falls back to asking); call end = the call app released the microphone for 30 s after holding it, then Scribe's own end window opens (9 s, Keep recording); Keep returns to recording and waits for the microphone to come back before suggesting again; a recording started by hand is never prompted over; ticks only move banner deadlines.
- Tests: `ScribeAutoStartTests.swift` (every transition, debounce, single trigger, permission fallback, call-ended path, keep, cooldown re-arm).

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

## Remaining (not fixed)

### 12. Polyglot run. HAND-ROLLED BUT GUARDED, severity medium
`Polyglot/PolyglotController.swift:24-25, 60-68, 118-173`: `isListening`, `isStarting`, `generation`, `startTask`, `pipeline`, `mic`, `system`, `audioIn`, `eventIn`, `audioTask`, `eventTask`. Every await in `begin` checks `isCurrent(token)` and tears down what it opened, and `stop()` bumps the generation, so I found no live bug. The Bools are still two flags for what is idle, starting(token), listening(token). Candidate for a `PolyglotRun` reducer; the risk is the 12 resources `stop()` must release.

### 13. Automation consent cache. IMPLICIT, severity medium
`App/PermissionsModel.swift:365-455` (`Automation`: static `cache`, `inFlight`, `cacheLock`, `testStatusProvider`, TTLs) plus `automationPending` and `automationAsking`. Scenario: a background `ask: false` check starts, the person clicks Allow, `askAsync` stores `granted`, then the older check returns `errAEEventWouldRequireUserConsent` and `storeResolved` overwrites the grant and `remember` deletes the persisted grant until the next 20 s refresh. Needs a per-bundle generation like `UpdateRefresh`. Not fixed because the cache is static, lock-based and shared with tests.

### 14. SpeechInput recorder. IMPLICIT, severity medium
`Voice/SpeechInput.swift:118-148`: `engine`, `request`, `task`, `finished`, `waiters`, `generation`, `latest`, `finalizedText`, `stopRequested`, `consecutiveErrors`, `suppressLiveTap`, all under one `NSLock`. Generation checks exist on taps and restarts. A clean model would be idle, recording(session), restarting(session), stopping(session). Not fixed: 630 lines, lock-based, audited for the Swift 6 callback rules, and no compiler here.

### 15. Wake word retry. OPEN LOOP, severity low
`WakeWordController.swift:48, 168-188`: `retryStartAt` retries every 10 s (mic start failure) or 30 s (no on-device recognition) forever, with no terminal "needs attention" state and no log dedupe after the first.

### 16. Onboarding completion. GAP, severity medium
`Onboarding/OnboardingFlow.swift:122-160, 322`. "Set up later" is a per-step skip (`flow.next()`), not a dismissal; completion is recorded only by `complete()` on the final Sounds step. Closing the window earlier records nothing, so `AppDelegate.swift:300` (`!OnboardingFlow.isCompleted`) reopens the guide at the saved step on every launch. Fix needs a dismissed state plus a policy in `AppDelegate.swift`, which is off limits tonight (see report).

### 17. Accessibility gate. IMPLICIT, severity low
`App/PermissionsModel.swift:476-496` (`AccessibilityGate`: `waiting`, `timer`): polls every 3 s forever and never drops waiters if the feature that queued them is turned off.

### 18. Insomnia. IMPLICIT, severity low
`Insomnia/InsomniaController.swift:42-64, 110-219, 357`: `lidArmed`, `setupBusy`, `armFailure`, `restoreRetry` timer, `lastHotspotTry`, `nudgeTimer`. Guards exist (`guard !lidArmed`, `!setupBusy`) and `restoreRetry` is invalidated on disarm. No concrete bug found.

### 19. Teleprompter. IMPLICIT, severity low
`TopBar/TeleprompterController.swift:10-14, 28-60, 79-105`: `topBar.prompterActive`, `engine`, `timer`. A level queued before `end()` can write `prompterLevel` after the reset to 0. Cosmetic.

### 20. KeepAwake. EXPLICIT ENOUGH
`TopBar/TeleprompterController.swift:166-196`: `isOn` plus the assertion id, both set together in one place. No change needed.

## Ranked work left
1. Automation consent cache stale overwrite (13).
2. Onboarding dismissal state (16), needs `AppDelegate.swift`.
3. SpeechInput recorder session model (14).
4. Polyglot `PolyglotRun` reducer (12).
5. Wake word retry terminal state (15).
6. Accessibility gate waiters (17).
7. Teleprompter level after end (19).
8. Insomnia (18).
