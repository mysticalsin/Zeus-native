# Voice key machine: plan and design

Written 14 November 2026 on `codex/island-tiling-20261114` at `ae2ea60` (first commit `133bb9b`); revised the same day
after an adversarial review of that commit and again after a second read of every cited line ("Review notes" at the
end). The spec, design note and task list for one refactor: the hold keys of
Zeus (talk, dictation, the Polyglot key, with the pointing key beside them) get one explicit state machine, in the
pattern of `docs/STATE-MACHINES.md` (a pure `State`, `Event`, `Effect` reducer in ZeusCore, a controller that only runs
effects). Nothing was built or run for this plan. Every claim about today's code was read in the source and carries a
file and line; what could not be checked that way says "not verified". Nothing here is accepted until the named tests
run on macOS and the behaviour is seen on a real Mac.

## Why

Six review rounds on this branch kept finding orders of key presses in which a tiling chord starts, sends or latches a
talk or dictation turn. Each round added a flag or a function to `HotkeyMonitor` (`cancelledByLargerChord`,
`endedByLargerChord`, `finishEndedTurn`, `cancelHold`, `TalkKeyLatch.isEnding`, the consumed key feed). The cause is no
one order: the life of a hold key is spread over 13 variables in three types that must change together, so each new
rule has to be proved again by hand against every combination. The patching stops; the machine is made explicit.

| # | Open finding | Closed by |
| --- | --- | --- |
| F1 | Shift joining a talk hold is read as a release: Control, Option, Shift, Command, Left sends the turn 0.4 s later, and two quick swaps can latch hands-free (`HotkeyMonitor.swift:277-280`, `:170`) | I1, I2, table rows 8 and 11 |
| F2 | The clash rule compares modifier-only keys with the pair only, not the pair plus Shift (`TileBaseConflicts.swift:67`, `:80-81`) | Part 6 |
| F3 | The tap is created enabled before its thread services it (`TilingKeyTap.swift:25-26`, `:147-150`) | Step 14 |
| F4 | `stop()` leaves the gate open until the teardown runs (`TilingKeyTap.swift:174-180`) | Step 15 |
| F5 | `start()` calls the window server while holding the callback's lock (`TilingKeyTap.swift:118-123`) | Step 16 |

## 1. Today

### 1.1 State variables (27)

`HotkeyMonitor` has three instances: talk (`AppDelegate.swift:30`), dictation (`DictationController.swift:272`), Polyglot
(`PolyglotController.swift:59`). Each holds 1 to 13. Pointing holds 14 to 27.

| # | Variable | Where | Meaning |
| --- | --- | --- | --- |
| 1, 2 | `state.modifiers`, `state.deviceKeys` | `Shortcut.swift:289-290` | Modifiers down as the last event said: a key-down overwrites them (`:335`), so they can be stale until the next flags event. Physical modifier keys down, from flags events only (`:318-329`) |
| 3, 4 | `state.keysDown`, `state.spoiled` | `Shortcut.swift:291-293` | Ordinary keys down. An ordinary key joined while a modifier key was down (`:348`); cleared when a flags event shows none (`:330`) |
| 5, 6 | `isDown`, `cancelledByLargerChord` | `HotkeyMonitor.swift:102-104` | Dedicated key: a press is counted as down; no press until the modifiers are empty (`:236`) |
| 7 | `latch` | `:105` | `TalkKeyLatch`: idle, holding(down, second), tapped(up), latched, ending (`ZeusCommand.swift:282-288`) |
| 8 | `pendingStop` | `:106` | The timer that sends a quick tap after 0.4 s |
| 9 | `directPressActive` | `:107` | The toggle mode last seen; a flip resets 5, 7 and 8 with no callback (`:225-231`) |
| 10, 11 | `sharedDown`, `gesture` | `:97-98` | Shared key: counted as down; `SharedKeyGesture`: idle, down(at, second, holding, spoiled), tapped(up) (`SharedKeyGesture.swift:10-14`) |
| 12, 13 | `holdTimer`, `commandLatched` | `:99-100` | The 0.25 s hold delay timer. Shared key, talk side: a hands-free command turn is open |
| 14 to 17 | a second `ShortcutState` | `PointingKeyGesture.swift:32` | As 1 to 4 |
| 18 to 21 | `isActive`, `blockedByVoiceOver`, `waitForRelease`, `activeSince` | `PointingKeyGesture.swift:29-34` | A hold is running; VoiceOver owns the chord; nothing begins until everything is up; when the hold began |
| 22 to 24 | `controlDownAt`, `controlTapClean`, `lastControlTap` | `:35-37` | The double Control tap |
| 25 to 27 | `turnOpen`, `announcedBlock`, `watchdog` | `PointingHotkeyMonitor.swift:50-53` | An end is owed; the VoiceOver notice was shown; the 0.25 s stuck key timer |

Wiring, not counted: the monitor and observer handles (`HotkeyMonitor.swift:95-96`, `PointingHotkeyMonitor.swift:49`,
`:54-55`). State outside the monitors that the key logic leans on: `WakeWordController.talkKeyHeld`
(`AppDelegate.swift:282`, `:289`), `topBar.isDictating` (`DictationController.swift:393`), `run.isActive`
(`PolyglotController.swift:120`), and the turn itself, never read by the monitor (`VoiceTurnController.swift:27`, `DictationFlow.swift:25-32`).

### 1.2 Sources of events

