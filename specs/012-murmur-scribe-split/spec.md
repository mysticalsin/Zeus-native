# Murmur and Scribe stay different

Status: proposal. This document changes no Swift, no setting, and no pixel.
Audited commit: `2722dcb7497d5415fbc1fcb1f65c49629966a281` on the integration branch (2026-11-21).

Murmur is quick dictation. Scribe is a meeting record. Talking to Zeus is a third mode. A person can tell which one is running from the key they used, the wing in the notch, the sound, and the file that gets written.

## Decision

| Gesture | Result |
| --- | --- |
| Tap Right Command | Murmur only. The tap is up within 0.30 s, with no other key down. |
| Hold Right Option | Talk to Zeus. The hold is alone for `VoiceKey.secondKeyConfirm` (0.25 s). |
| Tap a Scribe control | Scribe only. The control is Start Scribe, Record on the meeting card, or Up next. |

One of those three starts one mode. The other two stay idle. A second mode that wants the microphone is refused, and the mode that already has it keeps going.

## Already settled

Two open drafts already argue about the Right Command tap. This spec does not restate them and does not add their tests.

[PR #81](https://github.com/mysticalsin/Zeus-native/pull/81) (`zeus-bot/right-command-toggle`, `817c4219`) is a preservation draft. On that branch a solo Right Command tap toggles listening and plays the talk cues. `HotkeyMonitor.onRightCommandStart` calls `talkKeyPressed`. The dictation monitor still owns the same key, so one tap can arm talk and dictation together. That is the defect.

[PR #112](https://github.com/mysticalsin/Zeus-native/pull/112) (`zeus-bot/fix-s08-command-tap`, `20392c5d`, stacked on #81) is the S08-08 fix. It is the owner of these rules, and its tests already lock them:

- A solo Right Command tap returns `.murmur` and leaves `RightCommandTap.listening` false.
- Left Command held across that tap returns no signal.
- Holding Right Option for 0.25 s returns one `.talk`. A later tick returns nothing.
- One `KeyActionRouter` event never returns both `.murmur` and `.talk`.
- A missed Right Command key-up clears the press, and the next tap is Murmur again.
- A flags repeat while both Command keys are down stays down when the hardware still holds the right key.
- `AppDelegate` does not point Right Command at `talkKeyPressed`.

Those assertions live in `RightCommandTapTests`, `KeyActionRouterTests`, and `ModifierFlagsRepeatTests` on that branch. An implementation of this spec leaves those files as #112 wrote them.

#112 also left the tap unwired: `applyRightCommand` breaks on `.murmur` and starts nothing. A talk key the owner has already saved as Right Command still talks. Scribe, the notch wings, the cues, the settings sentences, and the files are outside that fix. That is the work below.

On this branch `RightCommandTap.swift` and `KeyActionRouter.swift` are absent. The audit below is this branch. The router rules above are adopted as the key contract once #112 is present, and they are not redesigned here.

## Audit

### Murmur today

The product name Murmur is the notch tab and the settings section (`TopBarTab.dictation` title "Murmure", `GSSection.murmure`). The running feature is dictation.

| Piece | Where | What it does now |
| --- | --- | --- |
| Default key | `ShortcutStore.loadDictation` (`Sources/ZeusCore/Shortcut.swift`) | Right Command, stored as `dictation.shortcut` (legacy `dictation.key`). |
| Key machine | `VoiceKeyMachine` role `.dictation`, driven by `HotkeyMonitor` from `DictationController.start` | Default behavior is hold (`DictationBehavior.holdToSpeak`). Press starts a mic turn. Release transcribes and inserts. A quick second press latches hands-free dictation. |
| Behavior setting | `dictation.behavior` (`DictationBehavior.swift`, Settings catalog "Shortcut behavior") | "Hold to speak" or "Press to start and stop". A key shared with talk is forced back to hold. |
| Notch control | `AppDelegate` `topBar.toggleDictation` (around line 174) | A click latches dictation. A hold of about 0.35 s then a release stops it. |
| Job phase | `DictationFlow.State` / `DictationPhase` | `idle`, `listening`, `transcribing`, `rewriting`, `done`, `failed`. |
| Insert | `TextInserter.insert` / `type` from `DictationController` | Words go to the focused field. |
| History | `DictationStore` rooted at `Application Support/Zeus/Dictation` | `history/<id>/meta.json`, and `saveAudio` may write `history/<id>/audio.wav`. |
| Cues | `dictationBegin`, `dictationEnd`, `dictationCancel` | Gated by `dictation.sounds`. |
| Enable | `dictation.enabled` | Off means the dictation monitor does not start a turn. |

`AppDelegate` still describes the feature as "hold its key anywhere, speak, release".

### Talk today

| Piece | Where | What it does now |
| --- | --- | --- |
| Primary key | `ShortcutStore.talkDefault` | Control+Option, stored as `talk.shortcut`. |
| Second key | `ShortcutStore.secondTalkDefault` | Right Option, `talk.secondShortcut`. `VoiceKey.secondKeyConfirm` is 0.25 s. |
| Machines | `TalkKeyPair` over two `VoiceKeyMachine`s (`docs/STATE-MACHINES.md` items 24 and 28) | Phases: `idle`, `armed`, `holding`, `tapped`, `latched`, `spent`. One talk turn across both keys. |
| Wiring | `AppDelegate` talk `HotkeyMonitor` `onPress` → `talkKeyPressed` → `VoiceTurnController.press` | Release calls `voice.release()`. |
| Old defaults | `ShortcutStore.autoTalkDefaults` | `.optionCommand` and `.rightCommand`. An auto-written Right Command talk key migrates to Control+Option once. A key the owner recorded is kept, including Right Command. |
| Shared key | `SettingsView` talk row; `DictationController` when the keys match | "Double-tap it, then speak. Holding the same key dictates." |
| Cues | `ZeusSound` `.listenStart` and `.listenStop` | Separate switches from the dictation cues. |
| Turn | `VoiceTurnController.listening` | A Zeus turn. The words are a turn transcript, not a dictation insert and not a meeting. |

### Scribe today

| Piece | Where | What it does now |
| --- | --- | --- |
| Session | `ScribePhase` (`ScribeSession.swift`) | `idle`, `starting`, `recording`, `ending`, `processing`, `complete`, `failed`. |
| Meeting machine | `ScribeAutoStartMachine` | `idle`, `upcoming`, `armed`, `prompting`, `countingDown`, `held`, `starting`, `recording`, `failed`. |
| Tap starts | `ScribeCaptureRow` calls `scribe.start()` ("Start Scribe"). The meeting card's primary action uses origin `.tap`. | These are user taps. |
| Untended start | `ScribeAutoStart.expire` on `.countingDown` | When `scribe.autoStart` is "Start automatically" and readiness is complete, the deadline calls `startRequest(..., origin: .automatic)`. No tap. |
| Setting | `ScribeAutoStartMode` | "Off", "Ask me" (default), "Start automatically" (`scribe.autoStart`). |
| Keyboard | none | No global Scribe shortcut in `AppDelegate`. |
| Files | `ScribeMeetingStore.standard` | `Application Support/Zeus/scribe/meetings/*.json`. Capture frames are discarded (`ScribeDiscardingFrameStore`). |
| Engine | `ScribeController` / `ScribeTranscriberBridge` | Both read `DictationSettings.shared.engine`. |
| Sound | none on start | A VoiceOver announcement exists. No `dictationBegin` and no `listenStart`. |
| Watcher | `ScribeCallWatcher` | Feeds the meeting machine. The watcher comment says it does not capture by itself. The countdown expiry is the path that starts capture without a tap. |

### Wings

`ClosedWings.kind` (`TopBarViews.swift`) picks one wing: Recordly, then Scribe, then dictation, then feedback, then a cue, then the mascot. Scribe uses `ScribeWings` and an elapsed time. Dictation uses a red dot, the mode symbol, and `DictationWave` in `TopBarStyle.rec`. Talk uses the mascot listen pose. Recordly stays ahead of both and is left as it is.

## Where they overlap

Each row is a place a person, or a later change, can mix two modes.

1. **Right Command is a hold, a latch, and a possible talk key.** The default dictation path is press-and-hold, plus a hands-free latch on a quick second press (`VoiceKeyMachine` dictation role). Talk's shipped gesture is the same shape on different keys. `autoTalkDefaults` still names `.rightCommand`, and a recorded talk shortcut of Right Command is kept (`ShortcutStore.loadTalk`). On #81 that tap also calls `talkKeyPressed`.
2. **One shortcut card describes all three gestures as "hold".** Settings > Shortcuts, card "Summon Zeus": "Talk to Zeus" is "Hold to ask, let go to send." "Second talk key" is "Hold to talk, let go to send, double-tap to keep listening." "Dictation" is "Hold to speak, let go to write it where your cursor is." The default dictation value is `.rightCommand`.
3. **The shared-key sentence swaps the two jobs.** `SettingsView` talk row: "Double-tap it, then speak. Holding the same key dictates." `DictationBehavior.available` then offers only "Hold to speak". A double tap on that key is talk. A hold is dictation. The names Murmur and Scribe do not appear in the sentence.
4. **Press-to-toggle looks like a Murmur tap and still lives on the dictation key.** "Press to start and stop" (`dictation.behavior`) starts and stops dictation on a dedicated key. It is a second tap-shaped dictation. It is not wired to Scribe, and it is not the #112 router.
5. **The Murmure page still says Dictation.** The page is "Murmure". The first card is "Dictation" / "Enable dictation". The shortcut row is "Dictation shortcut". The sound row is "Play dictation sounds".
6. **Scribe can start with no tap.** "Start automatically", a completed readiness check, and the end of the 5 s countdown emit `start` with origin `.automatic` (`ScribeAutoStart.swift` counting-down branch of `expire`). "Ask me" and "Off" do not. The card, the page, and the wing all say Scribe either way, so an automatic meeting and a tapped meeting look the same once the wing is up.
7. **The microphone is shared by preemption.** `ExplanationAudioArbitration.yieldToNewCapture()` runs when dictation begins, when Scribe starts, and when talk presses. A new capture takes the input from the one already running. Separate `SpeechInput` stacks do not mean two owners. `VoicePermissions` is one prompt for talk, dictation, and wake.
8. **The closed notch hides the loser.** While Scribe is recording, `ClosedWings` returns `.scribe` and the dictation wing is not drawn, even if `topBar.isDictating` is true. Both recording wings use a waveform. Dictation's dot is the same red as a recording mark.
9. **The cues are easy to assign to the wrong mode.** Talk plays `listenStart` / `listenStop`. Dictation plays `dictationBegin` / `dictationEnd` / `dictationCancel`. Either switch can be off. Scribe plays neither, so a silent meeting and a silent dictation are the same to the ear. #81 played the talk cue on the Right Command tap.
10. **One engine setting feeds both recognizers.** `ScribeTranscriberBridge` and `ScribeController` take `DictationSettings.shared.engine`. Changing the Murmure engine changes how a meeting is transcribed.
11. **The files are different, and nothing in the UI says so at start.** Dictation history is `Dictation/history/<id>/`, including an optional `audio.wav`. A meeting is `scribe/meetings/<file>.json`, and the pcm frames are discarded. A Murmur insert uses `TextInserter`. A meeting save does not. Nothing at the start of either mode names the folder.
12. **The notch Dictate control and Start Scribe sit in one top bar.** `toggleDictation` calls `DictationController.begin` / `finish`. Start Scribe calls `scribe.start()`. They do not call each other. They share the bar, the mic permission, and the word "listening" in nearby copy (Start Scribe's hint is "Starts listening to a meeting").
13. **Wake and the primary talk key are adjacent.** A wake phrase and a Control+Option hold both open a talk turn (`VoiceTurnController`). They do not start Scribe. They must stay unable to start Murmur when the Right Command path becomes a tap.
14. **Equaliser and "Recording".** Scribe phases `starting`, `recording`, and `ending` mark Zeus as capturing. Dictation listening publishes levels into `DictationWave`. The word "Recording" appears on the Scribe confirmation and in the dictation red-dot treatment.

These do not overlap, and a later change should leave them that way: Scribe has no global hotkey; a Right Command tap on this branch does not call `scribe.start()`; a Start Scribe tap does not call `DictationController.begin()`; deep links open a hint and do not start the mic.

## Proposed split

Three owners. Each owner has one state value. A gesture names one owner.

Murmur's key contract is the #112 router. This spec starts where that signal is consumed. `VoiceKeyMachine` keeps talk, and it keeps dictation only for a dedicated key the owner recorded that is not Right Command. The default Right Command path stops being a dictation hold.

Scribe's session machine stays `ScribePhase`. The meeting machine stays `ScribeAutoStartMachine`, with one new rule: the only start origin is `.tap`. A stored "Start automatically" is read as "Ask me" and does not write a new opt-in stamp. The countdown may still show. When it ends, the card returns to the offer. `expire` does not emit `start`.

Talk's machines stay `TalkKeyPair` and `VoiceKeyMachine`. This spec adds no talk phase. It adds the owner check: a talk start runs for Control+Option and for a Right Option hold that the router has already called `.talk`. A Right Command tap is not one of those.

### Capture owner

One pure value, `CaptureOwner`, in ZeusCore: `.clear`, `.murmur`, `.talk`, `.scribe`.

`claim(holder:requested:)` returns the holder unchanged when `requested` differs from `holder` and `holder` is not `.clear`. The effect is `refuse(requested, because: holder)`. The holder keeps its state. The requester stays idle. The notch says which mode is already using the microphone. A release to idle is the only way back to `.clear`. Recordly is outside this value.

### Murmur machine

New type `MurmurMachine` in `Sources/ZeusCore/Dictation/MurmurMachine.swift`. It owns the `.murmur` signal. `DictationFlow` stays the transcribe job underneath a listening turn. A job starts only from this machine's `listening` state.

| State | Meaning |
| --- | --- |
| `idle` | No Murmur capture. |
| `listening(turn)` | Mic open for this turn. |
| `transcribing(turn)` | Mic closed, text not ready. |
| `inserting(turn)` | Text ready, going to the focused field. |
| `failed(turn, reason)` | The turn ended without an insert. |

| Event | From `idle` | From `listening` | From `transcribing` or `inserting` |
| --- | --- | --- | --- |
| `murmur` | `listening`, effect `beginCapture`, cue `dictationBegin` | `transcribing`, effect `endCapture`, cue `dictationEnd` | ignored |
| `escape` or `cancel` | ignored | `idle`, effect `discardCapture`, cue `dictationCancel` | `idle`, discard, no insert |
| `permissionDenied` | `failed`, no file under `scribe/meetings` | same | same |
| `textReady` | ignored | ignored | `inserting` |
| `inserted` | ignored | ignored | `idle` |
| `insertFailed` | ignored | ignored | `failed` |
| `holderBusy` | stay `idle`, effect `refuse` | stay, the turn keeps going | stay |

Effects that this machine does not emit: `scribe.start`, `VoiceTurnController.press`, `listenStart`, `listenStop`, a write under `scribe/meetings`.

A Right Command press longer than 0.30 s emits no `murmur` (the #112 router). The dictation controller does not call `begin()` for that hold. "Press to start and stop" remains available on a dedicated dictation key that is not Right Command and not the talk key. The default key does not use it.

The notch Dictate control sends `murmur`. It does not call `scribe.start` and it does not call `talkKeyPressed`.

Recording Right Command as "Talk to Zeus" or as the second talk key is refused. The stored talk key stays what it was. This closes the hole #112 listed and did not take.

With `dictation.enabled` off, a `murmur` signal leaves the machine `idle` and does not start talk. #112 already keeps `listening` false on the tap type. This rule is the controller.

### Scribe machine

`ScribePhase` stays the session. `ScribeAutoStartMachine` stays the card. The new rows:

| Event | Result |
| --- | --- |
| `primary` on the offer, the countdown, or Up next, holder `.clear` | `start` with origin `.tap` |
| `primary` while Murmur or talk holds the mic | no `start`, card explains the holder |
| countdown `expire` | card returns to the offer, no `start`, origin `.automatic` is not produced |
| meeting evidence, dismiss, Cancel, "Off" | no `start` |
| stored mode "Start automatically" | read as "Ask me" |

`ScribeStartOrigin.automatic` remains in the type so old logs still decode, and no new attempt is built with it. Cancel, the close glyph, and a countdown ending do not call `scribe.start()`.

### Talk machine

Unchanged tables in `VoiceKeyMachine` and `TalkKeyPair`. The owner adds:

| Event | Result |
| --- | --- |
| Right Option down alone for 0.25 s, holder `.clear` | one talk turn, cue `listenStart` |
| Control+Option hold, holder `.clear` | one talk turn, the same cue |
| either hold released | the turn ends, cue `listenStop` |
| either hold while Murmur or Scribe holds the mic | no turn, `refuse` |
| Right Command tap during a talk turn | no second turn (#112), and no Murmur until talk is idle |

A talk transcript is not passed to `TextInserter` and not passed to `ScribeMeetingStore`.

## Trigger matrix

Rows marked "router" are #112's tests. The other rows are this spec's tests.

| Input | Murmur | Talk | Scribe | Owner |
| --- | --- | --- | --- | --- |
| Right Command tap, alone, ≤ 0.30 s | start, or commit if listening | idle | idle | router, then Murmur |
| Right Command held past 0.30 s | idle | idle | idle | router |
| Right Command with any other key, or with Left Command | idle | idle | idle | router |
| Second Right Command tap while Murmur is listening | commit and insert | idle | idle | Murmur |
| Right Command tap while Scribe is recording | refused, stays idle | idle | keeps recording | capture owner |
| Right Command tap while talk is listening | refused | keeps the turn | idle | capture owner |
| Right Command tap with dictation disabled | idle | idle | idle | Murmur |
| Right Option tap shorter than 0.25 s | idle | idle | idle | router |
| Right Option held 0.25 s alone | idle | one turn | idle | router, then talk |
| Right Option release after that hold | idle | end the turn | idle | talk |
| Control+Option hold and release | idle | one turn, then send | idle | talk |
| Start Scribe, meeting-card Record, Up next | idle, unless Murmur or talk holds the mic | idle | origin `.tap` | Scribe |
| Countdown reaches its deadline | idle | idle | offer stays, no start | Scribe |
| A meeting is detected | idle | idle | card only | Scribe |
| Notch Dictate control | one `murmur` | idle | idle | Murmur |
| Escape during Murmur listening | cancel, no insert, no meeting file | idle | idle | Murmur |
| Talk key recorded as Right Command | the recorder refuses the change | previous talk key | idle | settings |

## Wings, cues, files, settings

**Wings.** Murmur listening draws the dictation wing and the accessibility label "Murmur". Scribe recording draws `ScribeWings` and the label "Scribe". Talk listening draws the mascot. `ClosedWings.kind` does not report `.dictation` while Scribe is the holder, and it does not report `.scribe` for a Murmur turn. The red dot stays on the Murmur wing. The elapsed meeting time stays on the Scribe wing.

**Cues.** `ModeCue` maps one event to one cue id. `murmurBegan` → `dictationBegin`. `murmurEnded` → `dictationEnd`. `murmurCancelled` → `dictationCancel`. `talkBegan` → `listenStart`. `talkEnded` → `listenStop`. `scribeBegan` → no cue. A Murmur event does not play `listenStart`. A Scribe tap does not play `dictationBegin`.

**Files.** A Murmur turn may write only under `Dictation/history/<id>/` and may call `TextInserter`. A Scribe session may write only under `scribe/meetings/` and does not call `TextInserter`. A talk turn writes neither.

**Settings copy, in the later UI change.** The Murmure card title is "Murmur". The shortcut row is "Murmur shortcut", and the sentence for the default key is "Tap Right Command to write where the cursor is." The Shortcuts card uses that sentence for Murmur and keeps "Hold to ask, let go to send" on Talk to Zeus. The shared-key sentence is removed for Right Command, because that key is no longer selectable as the talk key. Scribe's settings gain no shortcut row. "When a meeting starts" offers "Off" and "Ask me".

The engine control may stay shared until a later spec splits it. This spec only requires that the label say it feeds Murmur and Scribe, so saving it is not a silent change to meetings.

## Red-first tests

New files. They are written against types this branch does not have (`MurmurMachine`, `CaptureOwner`, `ModeCue`) or against a Scribe rule the current `expire` breaks. They fail first. They do not edit `RightCommandTapTests`, `KeyActionRouterTests`, or `ModifierFlagsRepeatTests`.

`Tests/ZeusCoreTests/MurmurMachineTests.swift`

- `aMurmurSignalFromIdleOpensListeningAndStartsNoOtherMode`
- `aSecondMurmurSignalEndsCaptureAndNamesAnInsert`
- `aSignalLongerThanTheTapIsAbsentHere` (the machine never sees it; a direct `murmur` is the only start)
- `escapeFromListeningDiscardsAndWritesNoMeeting`
- `permissionDeniedWritesNoMeeting`
- `aSignalWhileScribeHoldsIsRefusedAndScribeStaysRecording`
- `aSignalWhileTalkHoldsIsRefused`
- `dictationDisabledIgnoresTheSignalAndLeavesTalkIdle`
- `transcribingIgnoresAnotherMurmur`

`Tests/ZeusCoreTests/ScribeTapOnlyTests.swift`

- `countdownExpiryReturnsToTheOfferAndEmitsNoStart` (red on today's `expire`)
- `aPrimaryTapEmitsStartWithOriginTap`
- `evidenceAloneEmitsNoStart`
- `cancelEmitsNoStart`
- `storedStartAutomaticallyIsAskMe`

`Tests/ZeusCoreTests/CaptureOwnerTests.swift`

- `aSecondClaimLeavesTheHolder`
- `releaseToClearLetsTheNextModeClaim`
- `scribeWingIsNotTheMurmurWing`
- `murmurWingIsNotTheScribeWing`

`Tests/ZeusCoreTests/ModeCueTests.swift`

- `murmurBeganIsDictationBegin`
- `talkBeganIsListenStart`
- `scribeBeganIsSilent`
- `aMurmurEventIsNotATalkCue`

`Tests/ZeusCoreTests/ModeStoreTests.swift`

- `aMurmurInsertPathIsTheDictationHistory`
- `aMeetingPathIsScribeMeetings`
- `theTwoRootsDiffer`

`Tests/ZeusCoreTests/TalkKeyRefusalTests.swift`

- `rightCommandIsRefusedAsTheTalkKey`
- `rightCommandIsRefusedAsTheSecondTalkKey`
- `controlOptionAndRightOptionStayAssignable`

A Scribe or Murmur test that only asserts "a Right Command tap returns `.murmur`" is a duplicate of #112 and is not added.

## Acceptance

- The three machines above are the only start paths for the three modes.
- The trigger matrix holds, with #112's rows still covered only by #112's tests.
- A meeting file appears only after a tap on a Scribe control, and only when `CaptureOwner` was `.clear`.
- A Right Command tap writes through `TextInserter` or Murmur history, and the talk turn count stays the same.
- Holding Right Option for 0.25 s starts one talk turn, and Murmur and Scribe stay idle.
- Settings no longer describe Right Command as hold-to-speak or as a talk key. Scribe has no key.
- This document's merge changes none of that yet. The lists are the contract for the implementation change.
