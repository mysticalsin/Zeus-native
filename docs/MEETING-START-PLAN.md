# Meeting start: one machine, one card, an opt-in that works. Plan and design

Written 14 November 2026 against `codex/island-20261113` at `d26eb37` (read only: nothing was built, run or
launched). Second version, rewritten after an adversarial review whose findings were each checked against the
code. This is the spec, design note and task list for the meeting-start notification and automatic start. It
follows `AGENTS.md`, `docs/DESIGN-DIRECTION.md`, `docs/ALERTS-DESIGN.md`, `docs/STATE-MACHINES.md` (item 23) and
`docs/SCRIBE-PRIVACY-AND-END-FLOW.md`, and the pure-rules-in-ZeusCore pattern. When work starts, copy this file
to `docs/MEETING-START-PLAN.md` in the worktree. Nothing here is accepted until the named tests run on macOS and
the behaviour is seen on a Mac.

## Verdict: refactor first

The request cannot be built cleanly on today's structure. Stop, agree on the refactor below, then build.

Why. One meeting is decided by two pipelines that share no state, and its start is tracked by two machines:

- The heads-up ("Starts in N min") lives outside the machine: `ScribeCallWatcher.decision` plus three dismissal
  collections (`ScribeCallWatcher.swift:213-222`), `ScribeCallPrompt.decide`, `ScribeCallPopup` with its own
  45 s lifetime (`ScribeCallPopup.swift:79`). `decision` is written before `present()` and `present()` can
  return without showing (`ScribeCallWatcher.swift:355-359`, `ScribeCallPopup.swift:109-111`), so a heads-up
  can be lost for good.
- `ScribeAutoStartMachine` enters `.recording` at the moment it emits the effect (`ScribeAutoStart.swift:584-587`),
  not when Scribe reports. The truth about "did it start" lives in a second machine, `ScribePopupLifecycle`, and
  only for taps. The automatic path hides the card first (`:574`) and a refused start only logs
  (`ScribeAutoStartController.swift:112-117`). The feature the owner asks for is the one path with no result.
- The two machines are glued by patches: `startNow`, the `banner.meeting` late-tap fallback
  (`ScribeAutoStartController.swift:45-55`), `begin()` returning false (`ScribeMeetingBanner.swift:161-173`),
  `hide()` refusing while busy (`:154-158`).
- Two card shells copy the same panel, layout and origin code (`ScribeCallPopup.swift`, `ScribeMeetingBanner.swift`).

A visible countdown, a truthful result for an automatic start and a Settings opt-in on top of this would add a
third outcome tracker and a third set of card states. That is a bolt-on. The clean route: the existing machine
owns the whole life of a meeting (sighting, decision, card, start, result), and the card is a pure view of its
state. The refactor removes more code than it adds.

Scope of the refactor (tickets MS0, MS1, MS2, MS6, MS7):

| Area | Files |
| --- | --- |
| Core, changed | `Sources/ZeusCore/Scribe/ScribeAutoStart.swift`, `ScribeEndWorkflow.swift`, `ScribeLiveLogic.swift:547-578` |
| Core, new | `ScribeMeetingSignals.swift` (evidence types moved, no behaviour change), `ScribeMeetingLedger.swift`, `ScribeMeetingCard.swift`, `ScribeMeetingContext.swift`, `ScribeAutoStartOptIn.swift`, `ScribeDetectorPlan.swift` |
| Core, deleted | `ScribePopupLifecycle.swift`, `ScribeCallPrompt.swift` (its slot and name types move), `ScribeCallPromptText` |
| App, changed | `Sources/Zeus/Scribe/ScribeAutoStartController.swift`, `ScribeCallWatcher.swift`, `ScribeController.swift:303-325, 556-601, 658, 679-687, 725-736`, `ScribeEndWindow.swift:84-100`, `ScribeIdleView.swift:168-172`, `Settings/GSFeaturesPage.swift:100-108`, `App/SettingsStore.swift:108-113, 306-333` |
| App, new | `ScribeMeetingCardView.swift`, `ScribeMeetingCardPanel.swift` |
| App, deleted | `ScribeCallPopup.swift` (219 lines), `ScribeMeetingBanner.swift` (252), `ScribePopupDriver.swift` (215) |
| Tests | `ScribeAutoStartTests.swift` (68 cases adapted), `ScribePopupLifecycleTests.swift` (18 cases ported, then removed), `ScribeCoreTests.swift:955-1030` and `ScribeLiveLogicTests.swift:464-488` (replaced), `ScribeLifecycleScenarioTests.swift:131` |
| QA | `qa/regressions.json` REG-400 to REG-409, `qa/feature-map.json` F04, `qa/closed-loop/tests/test_source_lint.py:685-715`, `qa/closed-loop/tests/test_alerts_lint.py:59`, `qa/portable-core/prepare.py:86-96` |

Risk of the refactor: the click path that REG-400 to REG-409 fixed is rebuilt. Each of those ten guards keeps
its test name and is retargeted in the same ticket that moves the code it guards; none is dropped, and no
ticket leaves the gate red.

## What the owner asked for

| Ticket | Kind | Gap today | After |
| --- | --- | --- | --- |
| MS0 | Refactor | The card's states exist only as strings and flags on two panels | One frozen card value and its words, so the card and the machine can be built side by side |
| MS1 | Refactor | "Meeting started" can show, and automatic recording can begin, up to 2 minutes early; one meeting has two names; three separate memories of "already handled" | A meeting starts at its start time; automatic start needs a live call; one ledger remembers every meeting |
| MS2 | Refactor | Title, guests and call binding travel as three loose optionals that leak after a refused start | One `ScribeMeetingContext` value passed to `start` |
| MS3 | Fix | A call app that releases the microphone for 8 s arms a stop that saves 9 s later, against the privacy doc | Detector signals only suggest. Nothing stops without a tap or the bound app closing |
| MS4 | Feature | Automatic start still asks on the first meeting, keeps its consent after being switched away, and can be selected by a settings import | Choosing it in Settings is the opt-in, at that click; any other choice withdraws it; an import can never select it |
| MS5 | Feature | Three lines of text, two equal buttons, no motion, no countdown you can see | A liquid-glass slab: orb with a countdown ring, call app tiles, status pill, title, time, one action; Join in the call app when the link is known; motion from the alert tokens; keyboard and VoiceOver |
| MS6 | Refactor | Two machines disagree on "did it start"; an automatic start fails silently; a Cancel can arrive too late | One machine from sighting to result; Starting, Recording or the true reason for taps and automatic starts alike; Cancel always wins |
| MS7 | Refactor | The heads-up is a second pipeline, gone 75 s before the meeting, never shown in automatic mode, sometimes never shown | An `upcoming` state in the same machine; the heads-up pipeline is deleted |
| MS8 | Feature | The detector polls every 5 s forever, in every mode | Stopped when Off, event driven when idle, polling only while a meeting is near |
| MS9 | QA | No app-level test activates the real card; F04.2 is unimplemented | An own-process journey that clicks the real controls with a fake clock |

Later (separate plans): landing the card under the notch inside the alert stack, the Scribe page "Up next"
wording, other end-window wording, the capture run flags in `ScribeLiveCapture.swift:142-146`.

## What changed after the review

Each finding was checked in the worktree. All were confirmed; the verdict stays "refactor first".

| Finding | Checked at | Change in this version |
| --- | --- | --- |
| Countdown can fire after Cancel | `ScribeAutoStartController.swift:130-141` (1 s repeating timer, default run-loop mode), `ScribeAutoStart.swift:402-415` (a decline in `.recording` does nothing) | `cancel(on:)` is its own event; the countdown card has no primary; Cancel stays through an automatic Starting and abandons the start; expiry is a one-shot at the deadline in common modes (MS6) |
| Cooldown plus `call:<App>` alias breaks dismissal | `ScribeAutoStart.swift:520-536` | `ScribeMeetingLedger` replaces the cooldown state, `switching`, and the watcher's dismissal sets; two calendar meetings never match through a shared app (MS1) |
| QA bindings moved too late | `test_source_lint.py:685-715`, `prepare.py:86-96`, `feature-map.json:1128-1150` | Every binding moves in the ticket that moves the code; the portable scribe group gains the machine in MS1 |
| "Parallel" waves shared files | plan | One serial lane for the machine and the controllers, one parallel lane for the card view; REG ids assigned up front |
| Automatic start shipped before the mic-release stop was fixed | `ScribeAutoStart.swift:494-499`, `ScribeController.swift:679-686, 1892-1898` | MS3 makes detector signals advisory by default and MS4 depends on it |
| Switch confirmed twice | `ScribeAutoStartTests.swift:640-658`, `ScribeAutoStart.swift:393-398` | Switch ends now and queues the next start once, with no second question (MS6) |
| A meeting held while saving was silent | plan | `held` state with a visible card and Cancel (MS6) |
| Opt-in recorded in a view binding; old stamp could arm it | `ScribeAutoStart.swift:205-219`, `SettingsStore.swift:108-113, 157-162` | New key, one-time launch migration, one seam in `SettingsStore.set` with an origin, never reached by an import (MS4) |
| Missing outcome rules | `ScribePopupLifecycle.swift:179-188, 232-239`, `ScribePopupDriver.swift:96-97`, `ScribeController.swift:1160, 1801` | Written out in MS6: what `starting` and `failed` ignore, the late success, the phase read right after `start`, the `didSet` seam |
| Controller untestable | `ScribeAutoStartController.swift:11-24` | Ports for Scribe, clock, scheduler, panel and microphone access (MS6); factories for the watcher (MS8) |
| Debounce skipped from the heads-up | plan | `upcoming` goes to `armed`, which keeps the card (MS7) |
| Unknown link host never matched | `ScribeIdleLogic.swift:48-55` | The start-time card no longer needs a call app; only `.teams`, `.zoom`, `.meet` pair a live call (MS1) |
| Call binding for calendar starts | `ScribeAutoStartController.swift:121` | `callIdentity` only for a live meeting (MS2) |
| Brand glyph, missing call title | `ScribeLiveLogic.swift:567-577` | One generic symbol, call-only card title "Call" (MS0) |
| System-audio dialog assumed absent | `ScribeLiveCapture.swift:607-612` (a process tap is created at start) | Fail closed: automatic start is blocked until one recording has run on this Mac (MS4) |
| Ring could restart each second | plan | Ring keyed on the deadline, a lint check and a temporal test (MS5) |
| Prune by presence; launch start | `ScribeCallWatcher.swift:207` | Ledger entries leave by slot end; launch start is decision D3 |
| Item 8 overstated | `ScribeAutoStart.swift:459-462` | Reworded below: Off is handled on evidence; Ask me and the expiry path are not |