| Source | What arrives |
| --- | --- |
| Local monitor (Zeus's own windows, `HotkeyMonitor.swift:126-130`) and global monitor (other apps, once Accessibility or Input Monitoring is on, `:125`, `:134-139`) | Flags, key-down, key-up, through `convert` (`:141-149`): a flags event carries the whole modifier set, a repeat is dropped (`:145`) |
| Consumed key feed | The tiling tap turns a key it consumed into the event a monitor would have seen (`TileKeyMatcher.swift:54-60`) and posts it on the main queue (`TilingKeyTap.swift:270-273`); each monitor feeds it to itself (`HotkeyMonitor.swift:114-121`). Nothing orders it against the monitors' own events (`TilingKeyTap.swift:265-268`) |
| Timers and settings | The hold delay (`HotkeyMonitor.swift:199-206`) and the send after a tap (`:306-316`), stored work items. Settings (key, shared test, toggle test, VoiceOver) are read in `evaluate` (`:219-241`): a change shows only at the next key event. Nothing tells the monitor about sleep, wake or a release it could not see |
| Pointing | Its own event tap (`PointingHotkeyMonitor.swift:112-117`), the same feed (`:59-66`), the watchdog with the live modifiers (`:41-43`, `:98-110`), sleep, wake and display changes (`PointingController.swift:278`), `stop()` (`:81-88`) |

### 1.3 Transitions as the code behaves

`evaluate` picks a path at every event (`HotkeyMonitor.swift:223-235`): shared when the talk key the owner chose equals
the dictation key (`:88`); toggle for a dictation role with the toggle setting on its own key (`:224`); else the latch.
A bare `:n` below is a line of `HotkeyMonitor.swift`.

| Path | What the code does |
| --- | --- |
| Dedicated hold (talk; dictation "Hold to speak"): press | Pressed means held exactly and not `cancelledByLargerChord` (`:237`): the modifiers are equal, no ordinary key is down, the chord is not spoiled, the side matches (`Shortcut.swift:355-367`; Left and Right Command together still read as Right Command, `:365-366`). The press edge (`:251-258`) starts a turn from idle, continues a tapped one (a second tap when within 0.4 s), or ends a latched one at once and becomes `ending` (`ZeusCommand.swift:301-315`) |
| Dedicated hold: release | The release edge (`:259-270`): when Control, Option or Command joined (`:277-280`) the turn is cancelled, or only blocked when the latch is `ending` (`:285-299`). Otherwise the latch takes a key-up (`ZeusCommand.swift:317-337`): a first press of up to 0.3 s waits 0.4 s and sends; a second quick one latches hands-free; a longer one sends |
| Dedicated hold: Shift or Fn joins | Also a release edge: the exact hold fails and `:279` does not count them. For dictation the docs call it Shift means Return (`docs/VOICE-KEY.md:47`), but the Return is read from the live flags at delivery (`DictationController.swift:977`, `:1005`), so Shift joining ends the turn whatever comes next. For talk it is F1: the send timer runs with `isDown` false, `spoilHold` guards on `isDown` (`:170`), nothing cancels it, and a quick swap can latch |
| Dedicated hold: another key, or a larger set that shrinks | Another key down (`:154-157`): the talk monitor cancels (`:169-177`, `cancelsWhenSpoiled` from `AppDelegate.swift:287`); the dictation monitor does not (`:170`), and the release edge sends the turn or counts a tap. Command, Control, Option, then Command up starts a turn (`:237`) |
| An arrow and an Fn key | An arrow, F or navigation key-down carries the Fn flag and overwrites `modifiers` (`Shortcut.swift:335`); no flags event follows, so after its key-up an Fn hold key (the third VoiceOver fallback, `VoiceKey.swift:19`) reads as held and a turn starts. The same in `PointingKeyGesture` (`:44`). Not verified on hardware |
| VoiceOver fallback | VoiceOver on and the key Control-Option: `onBlocked` and nothing else, on every event while held (`:252-255`). The talk key itself moves to a fallback meanwhile (`VoiceKey.swift:23-27`, `:40`), same paths |
| Shared key (`handleShared`, `:185-216`) | Armed only on an exact hold (`:187`); before the hold begins an extra modifier other than Fn spoils the press (`:188-189`), and so does another key (`:161-165`). No VoiceOver check: it sits after the `return` at `:234`. Dictation role: after 0.25 s unspoiled the turn starts (`:199-206`, `SharedKeyGesture.swift:41-45`) and the key-up sends it (`:211`); a running hold tolerates every extra modifier (`:187` stops asking for exact), which is how Shift means Return here; only another key cancels it (`SharedKeyGesture.swift:48-55`). Talk role: two taps of up to 0.25 s, at most 0.35 s apart (`SharedKeyGesture.swift:16-18`, `:57-65`), start a hands-free command turn (`:212`); the next key-down sends it and is itself a first tap (`:192-197`) |
| Toggle (dictation "Press to start and stop"; Polyglot always, `PolyglotController.swift:110-115`) | The press edge calls `onPress`, the release edge nothing (`:238-250`); the owner decides start or finish (`DictationBehavior.swift:24-29`, `PolyglotController.swift:120`). A foreign modifier tapped during one hold makes a second press edge and toggles again. Polyglot's default key, Control-Option-T (`PolyglotSettings.swift:13`), is keyed: held when the modifiers are equal and T is down; other keys and `spoiled` are ignored (`Shortcut.swift:359-363`) |
| What a start costs | A talk press yields explanation audio, makes the wake word listener let go of the microphone and calls the companion (`AppDelegate.swift:585-592`), cancels the answer in flight (the fast race, the session's busy run, the turn task, the brain's turn) and stops speech (`VoiceTurnController.swift:128-145`), then opens the microphone, plays the listen sound, dips other audio, captures the screens and reads the front browser tab (`:153-178`). A dictation press reads the front app and the selected text, plays the start cue, opens the microphone and pauses media (`DictationController.swift:570-611`). A pointing start stops speech and the answer in flight too (`AppDelegate.swift:645`, `VoiceTurnController.swift:113-125`) |
| A press the owner refuses | `begin()` returns without a word while a job is transcribing or rewriting (`DictationController.swift:539`, `DictationFlow.swift:34-41`) or when the start fails (`:559`, `:598`); the talk press can return false (`VoiceTurnController.swift:163`, `AppDelegate.swift:586`, `:595-602`). The monitor counts the press as down all the same, and the key's cancel is `cancel()` (`DictationController.swift:367`), which drops any active job, a transcribing one included (`:723-727`) |
| Settings change; Esc | The key becomes nil while `isDown`: the turn is sent (`:219-222`). The toggle setting flips: the latch and `isDown` reset with no callback and an open turn runs on with no owner in the monitor (`:225-231`). `TalkKeyLatch.cancelFromEsc` (`ZeusCommand.swift:347-351`) has no caller in `Sources/Zeus`; dictation's own Esc cancels the turn (`DictationController.swift:613-616`) without telling the monitor, so a latched monitor stays latched and the next press is spent on a turn that is gone |
| Pointing (`PointingKeyGesture.feed`, `:41-68`) | A hold begins on an exact hold when not waiting (`:58-64`), unless VoiceOver owns Control-Option (`:59-60`). When no longer exact it ends if what is left is inside the key's set, unspoiled, with no key down (`:49-50`); otherwise it is cancelled and waits for everything to be up (`:51-55`). The watchdog and the interrupt empty the picture (`:80`, `:91`), so the wait clears on the next key event even with keys held (`:55`). Also the 95 s bound (`:75-84`), Esc and the double Control tap (`:66`, `:96-118`). The monitor adds one-turn bookkeeping (`PointingHotkeyMonitor.swift:120-144`) and starts no turn when the pointing key is the talk key (`VoiceKey.swift:31-33`). It starts on a shrink too |

## 2. What must not change

| Behaviour | Pinned by |
| --- | --- |
| A hold starts at once and the release sends | `TalkKeyLatchTests.holdToTalk`, `ShortcutTests.holdToTalkStartsAndStops`, `TilingConsumedKeyTests.aPlainHoldAndReleaseStillSendsTheTurn` |
| A quick tap sends after the gap; tap then hold is a hold; a double tap latches until the next tap | `singleTapStopsAfterTheGap`, `aSingleTapStopsAfterTheGap`, `tapThenHoldIsANormalHold`, `doubleTapLatchesUntilTheNextTap` (both suites) |
| The press that ends a hands-free turn sends once, cancels nothing, starts nothing | `theTapThatEndsALatchedTurnIsEndingUntilItsKeyUp`, `aModifierJoiningThePressThatEndedAHandsFreeTurnDoesNotCancelIt`, `theKeyThatEndedAHandsFreeTurnDoesNotStartANewOneWhenTheExtraModifierIsLetGo` |
| The owner ends a turn itself | `escapeCancelsHoldOrLatch` |
| Shared key: hold dictates, double tap talks, a shortcut is ignored or cancels, Shift does not end a running hold | `SharedKeyGestureTests` (5), `aSharedHoldOfExactlyItsOwnKeyStillStartsDictationAndExtraModifiersDoNotEndIt`, `aSharedHoldOfAPairInsideTheTilingPairDoesNotStartDictationWhenCommandComesFirst`, `aSharedHoldInTheSameOrderStartsNothingWhenTheRestOfThePairArrivesInTime` |
| A larger chord cancels, never sends | `aTalkTurnThatTheRestOfTheTilingPairEndsIsCancelledNotSent`, `aSlowPressOfTheSameOrderIsCancelledToo`, `aDedicatedDictationHoldThatTheRestOfThePairEndsIsCancelledNotInserted`, `aSingleModifierHoldThatAnotherModifierEndsIsCancelledToo`, `aModifierJoiningTheSecondTapOfADoubleTapStillCancelsTheOpenTurn` |
| Nothing restarts until every modifier is up | `aCancelledHoldDoesNotRestartWhenTheExtraModifierIsLetGo`, `aTalkHoldDoesNotStartWhenCommandIsReleasedFirstAfterAConsumedChord`, `aDictationKeyOnRightCommandDoesNotStartWhenTheOthersAreReleasedFirst`, `aModifierChangeHeardBeforeTheForwardedKeyOnlyCostsACancelledTurn` |
| The keyboard picture (`isHeld` stays as it is) | `ShortcutTests`: `optionCommandChord`, `aKeyPressedDuringTheChordSpoilsIt`, `rightCommandIsNotLeftCommand`, `repeatedFlagsChangedWhileHeldDoesNotReadAsARelease`, `anUnrelatedCommandShortcutElsewhereDoesNotSpoilALaterBareModifierHold`, `fnAloneAndKeyedShortcuts` |
| The feed carries one event and nothing else | `theNotificationCarriesTheEventAndNothingElse`, `withTheForwardedKeyTheTalkHoldStaysSpoiledUntilEveryModifierIsUpThenWorksAgain` |
| Pointing | `PointingKeyGestureTests` (9), `PointingRobustnessTests` (stuck keys, sleep, wake, display change), `PointingHotkeyMonitorTests` (6), `thePointingHoldStaysSpoiledToo`, `aPointingHoldDoesNotBeginWhenCommandIsReleasedFirstAfterAConsumedChord`, `aPointingHoldThatTheRestOfTheTilingPairEndsIsCancelledNotEnded` |
| One owner per hold; the VoiceOver fallback; every key monitor is read by the clash check | `VoiceKeyTests.everyHoldHasAtMostOneOwner`, `voiceOverKeepsControlOptionAndTalkMovesToAFallback`, `TilingKeyClashTests.everyKeyMonitorInTheAppIsAccountedForByTheLiveKeys` |

**One pinned behaviour changes.** `shiftJoiningAHoldStillEndsItTheNormalWay` pins that Shift joining a dedicated
dictation hold sends it. The swap and nudge chords are the pair plus Shift, so that rule lets a tiling chord send
dictation (C4). The test is renamed `shiftJoiningADictationHoldKeepsItUntilTheKeyIsLetGo` and expects no release while
Shift is held and one release when a key of the hold is let go with Shift still down. A second case in it: Shift let go
first, then the key, still one release and no latch, even when the press was a quick second tap.

**No test pins these today.** The toggle path through the monitor (Polyglot, press to toggle). The VoiceOver refusal in
the monitor. The talk side of the shared key through the monitor (`commandLatched`). A settings change mid turn. A key
joining a dedicated dictation hold. Fn joining a hold; an arrow and an Fn key. A keyed hold key (Option-Space) meeting
a foreign modifier or key. Left Command joining a Right Command hold. The shrink start. Esc while latched. A refused
press. The real timers, except through sleeps in `TilingConsumedKeyTests`.

**Changed on purpose.** Each row is unpinned today (C4 apart) and changes because a rule in part 3 demands it.

| # | Today | After |
| --- | --- | --- |
| C1 | Shift or Fn joining a talk hold is a release: sent, or a tap that can latch (F1) | Cancelled |
| C2 | A key joining a dedicated dictation hold is a release | Cancelled |
| C3 | Fn joining a shared key before its hold begins is ignored (`HotkeyMonitor.swift:188`); Command, Control, Option or Fn joining a running shared dictation hold is tolerated until a key lands | Foreign in both places: the press is dropped before the hold begins, the turn is cancelled during it |
| C4 | Shift joining a dedicated dictation hold ends it: sent after 0.4 s, or a tap that can latch | The turn runs on, as on the shared key. Letting go of the key sends it, with Shift still down (Return) or after Shift was let go (no Return), never as a tap and never hands-free. Anything else foreign cancels |
| C5 | A tap waiting out its 0.4 s, then a foreign key or modifier: sent | Cancelled |
| C6 | A larger set that shrinks to the key's set starts a turn, and fires a toggle again (talk, dictation, Polyglot, pointing) | Nothing until every modifier is up |
| C7 | Settings change mid turn: a nil key sends, a mode flip leaves the turn open | Cancelled |
| C8 | VoiceOver refusal repeats on every event and is skipped on the shared key | Once per press, in every mode |
| C9 | A keyed hold key that a foreign modifier joins is a release; a foreign key is ignored (`Shortcut.swift:359-363`) | Cancelled |
| C10 | A cancel with no `onCancel` falls back to `onRelease`, which sends (`HotkeyMonitor.swift:176`, `:298`) | A cancel never calls `onRelease` |
| C11 | A keyed key (Control-Option-T, Option-Space) pressed while another ordinary key is still down from rollover acts | Nothing, and nothing until every key is up |
| C12 | A foreign modifier tapped during one toggle press toggles again | One toggle per press |
| C13 | The other side of a sided key (Left Command beside Right Command) is not seen | Foreign: it bars a start and cancels a hold |
| C14 | A hold key inside a tiling chord starts the moment its set is down | While tiling runs it starts after 0.15 s alone, or by a double tap; a lone tap under 0.15 s does nothing; the press that ends a hands-free turn sends after 0.15 s or on a clean release (part 6) |
| C15 | An arrow, F or navigation key starts an Fn hold key on its key-up | Nothing: only flags events say which modifiers are down |
| C16 | A press the owner refuses counts as down; a later cancel can drop a transcribing job | The press is abandoned; the key's cancel reaches only a listening turn |
| C17 | A release the monitors never saw, or sleep, leaves the turn open until the next event | Ended within 0.25 s from the live modifiers; sleep and wake cancel an open turn |
| C18 | The owner's own end (dictation Esc) leaves the monitor latched and the next press is spent | The machine is told; the next press starts |

## 3. Safety rules

Words. The key's **own set** is its modifiers and its key code when it has one; for a sided key it is that one
physical key, and the other side is foreign. **Foreign** is a modifier outside the own set, or an ordinary key that is
not the key's own. A **press** lasts while the whole own set is down. A **turn** runs from `start` to `send` or
`cancel`, and is **hands-free** while the machine says `isLatched`. The rules hold after every step (a key down or up,
a forwarded key arriving, time passing, an `abandon`) of every order; the search in part 5 checks them from the keys the
machine has been told are down, the effects and `isLatched`, and reads nothing else of the machine.

| Rule | Checkable statement |
| --- | --- |
| **I1.** A press that something foreign joined never sends and never latches | For every `send` of a turn that is not hands-free, nothing foreign was down at any step from its `start` to the `send`. One exception: on a dictation key Shift may be down, alone, and the `send` then comes only at a step where the key is let go (hold Shift while releasing means Return, `DictationController.swift:977`); the step where Shift joins never sends. For a talk key Shift is foreign like any other key. A turn becomes hands-free only if nothing foreign was down since its `start`, Shift included, so a press that Shift joined is sent when the key is let go, never latched. A hands-free turn is sent only by a press of exactly the own set: at the step the set came down when `confirm` is 0, otherwise once it stayed down alone for `confirm` or was let go with nothing foreign down since the press began. Typing and larger chords neither send nor cancel it |
| **I2.** After a cancel, nothing starts until everything is up | No `start` after a `cancel` until every key is up |
| **I3.** Nothing starts on a larger chord | No `start` at a step where the keys down are a strict superset of the own set |
| **I4.** Every turn ends exactly once | `start` is followed by exactly one `send`, `cancel` or `abandon` before the next `start`; no `send` or `cancel` without an open turn. With every key up and every timer run out, only a hands-free turn is open |
| **I5.** A consumed key is a key | The machine's event has no field that says where a key came from, so a consumed key and the same key unconsumed give the same effects. A forwarded key that comes ahead of the flags event of the modifier pressed before it leaves every other rule holding. A forwarded key that waits behind three later events cannot be held to the rules by any reducer: with the three modifiers of a bound chord let go and the arrow still held, the machine is told that every key is up (third pass, finding 24) |
| **I6.** Nothing starts when a larger chord shrinks | Once the whole own set has been down with something foreign, no `start` until every key is up. This closes the gap `TilingKeyTap.swift:265-268` calls bounded, whatever the feed's order |
| **I7.** A toggle fires once per press | At most one `start` per press of a toggle key, and none while I2 or I6 bar it. A toggle cannot be taken back, so I1 and I4 do not apply to it; part 6 refuses the pairs that would need them |
| **I8.** Never stuck | From every state, letting go of everything, waiting 0.5 s, then pressing exactly the own set acts. Acts: a hold key gives `start` once held for `confirm` (`send` when a hands-free turn was open); a toggle gives `start`; a shared dictation key gives `start` after 0.25 s; a shared talk key gives `start` on the second of two quick clean taps; a key VoiceOver holds gives `refused` |

## 4. The target

### 4.1 One reducer

`Sources/ZeusCore/VoiceKeyMachine.swift`, about 200 lines, `Sendable` and `Equatable`, no clock, no timer, no callback.

```swift
public struct VoiceKeyMachine: Sendable, Equatable {
    public enum Role: Sendable, Equatable { case talk, dictation }
    public enum Mode: Sendable, Equatable { case hold, shared, toggle }
    public struct Config: Sendable, Equatable { var key: Shortcut?; var role: Role; var mode: Mode; var voiceOverHoldsKey: Bool; var confirm: TimeInterval }
    public enum Event: Sendable, Equatable {
        case key(ShortcutEvent, at: TimeInterval)              // from a monitor or from the feed: no way to tell
        case tick(at: TimeInterval, live: ShortcutModifiers?)  // a wake the machine asked for, with the modifiers the system reports now
        case abandon(turn: Int)                                // the owner refused the press or ended that turn itself
        case interrupt(live: ShortcutModifiers?)               // sleep or wake
        case sweep(live: Set<UInt16>)                          // the ordinary keys the system reports down now; the picture drops the rest
    }
    public enum Effect: Sendable, Equatable { case start, send, cancel, refused, wake(after: TimeInterval) }
    public enum Press: Sendable, Equatable { case first, second, ending } // ending: this press will end a hands-free turn
    public enum Phase: Sendable, Equatable {
        case idle                                              // nothing open, no press counted
        case armed(since: TimeInterval, press: Press)          // the key is down alone and has not acted yet
        case holding(since: TimeInterval, second: Bool, check: TimeInterval, shifted: Bool) // a turn is open and the key is down; shifted: Shift joined it (dictation role)
        case tapped(at: TimeInterval, open: Bool)              // the key is up after a quick tap; open: its turn waits for the gap
        case latched                                           // hands-free: a turn is open and the key is up
        case spent                                             // the key is down and this press has done all it will do
    }
    public var isLatched: Bool { get }
    public mutating func handle(_ event: Event, config: Config) -> [Effect]
}
```

The whole state is four values: `config` (the last one seen, nil before the first), `keys` (a `ShortcutState`, the
picture of the keyboard), `barred` (nothing may begin until everything is up) and `phase`. The adapter reads the config
at every event: `key` nil is off; `mode` is the choice made today at `HotkeyMonitor.swift:223-224`; `voiceOverHoldsKey`
means VoiceOver is on and the key is Control-Option; `confirm` is how long a hold key must be down alone before it
acts, 0 except in part 6. Times keep today's values: hold 0.3 s tap and 0.4 s gap (`ZeusCommand.swift:290-291`); shared
0.25 s hold delay, 0.25 s tap, 0.35 s gap (`SharedKeyGesture.swift:16-18`); a due check allows 1 ms (`:42`). The
**delay** of a press is `confirm` for a hold key and 0.25 s for a shared dictation key. A `wake` asks for a `tick`
later; the machine decides from the tick's time and its own phase, so a late or stale tick does nothing and nothing
ever needs cancelling. A config **differs** from the last one when its key, mode or `voiceOverHoldsKey` differ; a new
`confirm` is only stored (tiling switching on or off must not end a hands-free turn), and `role` never changes after
the monitor is made. `ShortcutState` becomes `Equatable` (step 1), so the machine can be.

### 4.2 Key facts

`ShortcutState` gains one value and one function; `isHeld` and `modifiers` stay, with their tests. `flagModifiers` is
the modifier set of the last flags event: a key-down adds a key and never writes it, so the Fn flag an arrow carries
and a pasted Command-V change nothing. `resync(to:)` sets both modifier values to the live set the adapter read, keeps
device keys only for modifiers still down, and forgets ordinary keys; it replaces `reset()` where a monitor keeps
running. `KeyFacts.swift` is a pure function of a `ShortcutState` and a `Shortcut`, read by the machine and by pointing.

| Fact | Meaning |
| --- | --- |
| `ownDown` | Every modifier of the key is in `flagModifiers`; for a sided key its own device key is down; for a keyed key its key code is down |
| `foreignModifier` | `flagModifiers` holds a modifier outside the key's set (Fn does not count for a keyed key that does not ask for it, as `Shortcut.swift:359`: a laptop F key needs it), or the other side of a sided key is down |
| `foreignKey` | Modifier-only key: an ordinary key is down, or `spoiled`. Keyed key: an ordinary key other than its own is down |
| `allUp` | `flagModifiers` is empty and no ordinary key is down. True at launch; after a `resync` it is what the system reports |

One **reading** per event, from the facts and the role. **E**, exact: `ownDown` and nothing foreign. **R**, let go: not
`ownDown` and nothing foreign. **S**, Shift only, dictation role only: Shift is the one foreign thing down (for a talk
key Shift is plain foreign). **F**, foreign: anything else.

### 4.3 The transition table

Before the row, in this order: (1) a key event is applied to `keys`; an `interrupt` resyncs `keys`; (2) the first
config is stored and is no change; when a later one differs (4.1), emit `cancel` if a turn is open (holding, tapped
open, latched, armed ending), go to idle, store it, and set `barred` unless every key was up before this event (the
adapter hands the config over with an event, so the press that reveals a change made with the mouse is itself a key
down, and nothing was held through the change; a nil key stops here); (3) `barred`
becomes false when `allUp`, else true when `ownDown` with anything foreign; (4) the row. **Begin** means reading E and
not `barred`. Every `cancel` also sets `barred` unless `allUp`. Quick means within the mode's tap time.

| # | Phase | Input | Mode | Next phase | Effects |
| --- | --- | --- | --- | --- | --- |
| 1 | idle | begin, `voiceOverHoldsKey` | any | spent | `refused` |
| 2 | idle | begin | toggle | spent | `start` |
| 3 | idle | begin | hold, `confirm` 0 | holding(t, first) | `start`, `wake(0.25)` |
| 4 | idle | begin | hold with `confirm`; shared | armed(t, first) | `wake(delay)`; shared talk: none |
| 5 | armed(since, press) | tick, the delay since | hold; shared dictation | first, second: holding(since, second, not shifted). Ending (hold only): spent | `start`, `wake(0.25)`. Ending: `send` |
| 6 | armed(since, press) | R | hold; shared talk | ending (hold only): idle. Quick and second: latched. Quick and first: tapped(t, not open). Else idle | ending: `send`. Latched: `start` |
| 7 | armed | R | shared dictation | idle | none |
| 8 | armed(press) | F or S | any | ending: latched. Else idle | none |
| 9 | holding(since, second, shifted) | R | hold | not shifted, quick and second: latched. Not shifted, quick and first: tapped(t, open). Else idle | tapped: `wake(0.4)`. Else `send` |
| 10 | holding | R | shared | idle | `send` |
| 11 | holding | F | any | idle | `cancel` |
| 12 | holding | S with the key still down | any | holding, shifted | none |
| 13 | holding | S with the key let go | any | idle | `send` |
| 14 | holding | tick at the check time | any | holding as it was, next check 0.25 s on | `wake(0.25)` |
| 15 | tapped(at, open) | begin | hold | holding(t, second when within 0.4 s of at, not shifted) | `wake(0.25)` |
| 16 | tapped(at, open) | F or S | any | idle | `cancel` |
| 17 | tapped(at, open) | tick, 0.4 s since at | any | idle | `send` |
| 18 | tapped(at, not open) | begin | hold; shared talk | armed(t, second when within the gap of at) | hold: `wake(confirm)` |
| 19 | tapped(at, not open) | F or S | any | idle | none |
| 20 | latched | begin, `confirm` 0 | hold; shared talk | spent; shared talk: armed(t, first) | `send` |
| 21 | latched | begin, `confirm` above 0 | hold | armed(t, ending) | `wake(confirm)` |
| 22 | spent | R, F or S | any | idle | none |
| 23 | holding, tapped open, latched, armed ending | `abandon(turn)`, `turn` the machine's `generation` | any | idle, `barred` unless `allUp` | none. In any other phase, or for any other `turn`, an `abandon` is row 25: a toggle has no turn to abandon, and the echo of a turn the machine ended or replaced is not the turn now open |
| 24 | any | `interrupt` | any | idle, `barred` unless `allUp` | `cancel` when a turn was open |
| 24b | any | `sweep(live)` | any | unchanged; the picture keeps only the ordinary keys in `live`, and step (3) runs on it, so `barred` clears when that leaves every key up | none |
| 25 | any | anything else | any | unchanged | none |

Rows 5, 14 and 21 (the wake of an ending press) first compare the key with the tick's live modifiers, which stand for
a flags event that has not arrived. When they no longer hold the key's modifiers a release was missed and `keys` is
resynced; when they hold a modifier outside the key's own set (a Command pressed after the pair, its event still queued
behind a busy main thread) it is adopted into the picture, ordinary keys kept, with the Fn rule of `KeyFacts`. In both
cases the row for the new reading runs instead (6 to 8, or 9 to 13), so the order of the wake and the queued event
decides nothing; a hold that is still running asks for its next check. `PointingKeyGesture.confirmElapsed` does the same.

