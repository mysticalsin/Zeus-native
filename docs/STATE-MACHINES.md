# Implicit state machines in Zeus

Audit date 2026-11-10, branch `codex/explicit-state-machines`, based on `codex/native-polish-20261110` (7b83c9f).
Line numbers are from the base commit unless a row says "now".

An implicit state machine is lifecycle state spread over independent Bools, optionals, timers or tasks that
must change together. The fix pattern used here: a pure `State` / `Event` / `Effect` reducer in `Sources/ZeusCore`,
a controller that holds one `state` value and performs the effects, a token on every async completion, and
Swift Testing tests in `Tests/ZeusCoreTests`.

Summary: 20 machines inventoried in the first audit; 6 fixed then. Second pass (branch `codex/state-machines-20261111`,
2026-11-11) fixed items 12 to 17 and 19, the Automation Allow more bug and a new overlap-flag class (21); Insomnia is
reviewed and left, Pointing is explicit (22). Nothing could be compiled in the authoring sandbox; CI is the first compile. Item 23 (Scribe meeting start) was added by the auto-start branch, explicit from the start.

## Added after the audit

### 23. Scribe meeting start and call end. EXPLICIT from the start (2026-11-11), one machine from sighting to result (2026-11-14)
- Where: `ZeusCore/Scribe/ScribeAutoStart.swift` (`ScribeAutoStartMachine`), driven by `Zeus/Scribe/ScribeAutoStartController.swift` through the ports `ScribeStartPort` (Scribe), `ScribeOneShotScheduling`, `ScribeMeetingCardRendering` and a microphone answer, fed by `ScribeCallWatcher` (Core Audio wake-ups in `ScribeMicActivity.swift`, one calendar reader `ScribeCalendarReader`, a plan from `ZeusCore/Scribe/ScribeDetectorPlan.swift`), drawn by `ScribeMeetingCardPanel.swift`. Setting `scribe.autoStart`: Off, Ask me (default), Start automatically.
- States: idle, upcoming (the heads-up: a calendar meeting starts within 2 min, one card for 20 s, longer under the pointer), armed (seen, debouncing 3 s; `offerUntil` keeps a standing heads-up on screen through the check), prompting (the offer, 20 s, with the reason an automatic start is blocked), countingDown (5 s, Cancel), held (Scribe is still ending or saving the last meeting; `startOwed` is a tap or Switch that starts when Scribe is free), starting (one `ScribeStartAttempt`: meeting, origin tap or automatic, previous session, session), recording (Recording confirmed for 1.5 s, then watched until Scribe is idle), failed (60 s, longer under the pointer). The memory of what was done about each meeting is `ScribeMeetingLedger`, not a state.
- Events: `evidence`, `scribe(phase)`, `tick(context)`, `primary(on: card, context)`, `cancel(on: card)`, `dismiss(on: card)`, `pointer`. The facts a start needs (Scribe's phase, Microphone access, `ScribeAutoStartReadiness`) are read by the app at the moment of each event as a `ScribeStartContext`; the machine keeps no copy. A tap carries the card the person saw and the machine reads its case and meeting.
- Effects: `start`, `abandonStart(session)`, `openMicrophoneSettings`, `suggestEnd`, `withdrawEnd`, `endNow`. There is no show or hide effect: `card(now:)` is the only source of what is on screen and `nextWake(now:)` the only source of when the app wakes (one one-shot timer on the main run loop in the common modes, nil when idle). The controller renders after every event and logs each state change once (`[ZEUS] scribe meeting: <state>`).
- Signals: a known call app holding the microphone (`kAudioProcessPropertyIsRunningInput`, Zeus excluded) is a live meeting, the calendar one it belongs to (from 2 min before its start to its end) or a call with no calendar behind it; a calendar meeting that has started (up to 5 min) is a scheduled meeting with or without a call; one that starts within 2 min (`ScribeMeetingEvidence.upcoming`, `0 < start - date <= leadWindow`, not ended) is the heads-up. An open app alone is not a meeting. Event-driven: Core Audio listeners on the input flag of every known call process (added and removed with the process list) plus the default input device flag.
- Detector rules: the detector runs only when a meeting is near. `ScribeDetectorPlan.plan(mode:machineIdle:micActive:slots:now:)` gives `stopped` (Off with the machine idle: no timer, no listeners, no calendar reads), `polling` (a slot from 2 min before its start to 5 min after it and before its end, a call app holding the microphone, or a machine that is not idle: the 5 s read, as the backup to the listeners) or `listening(wakeAt:)` (the listeners wait and one wake-up is set for 2 min before the next meeting, at most 24 h ahead). The watcher starts at launch unless the choice is Off, follows the choice at once (`follow()`), applies the plan after each scan, and reads again on a calendar change and on wake from sleep. `ScribeScanGate` runs one scan at a time; a wake during a scan runs exactly one more when it ends. A scan that ends after a stop is dropped. Off while the machine records or holds a card keeps reading until the machine is idle. The calendar reader leaves out events the current user declined.
- Start rules: one trigger per meeting (key = calendar event id, else call app; the ledger keeps an answer until the slot ends, or until the call app is gone or has not held the microphone for 30 s; a different meeting is offered at once). Automatic start counts down only for a live call and needs all of: Start automatically chosen in Settings, the stamp that click wrote (`scribe.autoStart.optInAt`), Microphone already allowed, and one earlier recording on this Mac (`scribe.firstRecordingAt`); the first missing one is `ScribeAutoStartReadiness`, and without all of them it asks. The choice, the readiness and the live call are read again on every evidence during the countdown and at its end; anything gone asks instead, and leaving Start automatically ends the countdown. A recording started by hand is never prompted over.
- Heads-up rules: from idle, with no candidate, Scribe free and the slot unmarked in the ledger, the closest upcoming slot enters `upcoming` and the ledger notes `headsUp` at once, so it is shown once per meeting and a failed or empty calendar read cannot announce it again. Shown in Ask me and Start automatically, never in Off. The deadline returns to idle with no answer; the dismiss glyph notes `declined`, which holds at the start time; Record starts with the slot's title and guests and no call binding. A candidate for the same meeting moves to `armed` with `offerUntil` set, so the card stays through the 3 s check and then asks (reading "now") or counts down; a candidate that vanishes inside the check, a microphone blip say, returns to `upcoming` with its remaining time and never counts down.
- Outcome rules: a tap or a countdown that ends with the microphone denied is `failed(.microphoneOff)`; with Scribe already starting or recording it joins that session and starts nothing; with Scribe ending or saving it is held; otherwise it emits `start` once and enters `starting`. The app then sends `scribe(phase)` in the same turn. A session equal to the one Scribe was on at the request is never the result, and a phase still saving it fails at once as `stillSaving`. Starting stays Starting; recording confirms; Scribe's own failure reason is shown; ending, processing or complete of the new session hides the card. No new session in 5 s, or in 45 s once starting, is `failed(.noResponse)`, which still accepts the late success. Starting and failed react only to Scribe, the time, taps and the pointer: evidence, a mode change including Off, and the meeting going away never take them down.
- Cancel rules: Cancel on the countdown or the waiting card ends it and answers the meeting. On an automatic start, in starting or in the 1.5 s of Recording, it emits `abandonStart(session)`: nothing is saved. In every other case it does nothing, and no path from Cancel starts anything. A start after a Record tap has no Cancel, and a close glyph never cancels a start. A Record tap on an offer that ended in the same instant still starts that meeting, unless a countdown, a start or a recording is already under way. After a failure leaves, the meeting is handled and nothing retries by itself.
- Held and Switch: a meeting sighted while Scribe saves is held, not marked; with Scribe free it counts down (live and ready) or asks, or drops if its call is gone. Switch emits `endNow` (the recording ends at once, no end window) and holds the next meeting with `startOwed`; it starts once when the notes are saved.
- End rules: the call app released the microphone for 8 s after holding it (a Zoom breakout hop of a few seconds is ignored), or its call window (read from window titles, only when readable; Zoom, Meet, Slack huddle, Webex) was seen and then gone for 8 s. Then the machine emits `suggestEnd` and Scribe's end window opens with "The call looks over", End meeting now and Keep recording. It is advisory: no countdown, the state stays recording (`endSuggested`), and nothing stops until a tap or the bound call app closing. When no signal holds any more the machine emits `withdrawEnd` and the window closes. Keep recording is not read by the machine, so nothing is suggested again until the call has come back. While the call looks over the next wake is one second ahead and the app reads fresh signals (`needsFreshEvidence`).
- Next meeting: while recording, another calendar meeting with a call link about to start (2 min before to 30 s after) is offered once with Switch or the dismiss glyph (20 s); dismissing or the timeout keeps recording.
- Indicator: the closed notch shows the Scribe recording wings for any Scribe recording (`ClosedWings.kind`), however it started.
- Tests: `ScribeMeetingStartOutcomeTests.swift` (taps, outcomes, cancel, held, switch, one row per state for `card(now:)` and `nextWake(now:)`), `ScribeAutoStartTests.swift` (signals, debounce, ledger answers, readiness, call end, next meeting, the heads-up), `ScribeAutoStartOptInTests.swift` (stamp, launch migration, readiness order), `ScribeMeetingLedgerTests.swift`, `ScribeDetectorPlanTests.swift` (the plan rows and the scan gate) and, in the app target, `ScribeDetectorTests.swift` (the watcher with fake listeners, scheduler and scan; the calendar reader's rule).

### 24. Drawn notch calibration. EXPLICIT from the start (2026-11-14)
- Where: `ZeusCore/TopBar/DrawnNotch.swift` (`DrawnNotchCalibration.reduce`), the shape rules in `DrawnNotchLimits`, the footprint in `NotchFootprint.swift`. The notch model and the Settings card come in later tickets and meet at `DrawnNotchControlling`.
- States: `idle`, `adjusting(draft, saved)`. The draft is shown while adjusting and the saved shape otherwise; the guide outline shows and opening by pointer stops only while adjusting.
- Events: `begin(saved:)`, `setWidth`, `setHeight`, `setOffset`, `step(field, direction)`, `reset`, `done`, `cancel`, `surfaceGone(loss)`.
- Effects: `persist(shape)` and `announce(text)`. Only `done` with a draft that differs from the saved shape persists; `cancel` and every `surfaceGone` return to `idle` and persist nothing.
- Losses, logged by name and all with the same result: the page was left, Settings closed, Settings minimised, the app hid, Pill was chosen, the last display without a notch went away, the Mac locked or slept, the session switched user. Settings sitting behind another app is not a loss.
- Rules: a second `begin` changes nothing; a set, step or reset while `idle` is ignored; every field is snapped to its step and clamped, and a field that is not a number takes its default.
- Tests: `DrawnNotchCalibrationTests.swift` (every event from both states, each of the nine losses, no persist from cancel or a loss), `DrawnNotchTests.swift` (limits, fit, availability).

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
tests in `Tests/ZeusCoreTests`, and a `qa/regressions.json` row (REG-227 to REG-229 and REG-241 to REG-247; REG-230 to REG-236 were taken by the parallel Laya, voice and settings rows).

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

## Third pass (2026-11-11)

Branch `codex/state-machines-pass3-20261111`. Scope: code added on 2026-11-11 that passes 1 and 2 never saw. Nothing could be compiled
in the authoring sandbox; CI is the first compile. New shared primitive: `ZeusCore/Lifecycle/LatestRun.swift` (a token per run, `begin`,
`finish`, `invalidate`; only the live token may publish or finish).

| # | Area | Problem | Severity | Fix | Test | REG |
|---|---|---|---|---|---|---|
| 23 | Talk to Zeus fast race (`TurnRaceState`, `FastRaceRun`) | A winner that broke off mid-sentence left the deep answer running and deliverable | medium | winner failure cancels and drops the deep answer | `TurnRaceLiveTierTests` | 248 |
| 24 | Same | Losers cancelled by the winner reported a cancellation error that was logged, ranked as a failure in `BrainLatencyBook` and could mark quota state | medium | `isLive(tier)` gate on `.failed` and `.finished` | `TurnRaceLiveTierTests` | 249 |
| 25 | `VoiceTurnController.turnRunning` | Bool cleared by a cancelled turn under its replacement (wake gate and `isBusy` saw idle mid-answer) | medium | `LatestRun` slot | `LatestRunTests` | 250 |
| 26 | Hands-free and wake turn | The silence timer of an earlier turn released a key the owner was holding; `wakeTurn` did not stop the previous deep follow-up or speculative run | medium | `press` cancels the timer, `wakeTurn` cancels race and ahead run | source lint | 251 |
| 27 | `Speaker` (Ultron engines) | Barge-in counted as an engine failure and could pause a healthy route; Kokoro, Chatterbox and OpenAI audio that finished after the cancel still played | medium | `SpeechAttemptPolicy` | `SpeechAttemptPolicyTests` | 252 |
| 28 | Alerts capsule | Timers ran while a peek or the panel covered the capsule: alerts expired unseen | medium | `AlertStack.setSuspended`, driven from `NotchController.show` | `AlertStackSuspendTests` | 253 |
| 29 | Alerts | Dismissing the last alert left a stale hover so the next alert never auto-dismissed | low | empty stack clears hover | `AlertStackSuspendTests` | 254 |
| 30 | Alerts snooze | A snoozed alert was dropped if the notch was open when it returned; repeated snoozes doubled | low | `postAlert(whileOpen:)`, one tracked task per id | source lint | 255 |
| 31 | Recordly countdown | Kept counting after the owner left the page, then started a capture they could not cancel | high | `pageDisappeared` on `onDisappear` | `RecordlyCountdownSourceTests` | 256 |
| 32 | Recordly countdown | A vanished source ended the countdown in a silent no-op | low | `tick(sourceReady:)` ends with a notice | `RecordlyCountdownSourceTests` | 257 |
| 33 | Settings Launch at login | An older background status read overwrote the owner's toggle | medium | `LatestRun` invalidated by the toggle | `LatestRunTests` | 258 |
| 34 | AI connections hooks | A look that began before Connect or Disconnect overwrote the click; Codex Connect never updated its row | medium | `hookReads` token, Codex row set on connect | source lint | 259 |

Plain behaviour bugs found: Codex row stayed "Ready" after Connect (34); `postAlert` silently drops alerts while the notch is open (kept by design,
snooze now bypasses it); `Speaker.speak(sentenceStream:)` and `SentenceSpeaking` have no caller (dead API, not removed).

Reviewed, no change: language pack installer (`LanguagePackState` is an explicit reducer with tokens; a late probe after remove can mark a component
installed, low, not changed); speaker model download (`ModelPreparation`, item 2); saved voices (synchronous, single owner); top bar position and
screen-share policy (stateless math plus one stored value); Jev stage (`hasJevKey` is refreshed at the only two write sites); scribe speaker pipeline
(covered by item 7).

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