## What was found (verified in the worktree)

1. Early "Meeting started". `ScribeMeetingEvidence.candidate` accepts a calendar event from 120 s before its
   start with any call app merely open (`ScribeAutoStart.swift:114-124`, `:129`). The headline has no before or
   after form (`:620-622`). In automatic mode recording begins 5 s later.
2. Automatic start can record a room nobody joined. The same rule (link plus an open app, microphone not held)
   feeds the countdown. An open call app is not a call.
3. Silent automatic failure. Covered in the verdict above.
4. "Scribe is recording" before capture. `ScribePopupLifecycle` marks the card started when Scribe is only
   `.starting`, and for `.ending`, `.processing` and `.complete` (`ScribePopupLifecycle.swift:214-217, 243-244`);
   the view then draws `record.circle` (`ScribePopupDriver.swift:194-197`). `docs/DESIGN-DIRECTION.md` forbids a
   recording indicator before capture.
5. Two dismissal memories. Not now on the heads-up writes `dismissedIDs` in the watcher; the machine keeps its
   own cooldown key, so the banner asks again seconds later. `dismissedApps`, `dismissedInstances` and the
   `.callDetected` branch are dead: `decide` is always called with `activeCallApp: nil`
   (`ScribeCallWatcher.swift:343-350`).
6. One meeting, two names. The key is the slot id inside the calendar window and `call:<App>` outside it
   (`ScribeAutoStart.swift:117-123`); the cooldown treats the second name as a different meeting (`:530-533`).
   The window closes 5 minutes after the start, so every meeting longer than that changes name mid-call.
7. Saving read as "recording by hand". Any non-idle `ScribeActivity` cools the sighted meeting
   (`:440-444, 451, 460-462`), so a meeting that starts while the previous recap is processing is never offered.
8. A change to Ask me during the countdown is ignored. The evidence step reacts only to Off (`:459-462`) and
   the expiry re-checks microphone and consent, not the mode (`:569-574`).
9. Consent is a side effect of a meeting, never cleared. `ScribeAutoStartConsent` has `record` and no clear
   (`:205-219`). It survives switching to Ask me and back.
10. A settings import can select "Start automatically". `SettingsStore.importJSON` only blocks toggles turning
    on (`SettingsStore.swift:315`); `scribe.autoStart` is a live choice row (`scripts/gen-settings-catalog.py:224`).
    Today the separate consent stamp is the only thing that stops it.
11. Hints leak. `ScribeController.start()` returns at `:557-561` before it consumes `meetingTitleHint`,
    `meetingAttendeeHint` and `meetingCallHint` (`:570, 598-601`); they attach to the next unrelated start.
12. A detector signal stops a recording. The machine's `requestEnd` effect calls `ScribeController.requestEnd()`,
    which arms `Reason.requestedByUser` (`ScribeEndWorkflow.swift:51-53`), so the window reads "You asked to stop"
    (`ScribeEndWindow.swift:90-92`) and capture stops 9 s later (`ScribeController.swift:1897`).
    `docs/SCRIBE-PRIVACY-AND-END-FLOW.md` ("Real end triggers") says microphone disappearance is never treated
    as a call ending, and `qa/feature-map.json:200` requires "no idle-mic heuristic as call end".
13. Cancel can lose to the timer. Expiry runs on a 1 s repeating timer in the default run-loop mode
    (`ScribeAutoStartController.swift:131-136`), so it stalls during menu tracking and can land up to 1 s late.
    A Cancel that arrives after the machine moved on is a no-op (`ScribeAutoStart.swift:402-415`).
14. Switch asks twice. Switch opens the end window (a second question), then the next meeting is asked about
    again (`ScribeAutoStartTests.swift:640-658`). `ScribePhase.isActive` includes `.processing`
    (`ScribeSession.swift:21-25`), so the next recording cannot start until the last notes are saved.
15. The detector never stops. `ScribeCallWatcher.stop()` has no caller; the watcher starts inside
    `ScribeController.makeProduction` (`ScribeController.swift:436`), which the closed top bar's first draw
    already triggers (`TopBar/TopBarViews.swift:1351`); the calendar is read on every 5 s poll
    (`ScribeCallWatcher.swift:321-330, 364-385`); a wake-up that arrives while a scan runs is dropped (`:322`).
16. No app-level proof. No test under `Tests/ZeusAppTests` touches the watcher, the controller or either card.
    F04.2 and F04.3 are "unimplemented" (`qa/feature-map.json:169-181`). `ScribeAutoStartController` is a
    private-init singleton reading the system clock, the capture device and two other singletons directly.

Not verified here: how each call app reports a muted microphone to Core Audio, whether the first system-audio
tap raises a macOS dialog, and the notch overlay geometry. All three need a real Mac.

## Decisions the owner owes

None of these blocks the start of work; each has a safe default written into a ticket.

- D1, end of call. Default in MS3: every detector signal (microphone released, call window closed) only
  suggests an end. Only a tap, or the bound call app closing, stops a recording. The question for later: may a
  closed call window, for apps with a reliable title, stop after 9 s again? The fact needed first: whether
  muting inside each supported call app drops its input flag (a 30 s mute test per app on a Mac).
- D2, the control. This plan keeps one row with three choices (Off, Ask me, Start automatically) on the same
  stored key, drawn as a segmented control so all three are visible and no explanation is needed. The
  alternative is a switch for automatic start plus a switch for the cards: it needs two new keys and a
  migration. Changing this later touches MS4 only.
- D3, when the detector starts. Today it starts when the closed top bar first draws, a side effect of a view.
  MS8 makes that explicit: started at launch unless the choice is Off. The code comment at
  `ScribeCallWatcher.swift:207` says "never at app launch". Reading which process holds the microphone is not
  capture, but it is the default posture for every install, so the owner confirms it.
- D4, back-to-back meetings. Scribe runs one session at a time, and saving counts as running. Until the last
  notes are saved, the next recording cannot begin, so its opening is not recorded; the card says so and starts
  the moment Scribe is free. Letting a new session start while the previous recap saves is a change inside
  `ScribeController` and is outside this plan.
- D5, the card at the start time. Today a meeting gets a start-time card only when its link's call app is
  open. In this plan every calendar meeting with guests or a link gets one card two minutes before and one at
  its start, with or without a call app. Automatic recording still needs a live call. Say no and MS1 keeps
  the app condition.
- D6, the Reduce Transparency still. The first build dropped it: the setting is read-only in SwiftUI and
  `AlertGlass` has no override. The redrawn card has its own glass with one pure surface rule and an override on
  the view, so the still exists again. `AlertGlass` itself is untouched.
- D7, status lines. The first build allowed two lines for a failure and a blocked reason because the words
  wrapped at 340 pt. The redrawn right column is about 275 pt wide and the reasons fit on one line; a long free
  text reason from the capture is cut with an ellipsis and read in full by VoiceOver.

## Privacy and consent (rules that do not move)

- Capture starts only through `ScribeController.start`. No ticket adds a second entry point. The mute and
  admission code (`ScribeMicrophoneIngress`, `ScribeMicGate`, `MicInputOwnership`, `ScribeMuteMonitor`) is not
  edited by any ticket.
- The detector never asks macOS for a permission. The only new permission request is the owner's own click on
  "Start automatically" or "Allow" in Settings, and the macOS dialog is theirs to answer.