How the rules follow. I3: only a begin starts or arms, and a begin needs reading E. I2 and I6: `barred` is set by every
cancel and by step 3, cleared only at `allUp`, and a begin needs it false. I1: from an open turn that is not hands-free
the only exits when something foreign shows are rows 11 and 16, which cancel, and row 13, the Shift release; Shift
joining is row 12, which only marks the turn shifted and sends nothing, and row 9 sends a shifted turn at the key
release and never taps or latches it; row 8 drops a press that has not acted and leaves a hands-free turn as it was.
I4: a turn is open only in holding, tapped open, latched and armed ending; `start` appears only on entering them (rows
3, 5, 6; row 2 opens no turn here), and every move out carries exactly one `send` or `cancel` (rows 5, 6, 9 to 11, 13,
16, 17, 20, 24, step 2) or is an `abandon`. I5: `Event.key` is the only way a key gets in. I7: rows 1 and 2 go to
spent, which no begin leaves. I8: every phase reaches idle at `allUp` or keeps a turn the next begin ends. F1 with
tiling running: Control, Option is row 4; Shift is row 8 for a talk key (idle, `barred`), or row 11 (`cancel`) when
pressed slowly. The swap chord on a dictation key: Shift is row 8 or 12, Command row 11 or nothing. Nothing is sent.

### 4.4 The adapter

`HotkeyMonitor` keeps its providers (`HotkeyMonitor.swift:74-90`), the monitors, `convert` and the feed observer
(`:114-149`). Everything else goes. What is left is one stored `machine`, injectable `now` and `liveModifiers` (as
`PointingHotkeyMonitor.swift:41-44`), a `confirmProvider` that defaults to 0, and four entries: `feed(_:)` sends
`.key(event, at: now())`, `tick()` sends `.tick(at: now(), live: liveModifiers())`, `turnEnded()` sends `.abandon`, and
the sleep and wake notices (as `PointingController.swift:297-300`) send `.interrupt`. Before a key event, while the picture holds an ordinary key,
`feed(_:)` asks the system which of those keys are down (`keysStillDown`, the hardware state, installed by `start()`) and
sends `.sweep`: an ordinary key whose key-up no monitor saw (Tab out of a username field into a password field turns
secure input on before Tab comes up) would otherwise read as a foreign key for ever. Pointing does the same through
`PointingKeyGesture.sweep`. The effects map `start` to
`onPress`, `send` to `onRelease`, `cancel` to `onCancel`, `refused` to `onBlocked` with today's sentence (`:241`), and
`wake(after:)` to one `asyncAfter` that calls `tick()`. It stores no timer and no flag; besides `machine` it keeps one number, the `generation` the machine gave the last turn
`onPress` was asked to start, which `turnEnded()` sends as the turn it ends (the k-th `start` of a `handle` is turn
`generation before + k`). The effects of one `handle` run in order after it has returned, so an owner that calls `turnEnded()` from
inside `onRelease` meets the machine in its new state; when the same `handle` also opened a turn (`[send, start, wake]`: a
quick tap, a late tick, the next press), the echo names the old turn and the machine leaves the new one alone. Both monitors and the feed call the same `feed`, which is I5 at
the adapter.