- Automatic start needs all of: the choice made in Settings on this Mac by a person, the opt-in stamp written by
  that click, Microphone already allowed, one earlier recording on this Mac, a call app holding the microphone,
  Scribe free, and a 5 s countdown that was not cancelled. Each is read again when the countdown ends. Anything
  missing means the card asks and says why; it never starts.
- Cancel always wins. A Cancel on a countdown, on the waiting card, or on an automatic Starting ends with
  nothing recorded and nothing saved.
- The default stays "Ask me". An import never selects automatic start and never carries the opt-in stamp.
- No recording word, dot or glow before `ScribePhase` is `.recording`.
- A recording is never stopped by a detector signal. Only a tap or the bound call app closing stops it.
- A call binding (process identity for the app-closed rule) is given only to a recording started on a live call.
- Calendar is read only when full access was already granted. Only display names leave a slot.
- No third-party product names are added to source or UI: the card uses one generic symbol and a call with no
  calendar meeting is titled "Call". Tests use synthetic slots, scans and phases.

## The machine at a glance (after MS7)

One pure value, `ScribeAutoStartMachine`, in `Sources/ZeusCore/Scribe/ScribeAutoStart.swift`.

- States: `idle`, `upcoming(meeting:deadline:)`, `armed(meeting:since:offerUntil:)`,
  `prompting(meeting:deadline:blocked:)`, `countingDown(meeting:deadline:)`, `held(meeting:startOwed:)`,
  `starting(ScribeStartAttempt)`, `recording(ScribeAutoStartRecording)`,
  `failed(meeting:failure:deadline:)`, `endingSuggested(meeting:since:)`.
- Memory: `ledger: ScribeMeetingLedger`. There is no cooldown state and no flag beside it.
- Events: `evidence(ScribeMeetingEvidence, now:)`, `scribe(ScribePhase, now:)`, `tick(now:context:)`,
  `primary(on: ScribeMeetingCard, now:context:)`, `cancel(on: ScribeMeetingCard, now:)`,
  `dismiss(on: ScribeMeetingCard, now:)`, `pointer(inside:now:)`. A tap carries the card the person saw; the
  machine reads only its case and its meeting.
- Effects: `start(ScribeMeeting)`, `abandonStart(ScribeSessionID)`, `openMicrophoneSettings`,
  `suggestEnd(ScribeMeeting)`, `withdrawEnd`, `endNow`. There is no show or hide effect.
- Views: `card(now:) -> ScribeMeetingCard` is the only source of what is on screen.
  `nextWake(now:) -> TimeInterval?` is the only source of when the app wakes; nil means nothing is scheduled.

## MS0. The card contract

### Behaviour

Nothing visible changes. This ticket freezes the value the card is drawn from and every word on it, so the
view (MS5) and the machine (MS1 to MS7) can be built in separate worktrees.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Scribe/ScribeMeetingCard.swift`:

- `ScribeStartFailure`: `microphoneOff`, `stillSaving`, `captureFailed(String)`, `noResponse`.
- `ScribeAutoStartBlock`: `notChosen`, `noOptIn`, `microphoneNotAsked`, `microphoneDenied`, `firstRecordingOwed`.
- `ScribeMeetingCard`: `hidden`, `offer(ScribeMeeting, blocked: ScribeAutoStartBlock?)`,
  `countdown(ScribeMeeting, seconds: Int, deadline: TimeInterval, total: TimeInterval)`,
  `waiting(ScribeMeeting)`, `starting(ScribeMeeting, cancellable: Bool)`, `recording(ScribeMeeting)`,
  `failed(ScribeMeeting, ScribeStartFailure)`, `next(ScribeMeeting)`.
- `ScribeMeetingCardText`:
  - `title(_:)`: the meeting title, "Meeting" when empty, "Call" for a call with no calendar meeting.
  - `time(startsAt:now:)`: "in N min" (rounded up) before the start, "now" from the start.
  - `status(_:now:)`: the time for `offer` and `next`; the block reason for a blocked `offer`; "Recording starts
    in N"; "Starts once your last meeting is saved"; "Starting"; "Recording"; or the failure reason.
  - `reason(_ failure:)`: "Microphone is off for Zeus", "Still saving your last meeting", Scribe's own capture
    reason or "Couldn't start", "Didn't start".
  - `reason(_ block:)`: "Microphone is off for Zeus", "Microphone not allowed yet", "Automatic start needs one
    recording first"; nil for `notChosen` and `noOptIn`.
  - `primary(_:) -> String?`: "Record" for `offer`, "Allow" for `failed(.microphoneOff)`, "Try again" for the
    other failures, "Switch" for `next`; nil for `countdown`, `waiting`, `starting`, `recording`.
  - `cancel(_:) -> String?`: "Cancel" for `countdown`, `waiting` and a cancellable `starting`; nil otherwise.
  - `canDismiss(_:)`: true for `offer`, `failed`, `next`.
  - `symbol`: `video.fill` for every card.
  - `seconds(deadline:now:)` (whole seconds left, counting the one in progress) and
    `ring(deadline:now:total:)` (the share left, clamped 0 to 1).
  - `label(_:now:)` ("<title>, <status>"), `announcement(_:now:)` and `accessibilityValue(_:)`.
  - `now` in `time`, `status`, `label` and `announcement` is a wall-clock `Date`. The countdown digit is the
    card's own `seconds`, which the machine refreshes at each wake; `seconds(deadline:now:)` and `ring` take the
    machine's uptime, and only the machine and the ring view call them.
- `ScribeMeetingCardPlacement.origin(size:visibleFrame:margin:)`: top right of the given screen frame.

### Tests first (`Tests/ZeusCoreTests/ScribeMeetingCardTests.swift`, new)

One row per card for title, status, primary, cancel and dismiss. Exactly one of primary and cancel is set for
every visible card except `recording`. `countdown` has no primary. "Recording" is the status of the
`recording` card only. Time text at 121 s, 120 s, 61 s, 60 s, 1 s, 0 s and after. Ring share at 5, 2.5 and 0 s
and past the deadline. Placement inside a frame with a margin. No string contains a dash or a product name.

QA in this ticket: the file and its suite join the scribe group in `qa/portable-core/prepare.py`. REG-410 to
REG-429 are reserved in `qa/regressions.json` for this plan (agree the range with the other worktrees first).

## MS1. Meeting identity, the windows and the ledger

### Behaviour

- A calendar meeting counts as started from its start time, not before.
- Automatic start counts down only for a live call (a call app holds the microphone). A meeting that has
  merely reached its start time is asked about, in both modes.
- One meeting has one name for its whole life: from two minutes before its start to its end, a live call in
  the meeting's app is that meeting.
- An answer covers the whole meeting. Not now, Cancel, or a recording that was started: nothing more is shown
  for that meeting, before, during or after its calendar window, and when it runs over.
- An unanswered card is not an answer. In "Start automatically", a card that timed out does not stop the
  countdown when the call begins.
- Two calendar meetings back to back in the same app are two meetings. The second is offered.
- A different meeting is offered as soon as it appears; there is no waiting time between meetings.

The first commit only moves types to `ScribeMeetingSignals.swift`; it changes no behaviour and no test.

### Rules (ZeusCore, pure)

In `ScribeMeetingSignals.swift`:

- `ScribeCalendarSlot.callApp: ScribeCallApp?`: the app of the event's link, set by the calendar reader.
- `ScribeMeeting`: `key` (the slot id, else `call:<App>`), `title`, `callApp: ScribeCallApp?`, `slot`,
  `isLive: Bool`.
- `ScribeMeetingStartPolicy`:
  - `liveSlot(in:micApps:at:)`: a slot with a link, from `leadWindow` before its start until its end (or
    `lateWindow` after the start when it has no end). A slot whose `callApp` is `.teams`, `.zoom` or `.meet`
    pairs only with that app holding the microphone; any other slot pairs with the first app that holds it.
    Among slots already started the latest start wins; a slot not yet started pairs only when none has started.
  - `startedSlot(in:at:)`: a slot with `0 <= date - start <= lateWindow`, not ended; the latest start wins.
- `ScribeMeetingEvidence.candidate`: live when `micApps` is not empty (the paired slot gives the key and
  title, else `call:<App>` and "Call"); otherwise scheduled when `startedSlot` exists (`isLive` false,
  `callApp` the slot's known app or nil); otherwise nil. No call to `ScribeCallPromptText`.

New file `Sources/ZeusCore/Scribe/ScribeMeetingLedger.swift`:

- `ScribeMeetingLedger.Mark` (ordered): `headsUp`, `asked`, `declined`, `started`. `isAnswered` is true from
  `declined` up.
- `note(_ meeting:_ mark:date:)`: a mark never goes down. A meeting with a slot gets a slot entry kept until
  the slot's end (or `start + lateWindow`). A live meeting also gets a call entry for its app, which records
  the slot it belongs to.
- `mark(of meeting:)`: for a meeting with a slot, its slot entry. If it has none and it is live, a call entry
  for its app that belongs to no slot yet adopts this slot, and that mark is returned (a call answered before
  its calendar window opened stays answered). For a call with no slot, the call entry of its app.
- `observe(_ evidence:now:)`: slot entries leave at their date. A call entry leaves when its app left
  `presentApps` or has not held the microphone for `rearmAfterAbsence` (30 s).

In `ScribeAutoStart.swift`:

- The `cooldown` state, `ScribeAutoStartCooldown`, the `switching` flag and `ScribeAutoStartTiming.cooldown`
  are deleted. After a meeting is handled the state is `idle` and the ledger holds the mark: `declined` for
  Not now and Cancel, `asked` for a timeout, `started` for a start, for a recording seen that this machine
  did not start, and for a recording that ended.
- From `idle`: an answered candidate is ignored. A candidate marked `asked` is ignored unless it would count
  down. `armed(_:)` goes to `countingDown` only when the meeting `isLive`.
- A recording whose meeting had no live app adopts the app when the same meeting goes live, so the end rules
  watch the right process.

App side, one line: `ScribeCallWatcher.upcomingSlots` sets `callApp` from `ScribeUpNext.callApp(link:)`.

### Tests first

`Tests/ZeusCoreTests/ScribeMeetingLedgerTests.swift` (new): `dismissAtTwoMinutesStaysQuietAtStartTime`,
`aBackToBackMeetingInTheSameAppIsOffered`, `aDismissedCallStaysQuietWhenItsCalendarWindowOpens`,
`aDismissedMeetingStaysQuietWhenItRunsOver`, `aNewCallInTheSameAppAfterAGapIsANewMeeting`,
`marksNeverGoDown`, `entriesLeaveWhenTheSlotEnds`.

`ScribeAutoStartTests.swift`: `aLinkMeetingIsNotStartedBeforeItsStartTime` (119 s early with its app open: no
candidate; at the start: scheduled), `aLiveCallBeforeTheStartCarriesTheMeetingTitle`,
`automaticNeverCountsDownWithoutALiveCall`, `aCalendarMeetingIsOfferedAtItsStartWithNoCallAppOpen`,
`anUnansweredCardDoesNotBlockTheAutomaticCountdown`, `aDifferentMeetingArmsWithoutWaiting`,
`twoLinkMeetingsInWindowThePairedAppTitlesTheCall`, `aCallNearTheNextMeetingKeepsItsOwnName`. The three
cooldown cases (`:410`, `:429`, `:441`) and the Switch case (`:640`) are rewritten against the ledger.

QA in this ticket: `prepare.py` scribe group gains `ScribeAutoStart.swift`, `ScribeMeetingSignals.swift`,
`ScribeMeetingLedger.swift`, `ScribeAutoStartTests` and `ScribeMeetingLedgerTests`, plus an excerpt of
`FeatureSettings.swift` from `public enum FeatureSettings {` to `// MARK: Fast path` (the whole file needs
types the group does not carry). REG-410 (early start), REG-411 (countdown without a call) and REG-412 (one
meeting, two names) are added with these guards, check `portable-scribe`.