The owners change in three small ways, so the machine is never wrong about the turn. An `abandon` that reaches a
machine with no open turn does nothing (row 23).

| Change | Where |
| --- | --- |
| `onPress` returns whether the owner took the press; false sends `.abandon` | Talk returns what `press()` returns (`VoiceTurnController.swift:128`; `talkKeyPressed` returns false at the guards of `AppDelegate.swift:586`, `:595` and takes the value of `voice?.press()` at `:603`), dictation returns `flow.isListening` after `begin()` and true after `finish()` (`DictationController.swift:392-397`), Polyglot returns true. Where `talkKeyPressed` returns false it also clears `WakeWordController.talkKeyHeld` (set at `:589`, cleared only by the release and cancel closures at `:282`, `:289` today), because no release will follow |
| Each owner calls `turnEnded()` when its turn stops listening for any reason | Dictation where the flow leaves listening (`apply`, `DictationController.swift:503-520`, which Esc at `:613-616` reaches); talk in a `didSet` on `listening` (`VoiceTurnController.swift:27`), which also clears `talkKeyHeld`. After the machine's own `send` or `cancel` no turn is open, so row 23 ignores that echo |
| The dictation key's cancel drops only a listening turn | `flow.isListening`, then `cancel()` (`DictationController.swift:367`), as the talk key's already does (`VoiceTurnController.swift:205-206`) |

### 4.5 Pointing keeps its own reducer

`PointingKeyGesture` does not join. It is already a pure reducer, an explicit entry in `docs/STATE-MACHINES.md:170`,
with three suites (`PointingKeyGestureTests`, `PointingRobustnessTests`, `PointingHotkeyMonitorTests`); it has no tap, latch or toggle, and its outputs are pinned one by one (a timed out hold is not an ended one,
`PointingHotkeyMonitor.swift:109`, `:139`): one reducer for both would be two tables behind a mode switch, plus a
wrapper to keep the old outputs. What must be the same is the rule, so pointing reads the same `KeyFacts`, runs under
the same search and invariants, and takes four small changes. (1) Began, ended and cancelled are read from `KeyFacts`
(E, R, anything else), not from `isHeld` and `modifiers` (`PointingKeyGesture.swift:44`, `:49`). (2) `waitForRelease` is also set when the own
set is down with something foreign and no hold is active (I6), and cleared on `allUp`, not by `:55`. (3) `tick` and
`interrupt` take the live modifiers and `resync` where they `reset()` (`:80`, `:91`), so the wait cannot clear while a
key is held. (4) It takes the same `confirm`: an exact hold gives a new output `armed`, the monitor asks for one
`confirm(at:)` after the delay, and `began` comes then if the hold is still exact; a shorter tap begins nothing.

## 5. Tests first

**The search.** `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift`, pure, no sleep. It explores the whole graph of reachable
states, so it covers every order of presses and releases at every length, with no cut-off: each state is expanded once
with every move, and a visited set ends the search. Time is a whole number of 0.05 s steps, of which every threshold is
a multiple (0.15, 0.25, 0.3, 0.35, 0.4), and the state key is the machine's config, keyboard picture, `barred` and phase with
ages in place of times, capped at 0.45 s, past every window, so the graph is finite. The pointing gesture gets the same key, which asks
`PointingKeyGesture` to be `Equatable` (step 4); its 95 s bound (`PointingKeyGesture.swift:26`) is past the cap and stays
with `PointingRobustnessTests`. The moves: toggle one physical key (a press if it is up, a release if it is down, so every order is valid), its event reaching the machine at once or held back for the next forwarded key;
wait 0.05 s (not while an event is held back); deliver the held event; `abandon`; `interrupt` (not while an ordinary key
is down, because a resync forgets ordinary keys by design); in run B, flip the config on a tick. The harness is the stand-in adapter:
it keeps the wakes and delivers each due `tick` with the true modifiers. Four more moves, each added only to the runs whose rules read it, put the adapter and the owner in the search (fourth pass): a timer may be late, so a key reaches the machine before the tick that was due ahead of it (A, A0, D, E, I), and the checker then reads the effects that timer owes on the keyboard as it was; a config change may ride on the next event of any kind (run J, dictation Right Command, hold, toggle, off); an ordinary key may come up with no event (F, G, H, I), and the harness sweeps before each key event as the adapter does; the owner may refuse the turns it is asked to start (A0). After every `send` or `cancel` the harness feeds the owner's echo, an `abandon` naming its turn, and after every call the machine's `generation` and open turn must agree with the rules, and a press that comes down from a keyboard with everything up is never barred. A missed key-up of a foreign key is now a move; a missed release of a modifier is still held by the unit tests of rows 5, 14 and 24 and by Mac check 10. A key-down is offered to the real
`TileKeyMatcher` with `TileKeymap.defaults(base: .standard)`; a consumed key becomes `TileKeyDecision.monitorEvent` and
the forwarded key reaches the machine at once, and one monitor event may be held back behind it, so the machine can hear a
forwarded key before the flags event of the modifier pressed ahead of it. After
every move a checker asserts I1 to I7 from the effects, the keys the machine has been told are down and `isLatched`; at every state it
also lets go of everything, waits 0.5 s, presses the own set and asserts I8 and the last clause of I4.

| Tests | What they hold |
| --- | --- |
| The runs of the search (all ten built) | The keys are Control, Option, Command, Shift and one ordinary key (Left arrow; T in run G), plus what is named. **A** talk, hold, Control-Option, `confirm` 0.15 (shipped talk beside tiling). **A0** the same, `confirm` 0. **B** dictation, hold, Right Command, `confirm` 0.15, with Left Command as a sixth key and a move that flips the config between hold, toggle and off (shipped dictation). **C** dictation, hold, Control-Option, `confirm` 0.15. **D** dictation, shared, Control-Option. **E** talk, shared, Control-Option. **F** dictation, toggle, Right Command. **G** toggle, Control-Option-T (shipped Polyglot). **H** `PointingKeyGesture`, Control-Option, `confirm` 0.15 (shipped pointing): began is `start`, ended and timed out are `send`. **I** talk, hold, Fn, the Globe key in place of Command. **J** (fourth pass) dictation, hold, toggle and off on Right Command with Control, Shift and Left, where each config change rides on the next key event. G gains Left as a sixth key, for the missed key-up |
| How many, and how long | Sequences are without number, because no length is cut off; what is counted is states and moves, and the test prints both for each run. Measured at step 3 in a debug build on a loaded Mac (load average 60 to 100): A 10,659 states, 84,781 moves, 3 s; A0 6,648, 52,813, 2 s; B 176,105, 1,754,811, 23 s; C 21,677, 172,434, 5 s; D 8,779, 69,741, 3 s; E 7,014, 55,741, 3 s; F 1,356, 10,775, under 1 s; G 1,441, 11,434, under 1 s; I 3,150, 24,955, 1 s. Measured at step 4 in the same way: H 9,163 states, 63,505 moves, 14 s. The key of run H leaves out the double Control tap, whose three timers only ever produce `doubleTapControl`, which no rule reads; with them the graph had 616,396 states and 4,270,621 moves and took six minutes. As a check on the state key, run A is also walked plainly from rest, every order up to 5 steps over eight moves (the five keys, wait 0.05 s, wait 0.5 s, `abandon`): 8 + 64 + 512 + 4,096 + 32,768 = 37,448 sequences, which meet no state the search did not and break no rule (6 s). The suite takes 23 s in parallel, run B alone; the budget of 5 s is not met, and the fallback (`abandon` and `interrupt` in A and B only) would not bring B down, so it was not taken. Measured at the fourth pass (same Mac, loaded): A 42,745 states, 344,878 moves; A0 13,824; C 21,677; D 32,679; E 7,014; F 1,764; G 8,613; H 11,991; I 4,740; J 53,295, 432,486 moves; B 176,053, 1,605,323 moves; the suite takes about 110 s in parallel, B alone 110 s |
| `Tests/ZeusCoreTests/VoiceKeyMachineTests.swift` | One test per row of 4.3, the prelude steps (the first press after launch acts; a config change), F1's order, the swap chord on a dictation key in both orders (Control, Option, Shift, Command, Left; Right Command, Shift, Control, Option, Left), a missed release found by a tick, a forwarded key that comes before the flags event of the last modifier, a dictation press that Shift joins and lets go, released as a quick second tap (sent once, never latched), and each row C1 to C18 |
| `Tests/ZeusCoreTests/KeyFactsTests.swift` | Every fact for a modifier-only, a sided and a keyed key; an arrow key-down carrying Fn and its key-up leave an Fn key not held; a key-down carrying Command leaves `allUp` true; Left Command is foreign to Right Command; after a resync, one modifier let go and pressed again is never `allUp` in between |
| The existing suites, which stay | `TalkKeyLatchTests` (`Tests/ZeusCoreTests/ZeusCLITests.swift:99-149`), `SharedKeyGestureTests` and the rig in `ShortcutTests.swift:169-230` keep their names, timelines and expectations, and drive the machine with `confirm` 0 in place of the two deleted types (`stopLater(0.4)` reads `wake(after: 0.4)`, `cancelPendingStop` reads no effect, `isLatched` stays, `isEnding` reads `phase == .spent`, `cancelFromEsc` reads `abandon`). `TilingConsumedKeyTests` loses the `cancelsWhenSpoiled` setter at `:134` and takes the one change of part 2. The pointing suites pass the live modifiers to `interrupt`; a new case: interrupt, one modifier let go and pressed again begins nothing |
| `Tests/ZeusAppTests/HotkeyMonitorMachineTests.swift` and a dictation test | F1's order through the real monitor sends and latches nothing; a key joining a dictation hold cancels; a cancel never calls `onRelease`; a toggle fires once per press; the VoiceOver refusal comes once; a consumed key and the same key fed directly give the same callbacks; a refused press followed by a foreign key calls neither `onRelease` nor `onCancel`; `turnEnded()` while latched lets the next press start. Dictation: a refused press while a turn is transcribing, then a foreign key, leaves that turn alone |

## 6. The tiling clash rule

Once the machine holds I1 to I8, the rule needs no knowledge of how a monitor cancels. Let **B** be the modifier sets of
the chords the keymap really binds, without Fn (`TileKeymap.bindings`, `TileKeybind.swift:56`): for the default table,
the pair and the pair plus Shift (`TileKeybind.swift:117-131`); an edited keymap can bind any set that holds Control,
Option or Command (`TileKeybind.swift:64-71`), and the rule reads whatever is bound. For each modifier-only Zeus key
(talk as the monitor hears it, pointing, dictation, Polyglot; `TileBaseConflicts.swift:59-62`) let **K** be its
modifiers without Fn: the tap matches an arrow, F or navigation key with or without the Fn flag
(`TileKeybind.swift:89-94`), so a key that differs from a bound set only by Fn counts as equal, the safe side. A key that
is Fn alone is free. A dictation hold key has one more case: Shift joining it is not foreign (reading S), so for it K
plus Shift counts as equal to a set in B too.

| K against B | Hold key | Key that switches on at the press (press to toggle dictation, modifier-only Polyglot) |
| --- | --- | --- |
| K equals a set in B | Refused | Refused |
| K is strictly inside a set in B | Free, with `confirm` 0.15 s while the tap is installed | Refused |
| K is inside no set in B | Free | Free |

In one sentence: a modifier-only key is refused when its modifiers (a dictation hold key: with or without Shift) equal
those of a bound chord, a key that switches on at the press is refused when its modifiers are inside those of a bound
chord, and a hold key inside one waits 0.15 s.
It is total: every key lands in one cell. `TileBaseConflicts.notes` keeps its signature and takes B from the keymap it
is given; a note names the bound chord's modifiers ("Control-Option-Command-Shift is also your Dictation key"), not
`base.label` (`:71`). `TileBaseConflicts.confirm(for:keymap:)` is the middle cell as a pure function; each owner's
`confirmProvider` calls it with the installed tap's keymap (the controller keeps it at `TilingController.swift:131`, the
layer at `TilingKeyLayer.swift:60`; an accessor beside `isInstalled`, `:68`, is new, and reads nil, so `confirm` 0, when
no tap is installed).

| Still refused | Why |
| --- | --- |
| Equal (today only against the pair, `:67`; F2) | Every chord of that set has exactly the key's modifiers down before its key lands, in every press order, so the turn would start on every such chord, and a forwarded key that comes late could not be told from a clean hold (I5). A dictation key recorded as the pair plus Shift (the recorder takes any modifier peak, `Shortcut.swift:395-403`) is now refused, and so is the pair plus Fn. For a dictation hold key the set minus Shift is refused too: Shift joining it only marks the turn (row 12), so a bound chord of the key's modifiers plus Shift would reach its own key before anything foreign showed, and a late forwarded key would look like a clean release (I1, I5). The default table never meets this: Right Command plus Shift is not a bound set |
| A toggle inside (today only against the pair, `:80-81`; F2) | The smaller set down first fires the toggle, and I7 says it cannot be taken back. Now also caught against the pair plus Shift, for example a key that holds Shift |
| A keyed Zeus shortcut the keymap binds (`:88-100`); VoiceOver on and a bound chord holds Control and Option (`:55-57`) | Unchanged: the tap would swallow the first, and VoiceOver owns the second |

**The shipped pair stays Control-Option-Command** (`TileKeybind.swift:12`). Shipped talk and pointing are Control-Option
and shipped dictation is Right Command in hold mode: hold keys strictly inside, free, with the confirm. Shipped Polyglot
is keyed and its chord is not bound. No other pair is better: Control-Option equals the talk key, and Option-Command
holds Right Command and is where talk moves while VoiceOver runs (`TileKeybind.swift:9-11`, `VoiceKey.swift:19`). The
tests `theShippedDefaultsClashWithNothing` and `theShippedDefaultPairClashesWithNoShippedDefaultKey` stay as they are.

**Can the microphone open, even briefly, on a tiling chord with shipped defaults?** Without a rule, yes, whenever
Control and Option land before Command (two of the six orders; with Right Command first, dictation), and that start is
not cheap: it stops speech and throws away the answer Zeus was still working on, makes the wake word listener let go of
the microphone, plays the listen sound, dips other audio, shows listening, and begins a screen capture and a browser
tab read; dictation plays its cue, pauses media and reads the selected text (1.3). The cancel that follows sends
nothing and brings none of that back. So a rule is planned, the simplest that fits: the confirm. A hold key inside a
bound chord acts only after its own set has been down alone for 0.15 s (rows 4, 5, 21).

With the confirm the plain answer is: only on a chord pressed one key at a time. If Control and Option stay down alone
for 0.15 s or more before Command lands, the talk turn starts and the owner sees and hears all of the above, then the
turn is dropped in silence (`VoiceTurnController.swift:205-223`; dictation shows "Dictation cancelled",
`DictationController.swift:723-727`). Nothing is sent, inserted or latched, and nothing starts again until every key is
up. Pressed as a chord, or fast, nothing opens, nothing is interrupted, and a hands-free turn that was
running stays open (row 8). The same holds for dictation on Right Command, with Right Command as the key that must stay
down alone for 0.15 s. The price: while tiling runs, talk and dictation on these keys start 0.15 s after the
press, and a lone tap shorter than that does nothing (a double tap still latches). 0.15 s is a first value, not
measured; Mac check 2 sets it. With tiling off the keys behave as today.

Accepted, and named: with `confirm` 0 the press that ends a hands-free turn sends at the key-down, as the three tests
of part 2 pin, so another larger chord pressed own set first (Control-Option-Space for Chat) ends a hands-free talk
turn there. Not planned: a talk start split into a quiet microphone and a later barge-in. Speech must stop for the
microphone to hear, so the answer is lost either way, and the split needs the same timer.

## 7. Steps

Small commits that each build. A step named "failing tests" builds and its new tests are red until the next step. A
step that adds, deletes or renames a Core file or suite updates the lists in `qa/portable-core/prepare.py` in the same
commit; today they name `Pointing/PointingKeyGesture.swift` and `PointingKeyGestureTests` (`:117`, `:123`) and none of
the files this plan adds or deletes, which steps 2 and 9 check again. No setting is added or changed, so the settings
catalog and `docs/settings-inventory.md` stay as they are.