## MS2. Meeting context as a value

### Behaviour

A recording gets the title, guests and call binding of the meeting it was started for, or none. A refused
start leaves nothing behind. Only a recording started on a live call is bound to the call app's process.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Scribe/ScribeMeetingContext.swift`:

- `ScribeMeetingContext`: `title: String?`, `attendeeNames: [String]`, `callIdentity: ScribeCallProcessIdentity?`.
- `ScribeMeeting.context(callIdentity:)`: an empty title is nil; a call with no slot keeps today's recap title
  ("<App> call", the line moved from `ScribeCallPromptText.meetingTitle`); names pass through
  `ScribeAttendeeNames.clean`; `callIdentity` is kept only when `isLive`.

App side: `ScribeController.start(context: ScribeMeetingContext? = nil)`. The properties `meetingTitleHint`,
`meetingAttendeeHint` and `meetingCallHint` are deleted. Callers: `ScribeAutoStartController.startScribe`,
`ScribeCallPopup.startScribe` (until MS7 deletes it), `ScribeIdleView.swift:168-172`,
`ScribeLifecycleScenarioTests.swift:131`.

### Tests first

`Tests/ZeusCoreTests/ScribeMeetingContextTests.swift` (new): context from a slot meeting, from a call with no
slot, an empty title, `aHeadsUpStartHasNoCallBinding`, a live meeting keeps its binding.
`Tests/ZeusAppTests/ScribeLifecycleScenarioTests.swift`: `aRefusedStartLeavesNoContextBehind` (a start refused
while a session is active, then a plain start, has no title, no guests and no call binding).

QA in this ticket: the new file and suite join the scribe group. REG-413 (leaked hints) is added.

## MS3. Detector signals only suggest an end

### Behaviour

- When the call app lets go of the microphone for 8 s, or its call window closes, the end window opens and says
  "The call looks over", with End meeting now and Keep recording. There is no countdown. Nothing stops until a
  button is tapped.
- If the call takes the microphone again, the window closes by itself.
- Stop on the Scribe page and the bound call app closing work as today, with the 9 s window.
- Switch (next-meeting card) is an explicit request and keeps today's behaviour until MS6.

Other end-window wording is out of scope.

### Rules (ZeusCore, pure)

`ScribeEndWorkflow.swift`:

- `Reason.callLooksOver`. `suggestEnd(session:now:) -> Bool` sets the reason and `isSuggested`, with no deadline.
  A second suggestion does not rearm. `withdrawSuggestion(session:)`.
- `stopIfDue` is unchanged and therefore never fires for a suggestion. `keepRecording` also clears a
  suggestion. `requestEnd` and `applicationTerminated` replace a suggestion with their own 9 s deadline.

`ScribeAutoStart.swift`: the detector path emits `Effect.suggestEnd(ScribeMeeting)`; `requestEnd` stays for
Switch only. `ScribeAutoStartRecording.endSuggested`; when the call app holds the microphone again it emits
`Effect.withdrawEnd`.

App side: `ScribeController.suggestEnd()` (phase stays `.recording`, the end window opens),
`withdrawEndSuggestion()`, `var endSuggested: Bool`. End meeting now on a suggestion runs `requestEnd()` then
`confirmEnd()`. `ScribeEndWindow.swift:84-100` gains the suggestion case: the header "The call looks over" and
the same two buttons, no second line. `docs/SCRIBE-PRIVACY-AND-END-FLOW.md` "Real end triggers" gets a dated
paragraph: detector signals open a suggestion that never stops capture.

### Tests first

`ScribeEndWorkflowTests` (portable): `microphoneReleaseNeverStopsOnItsOwn` (suggest, then `stopIfDue` an hour
later is false), Keep clears a suggestion, an explicit Stop after a suggestion arms `requestedByUser` with 9 s,
a duplicate suggestion does not rearm, the bound app closing after a suggestion arms `boundCallAppClosed`.
`ScribeAutoStartTests`: microphone release and a closed call window emit `suggestEnd`, never `requestEnd`; the
microphone coming back emits `withdrawEnd`; Switch still emits `requestEnd`.
`ScribeLifecycleScenarioTests`: a suggestion leaves the phase `.recording` after 60 s of the injected clock;
End meeting now on it stops the provider once.

QA in this ticket: REG-414 (microphone release stopped a recording), guard `microphoneReleaseNeverStopsOnItsOwn`.

## MS4. Automatic start is switched on in Settings

Depends on MS3: automatic start does not become a one-click opt-in while a detector signal can still stop and
save a recording.

### Behaviour

- Settings, Features, Scribe: one row, "When a meeting starts", with three segments: Off, Ask me, Start
  automatically. No text under it. The end-of-call paragraph is removed.
- Clicking "Start automatically" is the opt-in. If macOS has not yet asked about the microphone, that click asks.
  The next live meeting counts down; there is no consent card.
- When automatic start is chosen and something blocks it, one more row appears and says what: "Microphone is
  off for Zeus" with Allow (opens System Settings), "Microphone not allowed yet" with Allow (asks macOS), or
  "Automatic start needs one recording first". The row is absent when nothing is blocked.
- Choosing Off or Ask me, or resetting the section, withdraws the opt-in.
- A settings import leaves this row alone when the file says "Start automatically".
- An opt-in given under the old consent card carries over only if "Start automatically" is the current choice
  at the first launch of this version.