| # | Commit | What |
| --- | --- | --- |
| 1 | Add the flags-only modifier picture and the key facts both key reducers read | `ShortcutState.flagModifiers`, `resync(to:)` and `Equatable`, `KeyFacts.swift`, `KeyFactsTests.swift`. Green |
| 2 | Add failing tests for the voice key machine and the search over every press order | `VoiceKeyMachine.swift` with the types of 4.1 and a `handle` that only applies keys; `VoiceKeyMachineTests`, `VoiceKeyWalkTests`. Red. Record states, moves and time in part 5 |
| 3 | Fill the voice key machine from its transition table | Rows 1 to 25. Search green for runs A, A0, B to G and I |
| 4 | Hold the pointing gesture to the same facts and the same start rule | The four changes of 4.5, and `PointingKeyGesture` becomes `Equatable` for the search. Search green for run H; the pointing suites keep their expectations |
| 5 | Drive the latch and shared gesture suites through the machine | The ports of part 5 (`ZeusCLITests.swift`, `SharedKeyGestureTests.swift`, `ShortcutTests.swift`). Green; the two old types have no test left |
| 6 | Add failing monitor tests for the press orders the reviews found | `HotkeyMonitorMachineTests` and the dictation test. Red |
| 7 | Make HotkeyMonitor an adapter over the voice key machine | 4.4 without the owners' calls. Deletes the flags and functions below; `onPress` returns a Bool in its three owners. Monitor tests green |
| 8 | Tell the key machine when its owner refuses or ends a turn | `turnEnded()` from `DictationController.apply` and from `listening`; the dictation key's cancel checks listening; sleep and wake send `interrupt`. Dictation test green |
| 9 | Delete TalkKeyLatch and SharedKeyGesture | No caller is left |
| 10 | Add failing tests for a key on the modifiers of any bound tiling chord | `TileBaseConflictsTests`: equal to the pair plus Shift (hold and toggle), the pair plus Fn, a toggle inside the pair plus Shift only, a hold inside free with a confirm, Fn alone free, a dictation hold key one Shift short of a bound set refused and a talk key in the same place free with a confirm, a keymap with a chord on one modifier, the note names the chord, the copy has no dashes |
| 11 | Compare modifier-only keys with every modifier set the tiling keymap binds | Part 6 in `TileBaseConflicts.notes` and `confirm(for:keymap:)`; rewrite its header comment (`:3-30`) |
| 12 | Wait out a short confirm before a hold key inside a tiling chord acts | The `confirmProvider` of talk, dictation and pointing reads the installed keymap. Monitor test: with a confirm, the chord pressed fast calls nothing |
| 13 | Add failing tests for the three tap findings | The stand-in system tests named in steps 14 to 16. Red |
| 14 | Create the tiling tap disabled until its thread installs it | `create()` disables the port right after `system.create` (`TilingKeyTap.swift:133-139`); install enables it after adding the source (`:149-150`); fix the comment at `:154` and the one at `TilingRunLoopThread.swift:15-16`. Test: the first switch is off on the owner's thread, the next is on, on the tap thread |
| 15 | Close the tiling gate under the lock when the tap stops | `stop()` sets `snapshot.gate.enabled = false` in its locked region (`:175-180`). `start()` says in its contract that `update` comes first: a stop leaves the gate closed, and the layer already calls `update` before every start (`TilingKeyLayer.swift:113-114`). Test with the teardown held open, through an internal entry that decides one `TileKeyEvent` (the part of `handleKey` at `:226-230`): a bound chord decided after `stop()` took the lock passes through |
| 16 | Switch the tiling tap on from its own thread | `start()` in the enable case makes no system call under the lock (`:118-123`): it asks the tap thread (`TilingRunLoopThread` gains `perform`, a block on its loop plus a wake, as `stop` does at `:63-64`), and the block switches the port on only while the life is still running. A `perform` asked before the loop exists waits for it, and is dropped when a stop came first (`TilingRunLoopThread.swift:75-82`). The give-up and the teardown run on that thread too (`TilingKeyTap.swift:242-258`, `:153-159`), so an enable cannot land after either. Tests: a `setEnabled` that takes the tap's lock returns; an enable asked for before a give-up or a stop is not applied after it |
| 17 | Record the voice key machine in the docs | `docs/VOICE-KEY.md`: "Chords" (`:37-56`) becomes the rules of part 3 and the plain answer of part 6, with what a start costs, and drops `cancelsWhenSpoiled`, `cancelHold`, `TalkKeyLatch.isEnding`, `finishEndedTurn` and `otherKeyPressed` (`:40`, `:47`, `:50`, `:56`); "Tests" (`:78-86`) names the new suites. `docs/STATE-MACHINES.md`: a new entry, voice hold key, explicit, with the 13 variables it replaces. `docs/TILING-PLAN.md`: the key clash paragraph (`:458-489`, which names `handleShared`, `TalkKeyLatch.isEnding` and `otherKeyPressed`) becomes part 6. Comments that would go stale: `TileKeyMatcher.swift:50-53`, `TilingKeyTap.swift:61-64` and `:265-268` (the feed is a second witness; `barred` stops the smaller hold), `TileKeybind.swift:9-11`, `HotkeyMonitor.swift:62-65` and `:81-82`, `TileBaseConflicts.swift:16`. `docs/POINTING-ASSISTANT-PLAN.md:32` is a dated record and stays. `qa/regressions.json`: one row each for F1 to F5 and the swap chord; this plan names no REG id, because the tiling work has none of its own, REG-409 is taken and REG-410 is the notch plan's next id (`docs/NOTCH-SOURCES-PLAN.md:27`), so the ids come from the decade block the merge claims, not from here |

**Deleted.** From `HotkeyMonitor.swift`: the stored `gesture`, `sharedDown`, `holdTimer`, `commandLatched`, `isDown`,
`cancelledByLargerChord`, `latch`, `pendingStop`, `directPressActive`, `state` (`:97-109`); the functions
`otherKeyPressed`, `spoilHold`, `handleShared`, `evaluate`, `endedByLargerChord`, `finishEndedTurn`, `cancelHold`, `fire`
(`:161-322`); `cancelsWhenSpoiled` (`:93`) and its setter (`AppDelegate.swift:286-287`); the release fallback of a
cancel. From ZeusCore: `TalkKeyLatch` (`ZeusCommand.swift:271-352`) and `SharedKeyGesture.swift`. Thirteen variables in
three types become four values in one. Kept: `ShortcutState`, the feed, `PointingKeyGesture`, the monitor's callbacks.

| Risk | What it means |
| --- | --- |
| Eighteen behaviours change on purpose (C1 to C18), one of them pinned today (C4) | Only the Mac list below can say they feel right. C2 and C5 change dictation on its shipped key: a shortcut made with Right Command cancels the turn |
| C14 delays every talk and dictation start by 0.15 s while tiling runs | If that feels slow, or the owner's chords are slower than it, the number moves; at 0 the rule is off and the answer of part 6 is "on two orders in six" |
| The three ported suites change their bodies | The review must check each timeline and expectation against the old one |
| Only flags events say which modifiers are down | A chord some tool posts as a key-down with flags and no flags event no longer presses a keyed key (Control-Option-T). Not verified: whether any tool Zeus uses posts chords that way, and that no flags event carries the Fn flag without the Globe key down |
| Row 14 trusts the live modifiers | Not verified: that secure input hides flags events from the monitors, and that `NSEvent.modifierFlags` still tells the truth then |
| The search's size and time are estimates | Step 2 measures them; the fallback is in part 5 |
| Not changed here | The shared test compares the talk key the owner chose, not the one heard while VoiceOver runs (`HotkeyMonitor.swift:88`). Noted, not planned: for every key part 6 allows, a consumed chord holds a modifier foreign to the key before its key lands, so `barred` is set without the feed; the feed stays as a second witness with I5 tested, and deleting it is the owner's call after the Mac checks |
| F3 and F5 rest on the event tap contract | A new tap starts enabled; enabling a dead port does nothing. Not verified |

| # | Only a person at the Mac can check |
| --- | --- |
| 1 | Control, Option, Shift, Command, Left, fast and slow, twice in a row: nothing sent, hands-free never latched (F1). The same with dictation on Control-Option, and Right Command, Shift, Control, Option, Left: nothing inserted |
| 2 | Part 6, with Zeus speaking an answer: a tiling chord pressed as a chord interrupts nothing and plays no sound; pressed one key at a time it gives one listen sound and a dropped turn. Read the gaps between the owner's own chord keys from the log and set 0.15 s by them. Does talk feel late with tiling on? |
| 3 | Hold to talk, quick tap, double tap hands-free and the tap that ends it, on Control-Option and on Right Command, with tiling on and off. A tiling chord during a hands-free turn leaves it running |
| 4 | Dictation: hold and release; hold, Shift, release gives Return; hold, Shift, let Shift go, release gives no Return; the same twice in a row, quickly: no hands-free turn; on a dedicated key and on the shared key |
| 5 | Right Command with C, with V, with Tab, and with Left Command: dictation is cancelled and the shortcut works (C2). While a dictation is being rewritten, press the key and then a shortcut: the first text still arrives (C16) |
| 6 | Press to toggle dictation and the Polyglot key: one toggle per press, none on a tiling chord. Control-Option-T typed fast in the middle of a sentence still toggles (C11) |
| 7 | VoiceOver on: the talk key moves, Control-Option refuses once per press, tiling shows its note. Talk on Fn: the arrow keys start nothing (C15) |
| 8 | A dictation key recorded as the pair plus Shift: tiling shows the note, names that chord, installs no tap (F2) |
| 9 | Tiling switched on and off twenty times while typing in another app: no lost or late keystroke (F3 to F5). A real keyboard's rollover: no dead talk key after fast typing, and no turn opened by typing |
| 10 | Hold the talk key and click into a password field, let go: the turn ends within a moment. Close the lid while holding: nothing is sent on wake. Esc during hands-free dictation: the next press starts a new turn (C17, C18) |

## Review notes

### First pass

Revision of 14 November 2026, after an adversarial review of `133bb9b`. Each finding was checked against the code.

| # | Finding | Verdict | Change |
| --- | --- | --- | --- |
| 1 | Shift joining a dedicated dictation hold sent it, so the swap and nudge chords sent dictation | Confirmed (`DictationController.swift:1005`, `TileKeybind.swift:117-131`) | Rows 12 and 13 (Shift joins, Shift with the key let go); I1 excuses Shift only at a release; C4, the renamed test, Mac checks 1 and 4, two orders in the table tests |
| 2 | A cancel after a refused press drops a transcribing job | Confirmed (`DictationController.swift:539`, `:723-727`, `DictationFlow.swift:41`) | Both fixes taken: `onPress` returns a Bool and the key's cancel checks listening (4.4, C16, step 8) |
| 3 | A key-down rewrites the modifiers, so an arrow starts an Fn key | Confirmed in the source (`Shortcut.swift:335`, `:355-367`), not on hardware | `flagModifiers`, C15, run I; the test of E against `isHeld` is dropped. Kept against the finding's letter: Fn is not foreign for a keyed key, or a laptop F key could never be a talk key |
| 4 | `allUp` from `deviceKeys` clears after a reset with keys held | Confirmed (`PointingKeyGesture.swift:80`, `:91`) | Taken further than asked: the finding's own definition still clears on the next key event after a reset, as today's `:55` does, so `resync(to:)` replaces `reset()` (4.2, 4.5) |
| 5 | The answer understated what a start costs | Confirmed (`VoiceTurnController.swift:128-178`, `AppDelegate.swift:585-592`) | 1.3 and part 6 state it. Option one chosen: the confirm (C14, rows 4, 5, 21, step 12), for pointing too. Option two rejected in part 6 |
| 6 | The walk was not exhaustive, missed events, and its checker could not see latching | Confirmed; its cost figure could not be checked either way | A search of the reachable graph with a visited set; Left Command, Fn, config flips, `abandon`, `interrupt` and any lateness added; the checker reads `isLatched`; "acts" defined in I8; the other side of a sided key is foreign (C13) |
| 7 | A late forwarded key breaks I1 for the pair plus Fn | Confirmed (`TileKeybind.swift:89-94`) | Part 6 drops Fn from K, so that key is refused; I5 says for which keys it holds |
| 8 | The first config could count as a change | Confirmed as unstated | Prelude step 2; a table test |
| 9 | Two behaviour changes were not listed | Confirmed (`Shortcut.swift:359-363`) | C11, C12, Mac check 6 |
| 10 | Esc and a hidden release were left outside the reducer | Confirmed (`DictationController.swift:613-616`) | `turnEnded()` and `interrupt`, rows 14, 23 and 24 (C17, C18, step 8) |
| 11 | A tiling chord sends a latched turn in mid sentence | Confirmed (old rows 20 and 21) | Closed for tiling by the confirm (rows 21 and 8). The second option, ending on the clean release always, is rejected: it changes three pinned tests and adds the press time to every ending. The case that remains is named in part 6 |
| 12 | An enable outside the lock can land after a give-up or a teardown; a stop leaves the gate closed for a later start | Confirmed (`TilingKeyTap.swift:117-128`, `:242-258`) | Steps 15 and 16 |
| 13 | The docs list missed stale text | Confirmed (`docs/VOICE-KEY.md:50`, `:83`, and the comments named) | Steps 5, 11 and 17 |

Nothing was rejected outright. Three fixes were taken in another form than proposed (3, 4, 11), for the reasons above.

### Second pass

Revision of 14 November 2026 that finished the first one: every cited line was read again, then the rules, the table
and the clash rule were checked against each other. Findings of the first pass that were folded in only partly are
included.

| # | Finding | Verdict | Change |
| --- | --- | --- | --- |
| 14 | Cited lines that no longer say what the plan says: `Shortcut.swift:367` and `:358`, `VoiceKey.swift:74-80` (the file has 45 lines), `PolyglotSettings.swift:12`, `TileKeybind.swift:4-7` and `:117-129`, `TilingKeyLayer.swift:68`, `ZeusCLITests.swift:99-140`, `ShortcutTests.swift:171-230`, the "Tests" part of `docs/VOICE-KEY.md` said to hold `finishEndedTurn` | Confirmed by reading each | Corrected in place, one by one; the rest were read and stand |
| 15 | A dictation press that Shift joined could still latch: row 12 changed nothing, so Shift, Shift let go, a quick second tap gave `latched`, against I1 | Confirmed from rows 9, 12 and 15 | `holding` carries `shifted`; row 9 sends a shifted turn and never taps or latches it; I1 says so; C4, the renamed test gains a second case, a table test |
| 16 | Part 6 compared K with the bound sets only. A dictation hold key one Shift short of a bound set (Command, with Command-Shift-X bound) reads E, then S, before its key lands, so a late forwarded key could send it (I1, I5) | Confirmed; the default table never meets it | K plus Shift counts as equal for a dictation hold key; B is read without Fn; step 10 tests it |
| 17 | The reading of a config change counted `confirm`, so switching tiling on would cancel a hands-free turn | Confirmed from step 2 of 4.3 | A config differs by key, mode or `voiceOverHoldsKey` only |
| 18 | Rows 5, 6 and 21 named shared talk where only a hold key has a `confirm` | Confirmed | Rows narrowed to hold; row 20 keeps shared talk |
| 19 | A refused talk press left `WakeWordController.talkKeyHeld` set, because the closure that cleared it was a release or a cancel and an abandon calls neither (`AppDelegate.swift:282`, `:289`, `:589`) | Confirmed | `talkKeyPressed` clears it where it returns false, and the `listening` observer clears it (4.4) |
| 20 | The plan named no way to keep `qa/portable-core/prepare.py` in step with new Core files, and used REG ids the tiling work does not own (REG-409 is a meeting card row, REG-410 is the notch plan's) | Confirmed (`prepare.py:117`, `:123`; `qa/regressions.json`) | Part 7 intro and step 17: no id from this plan, the merge claims a block |
| 21 | The plain answer of part 6 said "with Command first" for both keys, but dictation on Right Command starts when Right Command stays down alone | Confirmed | Reworded: pressed as a chord or fast; the dictation case stated |
| 22 | The search could not hold three things the plan implied: the 95 s bound of pointing, a missed event, a state key for a type that is not `Equatable` | Confirmed | Stated in part 5; step 1 and step 4 add `Equatable` |
| 23 | An effect that makes an owner call `turnEnded()` re-entered `handle` | Plausible, not built | 4.4: effects run after `handle` returns |

Nothing from this pass was rejected. Two limits stay and are named, not hidden: the search has no missed-event move
(22), and the 0.15 s and the search size are estimates until step 2 and Mac check 2 run.

### Third pass

Revision of 14 November 2026 made while steps 1 to 3 were built (the flags-only picture, the failing tests, the reducer). The
search was run against the reducer and against deliberate mutations of it (Shift read as a Shift press for a talk key
too, `barred` never set, a cancel that leaves `barred` alone, no wake after a first tap, no send when a shared talk press
ends a command turn, no `shifted` mark): each was found, with the shortest order that shows it.

| # | Finding | Verdict | Change |
| --- | --- | --- | --- |
| 24 | A forwarded key that waits behind several later events breaks I2, I3 and I6 whatever the reducer does: Control, Option, Command, Left (consumed), Command, Option, Control, then Control, Option with the arrow still held. The machine is never told about the arrow, sees every modifier up, clears `barred`, and starts on Control-Option with the arrow down. A late key-up has the same effect on a key pressed again. Found by the search at three events, and at one for the key-up | Confirmed by the walk; the claim of I5 (late by any number of events) cannot hold | The search forwards a consumed key at once and lets one monitor event wait behind it (the forwarded key ahead of the flags event of the modifier pressed first, the order the unit test names); the rules read the keys the machine was told about (time passes while an event waits since finding 28). The late forwarded key stays a risk the Mac checks must watch (check 9, rollover) |
| 25 | A stale wake kept by the harness can cover a phase that forgot to ask for its own, and it multiplied the state space (3.4 million states for run A0 before, 6,648 after) | Confirmed | A wake belongs to the phase that asked for it; a phase change drops the old ones |
| 26 | A tick or a key event that arrives late was not stated: an armed press past its delay, or a tap past its gap, would be read as a quick tap | Confirmed by reading rows 5 and 17 | `settle`: an overdue delay or gap acts first, on the keyboard as it was before the event, so a late timer cannot change what a key did. Unit tests of row 15 and the late tick |
| 27 | `isLatched` must be true for the press that will end a hands-free turn (armed ending), or the checker would read its send as the send of an ordinary turn | Confirmed | `isLatched` is true for `latched` and for `armed(_, .ending)` |
| 28 | A tick checked only whether the live modifiers had lost the key's own modifiers. With the shipped defaults (talk Control-Option, confirm 0.15) the main thread blocks after Control, Option; Command lands at 0.08 s and its flags event is still queued when the wake runs. The tick read a superset of the pair, started the microphone, and Command cancelled it afterwards; on a hands-free turn the same order sent the turn, which cannot be undone. The walk missed it: time stood still while an event was held, and the rules judged by `seen`, not by the live modifiers a tick carries | Confirmed by the walk once both were changed (runs A to D, H and J found it at three moves) | A due tick adopts a foreign live modifier as the matching event (armed to idle, or latched for an ending press, with `barred`; holding through `cancelTurn`, or marked shifted for a dictation key with Shift alone), in the machine and in `PointingKeyGesture.confirmElapsed`. In the walk time passes while an event is held and a due tick of an armed press or a running hold counts its live modifiers as keys the machine was told about |