- Leaving "Start automatically" during a countdown ends the countdown and asks instead.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Scribe/ScribeAutoStartOptIn.swift`:

- `ScribeAutoStartOptIn`: `key = "scribe.autoStart.optInAt"`, `legacyKey = "scribe.autoStart.consentAt"`,
  `firstRecordingKey = "scribe.firstRecordingAt"`.
  - `migrate(mode:hasSavedMeetings:defaults:)`, run once at launch: a legacy stamp is copied to `key` only when
    the mode is `.automatic`; the legacy key is always removed; `firstRecordingKey` is written when this Mac
    already holds a saved meeting.
  - `record(mode:now:defaults:)`: writes the stamp for `.automatic`, removes it for any other mode.
  - `reconcile(mode:defaults:)`: removes a stamp found while the mode is not automatic.
  - `noteRecordingBegan(now:defaults:)` (writes `firstRecordingKey` once), `date(defaults:)`, `hasRecorded(defaults:)`.
- `ScribeMicrophoneAccess`: `allowed`, `notAsked`, `denied` (restricted counts as denied).
- `ScribeAutoStartReadiness`: `ready` or `blocked(ScribeAutoStartBlock)`.
  `resolve(mode:optIn:microphone:hasRecorded:)` checks in this order: `notChosen`, `noOptIn`,
  `microphoneDenied`, `microphoneNotAsked`, `firstRecordingOwed`.
- `ScribeMeetingEvidence.automatic: ScribeAutoStartReadiness` replaces `micPermissionGranted` and
  `autoConsentGiven`. The machine counts down only on `.ready` and `isLive`, and reads the mode, the readiness
  and `isLive` again on every evidence during the countdown and at its end; anything missing asks instead.
- Deleted: `ScribeAutoStartConsent`, `Effect.showConsentAsk`, `Effect.recordConsent`, the consent reads of
  `lastEvidence`, `ScribeMeetingBanner.showConsent`.

App side:

- `SettingsStore.set(_:_:origin:)` with `ChangeOrigin`: `person` (the default), `reset`, `importFile`. For the id
  `scribe.autoStart` it calls `ScribeAutoStartOptIn.record`, with `.automatic` honoured only for `.person`; for
  `.person` and `.automatic` with access `notAsked` it requests the microphone through
  `PermissionPrompts.shared.run("microphone")`, so a double click raises one prompt. Nothing runs in snapshots.
- `SettingsStore.neverChosenByImport: [String: Set<String>]` holds `["scribe.autoStart": ["Start automatically"]]`
  and is checked beside `neverEnabledByImport` (`SettingsStore.swift:315`); `importJSON` passes `.importFile`.
  The stamp keys stay out of `appRules`, so they are never exported or imported.
- `AppDelegate.applicationDidFinishLaunching` runs `migrate` before anything touches `ScribeController.shared`.
  `ScribeAutoStartController.ingest` runs `reconcile`. `ScribeController` calls `noteRecordingBegan` where it
  reacts to `recordingStarted` (`ScribeController.swift:1190-1192`).

Residual, accepted: two raw `defaults write` commands by the owner on a Mac that already holds a real opt-in
can bring it back without a click.

### Design

- `GlassSegmented` (`Sources/Zeus/App/GlassTheme.swift:356`) as the row's trailing control. The accessibility
  value is the chosen segment.
- The blocked row uses `GSRow` with symbol `mic.slash` (or `record.circle` for the recording rule), the title
  only, and a `GSButtonStyle` button where there is a fix. Its words come from `ScribeMeetingCardText.reason`,
  the same words as the card.
- `scripts/gen-settings-catalog.py:224` note updated; `SettingsCatalog.swift` and the inventory regenerated,
  never edited by hand. `docs/FIRST-RUN-DEFAULTS.md:17` rewritten to these rules.

### Tests first

`Tests/ZeusCoreTests/ScribeAutoStartOptInTests.swift` (new): `choosingAnotherModeWithdrawsTheOptIn`,
`aStaleStampWithAskMeIsRemovedAtLaunch`, an old stamp with automatic carries over,
`aDefaultsWriteOfAutomaticWithoutTheClickIsNotReady`, every `resolve` combination in order.
`ScribeAutoStartTests`: `.blocked` of each kind asks and never counts down; `.ready` counts down on the first
live meeting; `leavingAutomaticDuringTheCountdownAsksInstead` (to Ask me at second 3, and to Off at second 3);
readiness lost at the end of the countdown asks.
`Tests/ZeusAppTests/SettingsCatalogTests.swift`: `anImportNeverChoosesStartAutomatically` (nothing changes, no
stamp), an import with "Off" applies and removes the stamp, `aSectionResetWithdrawsTheOptIn`.
`SettingsConsumerTests`: a `scribe.autoStart` consumer row. `FirstRunDefaultsTests`: default "Ask me", no stamp.

QA in this ticket: the new file and suite join the scribe group. REG-415 (import), REG-416 (consent outlives
the choice), REG-417 (mode change ignored in the countdown).

## MS5. The card

Builds the view and the panel from the MS0 contract. Not wired until MS6, so it can be built in a parallel
worktree while MS1 to MS4 land. Behaviour, states and actions are as first planned; the look, the layout and the
motion were redrawn after the owner's reference, a premium liquid-glass meeting reminder. Zeus draws all of it
in its own code; no third-party logo or image is bundled.

### Behaviour and design

- One wide liquid-glass slab, 440 pt wide and 156 pt tall, continuous corner radius 32 pt, in a window that adds
  24 pt of room on every side for its shadow. The slab sits 24 pt from the top and right edges of the visible
  frame (below the menu bar), so the window is flush with the corner and the margin is even.
- Material: the system behind-window blur, strongly blurred, with a cool blue-violet tint on top; a luminous
  rim of 1.25 pt, brightest along the top and top-left, with a faint glow; a soft inner highlight near the top
  edge; a wide soft shadow. Reduce Transparency swaps the blur for an opaque deep blue surface and keeps the
  same rim, highlight and shadow. The surface is chosen by one pure rule so a test and a still can both reach it.
- Left column, 30 percent of the width, closed by a thin vertical hairline. A glowing glass orb of 64 pt with a
  white calendar symbol; the countdown ring is a circle around it. Under it a row of rounded 22 pt tiles, one per
  call app the meeting can open in: real icons read at run time from the installed apps, only apps that match
  the meeting link, at most four, none when Zeus has no link. Matching means the app of the link's provider,
  when it is installed, then the installed browsers that open it, the default one first. The first tile is the
  app the primary action uses.
- Right column, top to bottom:
  - A status pill (translucent, a small coloured dot and a short phrase): "Starting soon" for the offer and the
    next meeting, "Recording in N" while counting down, "Waiting to record", "Starting", "Recording",
    "Not recorded" for a failure. Violet dot before the start, red while recording, orange for a failure.
  - The title, 24 pt bold, one line, tail truncation.
  - A clock symbol, the time range, a thin divider, then the relative time in the accent violet ("In 5 min",
    "Now"). A call with no calendar meeting has no range and shows only the relative time.
  - A people symbol and "N participants", only when the calendar gives names; it counts the named guests and
    the owner. In the states that carry a reason this line holds the reason instead: the blocked reason, the
    failure reason, or "Starts once your last meeting is saved". One line, tail truncation (D7); the spoken
    label carries the full words.
  - At the bottom one wide translucent capsule for the primary action of the state, with a symbol; where the
    card can be dismissed, a round translucent close button at the top right.
- Primary action by state:
  - Offer with a link Zeus already holds (the calendar slot carries it): "Join in <app>" opens the link in the
    first matching app. A chevron opens a small menu of the other matching apps and, last, "Record", so the
    offer keeps its old action. Recording still follows the owner's chosen mode exactly as the plan defines;
    Join only opens the call.
  - Offer without a link, a failure and the next meeting: the state's own action (Record, Allow, Try again,
    Switch). Countdown, waiting and a cancellable start: Cancel. Starting without Cancel and recording: no
    button; the slot stays empty so the card does not change size.
  - The close button is the existing dismiss. It appears when the pointer is over the card (the panel reports
    the pointer) and stays reachable for VoiceOver and the keyboard at rest. Return is the primary action,
    Escape is Cancel or dismiss.
- Countdown: the pill reads "Recording in N"; the capsule is Cancel; a thin ring around the orb drains over the
  5 s. No close button and no Record, so there is exactly one action. The orb glow breathes very slowly, one
  finite pass over the countdown, and only while counting down.
- Starting: a small spinner replaces the pill dot. An automatic start keeps Cancel in the same place, so a tap
  already on its way still lands on Cancel. No red.
- Recording: the pill reads "Recording" for 1.5 s, then the card leaves. The top bar wings stay the real
  indicator.
- Motion uses `AlertStyle` and `AlertMotion` only: in with the alert spring, a scale from 0.96, a fade and a 6 pt
  downward drift; a state change swaps the right column with a short crossfade and the slab never jumps; out
  with a fade while drifting up. The ring is one linear animation keyed on the deadline (`.id(deadline)`),
  started with the time left; the per-second redraw never restarts it. Reduce Motion: fades only, no scale, no
  drift, no ring sweep and no breathing; the digit still counts.
- Never a text field, chat area or reply box. The pill, the time line and the participants line are the only
  labels beyond the old status words.
- Keyboard: `.defaultAction` on the primary and `.cancelAction` on Cancel or dismiss, active when the card is
  key. The panel stays non-activating and never takes the keyboard from the call.
- VoiceOver: one element for the words, labelled "<title>, <status>"; buttons named by their titles and
  "Dismiss"; no hints. One announcement per state. The countdown is never announced each second; Cancel exposes
  the seconds as its value.
- Placement: top right of the active screen, from `ScribeMeetingCardPlacement`. Moving it under the notch needs
  the alert stack to host a card with a button, which is a separate plan.

App files: `Sources/Zeus/Scribe/ScribeMeetingCardView.swift` (a function of one `ScribeMeetingCard`, the two
clock readings, the join apps, the pointer flag and four closures: primary, cancel, dismiss and join, each handed
the card it drew; the pointer is reported by `ScribeCardHostingView`; it stores no meeting, string or phase),
`ScribeMeetingCardGlass.swift` (the surface), `ScribeJoinApps.swift` (finds the installed apps and opens the link)
and `ScribeMeetingCardPanel.swift` (`protocol ScribeMeetingCardRendering { func render(_ card: ScribeMeetingCard) }`,
one non-activating panel using `ScribeCardHostingView`; `render` shows, updates or orders out and is the only
way the panel leaves). Core adds the metrics, the pill words, the time and participants lines and the join app
choice to `ScribeMeetingCard.swift` and `ScribeJoinApps.swift`. Controls carry `ownedJourneyControl` ids
`scribe.meetingCard.primary`, `scribe.meetingCard.cancel`, `scribe.meetingCard.dismiss` and
`scribe.meetingCard.apps`.

The link: `ScribeCalendarSlot` gains `callLink: URL?` (default nil) and the watcher fills it from the event, where it
already searched for the link. Only the Join action reads it; it is never logged or stored. A meeting without
`callLink` keeps the old Record action, so the card works before any watcher change lands. `AppBrandCatalog`
brands for call apps list the hosts of their links, so the provider of a link is found from the catalog.

### Tests first

- `qa/closed-loop/tests/test_meeting_card_lint.py` (new): the two files contain no `Timer`, `TimelineView` or
  `repeatForever`; the view declares no `@State` holding a meeting; the ring is keyed with `.id(` on the
  deadline; the panel orders out only inside `render`; the panel hosts with `ScribeCardHostingView(rootView:`;
  the view draws on the card glass and has no text field.
- Core tests: the metrics (size, radius, left column share, orb, tile, at most four apps), the placement rule
  with the shadow room, the pill words and tone per state, the time and participants lines, which controls
  show on hover per state, the join app choice.
- Snapshot fixtures through `SnapshotRenderer`, 1x and 2x: offer with a short and a long title, "in 2 min",
  "now" and a blocked reason, countdown at 5, 3 and 1, waiting, starting with and without Cancel, recording,
  each failure, next meeting, the hover variant, a card with no link, the Reduce Transparency still, and cards
  over a busy colourful backdrop so the glass shows.
- A temporal test in `Tests/ZeusAppTests/ScribeMeetingCardMotionTests.swift` (new): the countdown rendered at
  0, 1.5, 3 and 4.9 s with an injected animation clock; the ring share falls steadily across the per-second
  redraws; with Reduce Motion there is no sweep and the digit still counts. The pixel reads sample the band
  of the ring around the orb.
- App tests: the hosted card has the planned size, no state draws a text field, the Reduce Transparency surface
  is opaque and the default one is not, the pointer reaches the view, Join and the menu hand over their app.

## MS6. One machine from sighting to result

Needs MS4 and MS5. The largest ticket; its core half is written test first.

### Behaviour

- After Record, or when the countdown ends, the card says Starting. When capture has begun it says Recording
  for 1.5 s and leaves. If capture does not begin, the card says why and offers the fix. Taps and automatic
  starts behave the same.
- Cancel always wins. On the countdown it ends the countdown. On an automatic Starting, and for the 1.5 s of
  its Recording confirmation, it throws that start away: nothing is saved and no note appears in Meetings.
  A Cancel never starts anything. Starting after a Record tap has no Cancel, and a stray close never cancels
  a start the person asked for.
- With "Start automatically" chosen and Microphone denied, the card shows that reason with Allow. With the
  microphone not yet asked, or no recording yet on this Mac, the card shows the reason with Record.
- A meeting sighted while Scribe is still ending or saving the last one is not dropped. Its card says "Starts
  once your last meeting is saved" with Cancel. When Scribe is free, automatic mode starts its 5 s countdown,
  and Ask me shows Record. A Record tap while Scribe is saving is kept and starts the moment Scribe is free.
- Switch (next-meeting card) ends the current recording at once, with no second question, and starts the next
  meeting once when the last notes are saved. Until then the card is the waiting card.
- After a failure leaves, the meeting is handled. Nothing retries by itself.
- A tap is never lost: a Record tap on an offer that ended in the same instant still starts that meeting,
  unless a countdown, a start or a recording is already under way.

### Rules (ZeusCore, pure)

`ScribeAutoStartMachine` keeps its name and file.

- `ScribeStartContext`: `scribe: ScribePhase`, `microphone: ScribeMicrophoneAccess`,
  `automatic: ScribeAutoStartReadiness`, read by the app at the moment of each event. The evidence carries one;
  `lastEvidence` is deleted.
- `ScribeStartAttempt`: `meeting`, `since`, `origin` (`tap` or `automatic`), `previousSession`, `session`.
  `ScribeAutoStartRecording` gains `origin`, `session` and `confirmUntil`.
- Events and effects as listed in "The machine at a glance". `accept`, `decline`, `startNow` and every show and
  hide effect are deleted.
- Start rules:
  - `primary(on: offer(m))` with the microphone denied goes to `failed(.microphoneOff)`.
  - A start (tap or countdown end) while Scribe is `.starting` or `.recording` adopts that session and starts
    nothing. While Scribe is `.ending` or `.processing` it goes to `held(m, startOwed:)`.
  - Otherwise it emits `start(m)` exactly once and enters `starting`.
- Outcome rules, ported from `ScribePopupLifecycle.swift:197-252`:
  - A session equal to `previousSession` is never this attempt's result.
  - `.starting` keeps Starting; `.recording` confirms for `confirmFor` 1.5 s; `.failed(_, reason)` becomes
    `failed(.captureFailed(reason))`; `.ending`, `.processing` or `.complete` of the new session hide the card.
  - Right after the `start` effect the app sends `scribe(port.phase)` in the same turn. A phase still saving the
    previous session fails at once as `stillSaving`. No new session within `startTimeout` 5 s, or 45 s once the
    session is `.starting`, becomes `failed(.noResponse)`.
  - `failed(.noResponse)` still accepts the attempt's new session and moves to `recording`.
  - `starting` and `failed` react only to `scribe`, `tick`, `primary`, `cancel`, `dismiss` and `pointer`.
    Evidence, a mode change (including Off) and the meeting going away never take the card down.
  - A failure stays `failureLifetime` 60 s, longer under the pointer, then the ledger marks the meeting.
- Cancel rules: `cancel(on:)` for meeting `m` ends `countingDown(m)` and `held(m)` with the mark `declined`. In
  `starting` or in `recording` before `confirmUntil`, for the same meeting and `origin == .automatic`, it emits
  `abandonStart(session)` and marks `declined`. In every other case it does nothing. No path from `cancel`
  emits `start`.
- Late tap: `primary(on: offer(m))` when that offer is no longer the state starts `m` from `idle`, `armed`,
  `upcoming` or another offer; it is ignored and logged in `countingDown`, `held`, `starting`, `recording` and
  `failed`. A late tap never applies to a countdown card.
- Held rules: `held(m, startOwed: false)` (automatic, sighted while saving) goes to `countingDown` when Scribe
  is free and the meeting is still live and ready, to `prompting` when it is not ready, to `idle` when it is
  gone. `held(m, startOwed: true)` (a tap, or Switch) emits `start(m)` once with origin `tap` when Scribe is
  free. In `idle` and `armed`, a candidate seen while Scribe saves is held, not marked; only a recording this
  machine did not start (`.starting` or `.recording`) marks it `started`.
- Switch: `primary(on: next(n))` emits `endNow` and enters `held(n, startOwed: true)`. `requestEnd` is deleted.
- `card(now:)` and `nextWake(now:)`: the mapping is one switch over the state. `nextWake` returns the earliest
  of the state's deadline, the next whole second of a countdown, the minute boundary of an offer's time, and
  one second ahead while the call looks over; nil in `idle`.
- `ScribeAutoStartTiming` gains `startTimeout`, `slowStartTimeout`, `confirmFor`, `failureLifetime`; `startGrace`
  is deleted.

App side:

- `protocol ScribeStartPort`: `phase`, `onPhaseChange`, `start(context:)`, `cancel(session:)`, `endNow()`,
  `suggestEnd()`, `withdrawEndSuggestion()`. `ScribeController` conforms. `cancel(session:)` is the existing
  discard path (`ScribeController.swift:738-758`) guarded by the session id. `endNow()` arms and confirms an
  explicit end without opening the end window. `onPhaseChange` fires from a `didSet` on
  `ScribeController.machine`, which covers both writers (`:1160` and the reset at `:1801`), and replaces
  `ScribeCallWatcher.recordingDidStart()` (`:658`).
- `ScribeAutoStartController.init(scribe: ScribeStartPort, clock: @escaping () -> TimeInterval,
  scheduler: ScribeOneShotScheduling, panel: ScribeMeetingCardRendering,
  microphone: @escaping () -> ScribeMicrophoneAccess)`; `.shared` is the production composition. After every
  event it performs the effects, calls `panel.render(machine.card(now:))`, re-arms one one-shot wake at
  `machine.nextWake(now:)`, and logs each state change once (`[ZEUS] scribe meeting: <state>` and
  `FlightRecorder`). The production scheduler is one timer added to the main run loop in `.common` modes. No
  repeating timer remains.
- `ScribeMeetingBanner.swift` is deleted. `ScribeCallPopup` is untouched except its guard, which reads the
  panel's visibility (`ScribeCallPopup.swift:111`), until MS7 deletes it.
- `docs/STATE-MACHINES.md` item 23 is rewritten to the states above.

### Tests first

`Tests/ZeusCoreTests/ScribeMeetingStartOutcomeTests.swift` (new), with the REG-402 to REG-407 function names
kept: `aDoubleTapStartsScribeOnlyOnce`, `aTapWhileTheAutomaticStartIsRunningConfirmsInsteadOfStartingTwice`,
`theCardNeverExpiresUnderThePointer`, `aCaptureFailureIsShownWithItsReason`,
`theMicrophoneBeingOffIsSaidAndAllowOpensSettings`, `aStaleFailureFromThePreviousMeetingIsNotThisTapsFailure`,
and the other ported cases (`aStrayCloseNeverCancelsAStartInFlight`, the slow start, the confirmation).
New: `aCountdownThatEndsGoesToStartingNeverStraightToRecording`, `anAutomaticStartThatFailsShowsItsReason`,
`recordingAppearsOnlyForTheRecordingPhase`, `cancelAtTheSameInstantAsExpiryNeverRecords`,
`cancelAfterExpiryAbandonsTheAutomaticStart`, `cancelDuringTheConfirmationDiscardsTheAutomaticStart`,
`aCancelNeverStartsAnything`, `modeOffDuringStartingKeepsTheCard`, `aSlowStartAfterNoResponseBecomesRecording`,
`aStartRefusedWhileSavingSaysSoAtOnce`, `aMeetingHeldWhileSavingIsShownAndStartsWhenFree`,
`aRecordTapWhileSavingStartsOnceWhenFree`, `switchStartsTheNextMeetingOnceWithoutAskingAgain` (replaces the case
at `ScribeAutoStartTests.swift:640`), `automaticWithTheMicrophoneDeniedShowsAllow`,
`afterAFailureLeavesTheMeetingIsHandled`, one row per state for `card(now:)` and for `nextWake(now:)`, and
`nothingIsScheduledWhenIdle`. `aTapThatArrivesJustAfterTheTimeoutStillStarts` (REG-409) and
`askMeNeverTimesOutUnderThePointer` (REG-408) keep their names in `ScribeAutoStartTests`.

QA in this ticket:

- `test_source_lint.py`: REG-400's test checks `ScribeMeetingCardPanel.swift` in place of the banner (the popup
  check stays until MS7). REG-401's test asserts that the panel has no hide path except `render`, that the
  controller renders `machine.card(now:)` after every event, and that the late tap is in the core
  (`primary(on:`). The logging test reads `ScribeAutoStartController.swift` for `[ZEUS] scribe meeting:`.
- `qa/regressions.json`: REG-402 to REG-407 point at `ScribeMeetingStartOutcomeTests.swift`, check
  `portable-scribe`; the new suite joins the scribe group. New rows REG-418 (silent automatic failure), REG-419
  (recording shown before capture), REG-420 (Cancel lost to the timer), REG-421 (meeting dropped while saving),
  REG-422 (Switch asked twice).

## MS7. The upcoming phase; the heads-up pipeline is deleted

### Behaviour

- Two minutes before a calendar meeting, one card: the title, "in 2 min", Record. In Ask me and in Start
  automatically. Off shows nothing.
- It stays 20 s, longer under the pointer, then leaves. Leaving on its own is not an answer. The dismiss
  glyph is: nothing more is shown for that meeting, including at its start time.
- If the call begins while the heads-up is up, the card stays through the 3 s check, then Ask me keeps the
  offer reading "now" and Start automatically counts down. A brief microphone blip does not start a countdown.
- A heads-up is shown once per meeting and can no longer be lost.

### Rules (ZeusCore, pure)

- `ScribeAutoStartState.upcoming(meeting:deadline:)`; its lifetime is `askTimeout` (20 s).
- `ScribeMeetingEvidence.upcoming`: the closest slot with `0 < start - date <= leadWindow`, not ended.
- From `idle`: a candidate arms as before; otherwise an upcoming slot with no ledger mark, with Scribe free,
  enters `upcoming` and the ledger notes `headsUp`. The deadline returns to `idle`. `dismiss` notes `declined`.
  `primary` starts. A candidate for the same meeting moves to `armed(meeting:since:offerUntil:)`, which keeps
  the offer on screen while the debounce runs, then to `prompting` or `countingDown`.
- `leadWindow` and `lateWindow` live in `ScribeMeetingStartPolicy`.

Deleted: `ScribeCallPopup.swift`, `ScribePopupDriver.swift` (`ScribeCardHostingView` already moved into
`ScribeMeetingCardPanel.swift` in MS5), `ScribePopupLifecycle.swift`, `ScribeCallPrompt.swift`, `ScribePromptDecision`,
`ScribeCallPromptText`, and in the watcher `decision`, `dismissedIDs`, `dismissedApps`, `dismissedInstances`,
`dismiss(_:)`, `recordingDidStart()` and the heads-up half of `apply`. `recordingIdentity(for:)` takes a
`ScribeCallApp`. The two `ScribePopupDriver.describe` calls in `ScribeController.swift:558-559` move to a
`ScribePhase` description in the core.

### Tests first

`ScribeAutoStartTests`: `headsUpWindowEdges` (121 s, 120 s, 1 s, 0 s before), shown in both modes and not in
Off, `theHeadsUpIsShownOncePerMeeting` (the 20 s deadline returns to idle; a failed or empty calendar read does
not announce it again), `dismissAtTwoMinutesStaysQuietAtStartTime` at machine level, a timeout then a live call
asks (Ask me) or counts down (automatic), `aMicBlipDuringTheHeadsUpDoesNotCountDown`, Record on the heads-up
starts with the slot's title and guests and no call binding, nothing while Scribe is saving.
`ScribeCoreTests.swift:955-1030` and `ScribeLiveLogicTests.swift:464-488` are removed with the code they test;
`ScribePopupLifecycleTests.swift` is removed.

QA in this ticket: `prepare.py` drops `ScribePopupLifecycle.swift`, `ScribeCallPrompt.swift` and
`ScribePopupLifecycleTests`. `feature-map.json` F04.1 rebinds to `headsUpWindowEdges`,
`dismissAtTwoMinutesStaysQuietAtStartTime` and `aRecordingStartedByHandIsNeverPromptedOver`. `test_source_lint.py`
drops the popup checks and reads the hosting view from the panel file; `test_alerts_lint.py:59` drops
`ScribeCallPopup.swift` and names the card view. `docs/ALERTS-DESIGN.md` surfaces row is updated. REG-423
(heads-up lost) and REG-424 (dismissal forgotten at the start time).

## MS8. The detector runs only when a meeting is near

### Behaviour

- Off: no timer, no microphone listeners, no calendar reads.
- Ask me or Start automatically with nothing near: no timer fires. The microphone listeners wait, and one
  wake-up is set for two minutes before the next calendar meeting. A calendar change resets it.
- Near (a slot inside its window, a call app holding the microphone, or the machine not idle): the 5 s poll
  runs as the backup, as today.
- The detector follows the setting at once. A wake-up that arrives during a scan runs one more scan when the
  first ends.
- Events the current user declined are not meetings.
- Start at launch follows decision D3.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Scribe/ScribeDetectorPlan.swift`:

- `ScribeDetectorPlan`: `stopped`, `listening(wakeAt: Date?)`, `polling`.
  `plan(mode:machineIdle:micActive:slots:now:)`: Off with the machine idle is `stopped`; near is `polling`;
  else `listening` with the earlier of the next slot start minus `leadWindow` and the end of the calendar
  look-ahead.
- `ScribeScanGate`: `idle`, `scanning`, `scanningDirty`; events `wake` and `finished`; effect `scan`. A wake
  while scanning becomes dirty and scans once more.

App side: `ScribeCalendarReader` is the one calendar reader, used by the watcher and `ScribeUpNextModel`
(`ScribeUpNextModel.swift:41-60` and `ScribeCallWatcher.swift:364-385` are the two copies today). The watcher
takes a microphone-observer factory and a scheduler in its initialiser, applies the plan after each scan, on the
setting change, on `EKEventStoreChanged` and on wake from sleep. `stop()` resets the machine. The process-exit
observer for a bound call app stays installed while a recording is bound.

### Tests first

`Tests/ZeusCoreTests/ScribeDetectorPlanTests.swift` (new): every plan row; the wake time; Off while recording
keeps polling until idle; the scan gate (wake while idle, while scanning, twice while scanning, finished when
dirty). `Tests/ZeusAppTests/ScribeDetectorTests.swift` (new), with fake factories: `offStopsTheDetector` (no
timer, no listener created), switching to Ask me starts it, a wake during a scan runs exactly one more scan.

QA in this ticket: the new file and suite join the scribe group. REG-425 (detector never stops).

## MS9. A real journey

- `Tests/ZeusAppTests/ScribeMeetingCardJourneyTests.swift` (new). It builds a `ScribeAutoStartController` from
  its ports: a `ScribeController` with the inert capture provider and injected clock of
  `ScribeLifecycleScenarioTests`, a manual scheduler, the real `ScribeMeetingCardPanel`, and a fixed microphone
  answer. Evidence is synthetic and fed through `ingest`. Clicks go through `OwnedWindowEventDriver`.
- Cases: the real Record starts exactly one session; the real Cancel ends a countdown with no session; a
  countdown that ends reaches Starting then Recording; a Cancel sent after the countdown ended leaves no
  session and no saved meeting; a provider that fails shows its reason; the dismiss glyph quiets the meeting;
  the panel sits at `ScribeMeetingCardPlacement.origin` for its screen; the time text changes from "in 2 min"
  to "in 1 min" when the fake clock crosses the minute.
- `qa/feature-map.json`: F04.2 binds to this suite (one session, placement, refreshed time). F04.3 stays
  unimplemented and owed.

## Implicit state machines made explicit

| Today | Becomes |
| --- | --- |
| Heads-up chain: `decision`, three dismissal collections, popup `current` and `shown`, a 45 s lifetime | `ScribeAutoStartState.upcoming` and the ledger mark `headsUp` |
| Banner surface: `Kind`, `meeting`, four strings, `model.card`, `driver.phase`, `panel.isVisible` | `ScribeMeetingCard`, computed by `card(now:)` |
| Start outcome: `ScribePopupLifecycle` for taps, `.recording` at effect time, `startGrace`, `startNow` | `starting`, `failed`, `recording`, driven by `Event.scribe` |
| Cancel versus the timer: a 1 s repeating timer and a decline that can arrive too late | `Event.cancel(on:)`, `Effect.abandonStart`, a one-shot wake from `nextWake(now:)` |
| Readiness: setting, microphone status, consent stamp, `lastEvidence` | `ScribeAutoStartReadiness`, `ScribeAutoStartOptIn`, `ScribeStartContext` |
| Identity and "already handled": slot key or call key, cooldown state, `switching`, `dismissedIDs` | `ScribeMeetingStartPolicy.liveSlot` and `ScribeMeetingLedger` |
| Scribe busy read as "by hand"; Switch through the end window | `held(meeting:startOwed:)` |
| Pending hints: three optionals on `ScribeController` | `ScribeMeetingContext` passed to `start` |
| Suggested end sent as `requestedByUser` with a stop timer | `ScribeEndWorkflow.Reason.callLooksOver`, advisory |
| Timers: watcher 5 s, controller 1 s, two card drivers at 0.25 s | `ScribeDetectorPlan`, `ScribeScanGate`, one one-shot wake |

Left as is, listed so it is not mistaken for explicit: the capture run flags in `ScribeLiveCapture.swift:142-146`.

## Strings removed

- "Nothing is recorded until you tap Record." and "Nothing is recorded until you tap Start."
- "Tap Cancel to keep Zeus from recording this meeting."
- "You chose Start automatically. Tap Start and allow, and Zeus will start by itself from now on, after a
  5 second countdown you can cancel." and the button "Start and allow".
- "Switching stops this recording and saves it first. Keep recording leaves it running."
- "Meeting started: <title>. Take notes?" and "Meeting started: <title>. Taking notes in N."
- "Next meeting: <title> is starting. Switch notes to it?"
- "Starts in N min: <title>", "Started: <title>", "Meeting detected: <app>".
- Buttons "Record with Scribe", "Start", "Not now", "Close", and "Keep recording" on the card. They become
  Record, Cancel, Switch, Allow, Try again and one dismiss glyph.
- Hints "Starts listening to this meeting and taking notes.", "Closes this suggestion without recording.",
  "Starts taking notes for this meeting.", "Closes this without recording."
- Labels "Scribe suggestion", "Scribe meeting", "Scribe suggestion: <headline>", "Scribe: <headline>",
  "Scribe is starting", and the announcements ending "Record with Scribe, or Not now.", "Start, or Not now.",
  "Start and allow, or Not now.", "Switch, or Keep recording.", "Cancel to stop it."
- "Scribe is recording" with its record icon.
- Failures shortened: "Microphone is off for Zeus, so Scribe can't hear the meeting.", "Scribe is still saving
  your last meeting. Try again in a moment.", "Scribe couldn't start. <reason>", "Scribe didn't start. Try again."
- The card title "<App> call" becomes "Call" (the saved recap title is unchanged).
- Settings: the three `settingNote` sentences and `settingEndNote`.
- End window: "You asked to stop. Your notes will be saved after recording ends." no longer shows for a
  suggested end.

Strings added, all in `ScribeMeetingCardText`: "Record", "Cancel", "Switch", "Allow", "Try again", "Dismiss",
"in N min", "now", "Recording starts in N", "Starts once your last meeting is saved", "Starting", "Recording",
"Microphone is off for Zeus", "Microphone not allowed yet", "Automatic start needs one recording first",
"Still saving your last meeting", "Couldn't start", "Didn't start", "Call". End window: "The call looks over".

## Order and parallel worktrees

1. MS0 alone, first. It is small, freezes the card contract and reserves REG-410 to REG-429.
2. Lane A, one ticket after another in this order: MS1, MS2, MS3, MS4. They share `ScribeAutoStart.swift`,
   `ScribeAutoStartController.swift` and `ScribeController.swift`, so they are not parallel. The pure half of
   MS3 (`ScribeEndWorkflow.swift` and its tests) may be written early; it lands after MS2.
3. Lane B, a second worktree in parallel with all of lane A: MS5. It touches only its two new app files, one
   new lint file, one new test file and one fixture call in `SnapshotRenderer.swift`.
4. MS6, after MS4 and MS5. Then MS7.
5. MS8 and MS9 in two worktrees in parallel, after MS7. MS8 owns the watcher, the reader and launch; MS9 adds
   one test file and the F04.2 binding. Their `qa/regressions.json` and `prepare.py` edits are separate lines.

New rules get new test files (ledger, context, opt-in, outcome, card, detector), so tickets rarely edit the
same suite. Every ticket ends green on its own: `swift build --build-tests`, its suites,
`python3 qa/portable-core/prepare.py --group scribe --run` and `./tools/check.sh development`, with the QA
bindings it moved.

## Verification for this work

1. Record the failing baseline of `ZeusCoreTests` and `ZeusAppTests` at `d26eb37` before the first change.
2. Tests are committed before the code and shown failing on the base (a missing name is a failure).
3. Per ticket: `swift build --build-tests`, then `swift test --filter` for each suite it names.
4. The whole `ZeusCoreTests` module on the branch and on the base, compared.
5. `python3 qa/portable-core/prepare.py --group scribe --run`, `scripts/check-settings-catalog.sh`, and
   `./tools/check.sh` in development mode, per ticket. A development pass is not full feature acceptance.
6. Snapshot fixtures for every card state reviewed at 1x and 2x; the temporal ring test with and without
   Reduce Motion.
7. An independent review of each diff, and a second verifier on each branch, before a pull request. The owner merges.
8. Owed on a real Mac, with the owner's own macOS consent, and not covered by any automated check here:
   - A real calendar meeting: the heads-up at two minutes, its 20 s leave, and "now" at the start.
   - Ask me: Record from another app's window on the first click; Starting, Recording, then the top bar wings.
   - Start automatically: opt in from Settings, join a call, see the ring drain, cancel once, let it run once,
     and confirm capture begins only after zero. Hold a menu open through the end of a countdown and confirm
     the start still happens on time. Tap Cancel in the last half second and confirm nothing is saved.
   - Microphone denied in System Settings: the card and the Settings row both say so and Allow opens the pane.
   - Whether the first system-audio use raises a macOS dialog. If it never does, the "one recording first" rule
     can be dropped; until that is seen it stays.
   - The D1 mute test: mute for 30 s inside each supported call app; read whether an end is suggested and
     whether a dismissed call is offered again after unmuting.
   - Two back-to-back meetings, the second starting while the first saves: the waiting card, then the start.
   - Switch on the next-meeting card: one tap, no second question, the next recording starts once.
   - A settings file with "Start automatically" imported on a Mac set to Ask me: nothing changes.
   - Mode Off: no timer or listener in a sample of the process; the app idle below 1 percent CPU.
   - Motion at normal speed, then with Reduce Motion and Reduce Transparency; VoiceOver through one full
     countdown; Return and Escape when the card is key; a second display.
