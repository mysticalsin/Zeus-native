# Voice key machine: plan and design

Written 14 November 2026 on `codex/island-tiling-20261114` at `ae2ea60`. The spec, design note and task list for one
refactor: the hold keys of Zeus (talk, dictation, the Polyglot key, with the pointing key beside them) get one explicit
state machine, in the pattern of `docs/STATE-MACHINES.md` (a pure `State`, `Event`, `Effect` reducer in ZeusCore, a
controller that only runs effects). Nothing was built or run for this plan. Every claim about today's code was read in
the source and carries a file and line; what could not be checked that way says "not verified". Nothing here is accepted
until the named tests run on macOS and the behaviour is seen on a real Mac.

## Why

Six review rounds on this branch kept finding orders of key presses in which a tiling chord starts, sends or latches a
talk or dictation turn. Each round added a flag or a function to `HotkeyMonitor` (`cancelledByLargerChord`,
`endedByLargerChord`, `finishEndedTurn`, `cancelHold`, `TalkKeyLatch.isEnding`, the consumed key feed). The cause is no
one order: the life of a hold key is spread over 13 variables in three types that must change together, so each new
rule has to be proved again by hand against every combination. The patching stops; the machine is made explicit.

| # | Open finding | Closed by |
| --- | --- | --- |
| F1 | Shift joining a talk hold is read as a release: Control, Option, Shift, Command, Left sends the turn 0.4 s later, and two quick swaps can latch hands-free (`HotkeyMonitor.swift:277-280`, `:170`) | I1, I2, table rows 11 and 16 |
| F2 | The clash rule compares modifier-only keys with the pair only, not the pair plus Shift (`TileBaseConflicts.swift:67`, `:80-81`) | Part 6 |
| F3 | The tap is created enabled before its thread services it (`TilingKeyTap.swift:25-26`, `:147-150`) | Step 11 |
| F4 | `stop()` leaves the gate open until the teardown runs (`TilingKeyTap.swift:174-180`) | Step 12 |
| F5 | `start()` calls the window server while holding the callback's lock (`TilingKeyTap.swift:118-123`) | Step 13 |

## 1. Today

### 1.1 State variables (27)

`HotkeyMonitor` has three instances: talk (`AppDelegate.swift:30`), dictation (`DictationController.swift:272`), Polyglot
(`PolyglotController.swift:59`). Each holds 1 to 13. Pointing holds 14 to 27.

| # | Variable | Where | Meaning |
| --- | --- | --- | --- |
| 1 | `state.modifiers` | `Shortcut.swift:289` | Modifiers down as the last event said. A key-down overwrites it (`:335`), so it can be stale until the next flags event |
| 2 | `state.deviceKeys` | `Shortcut.swift:290` | Physical modifier keys down, from flags events only (`:318-329`) |
| 3 | `state.keysDown` | `Shortcut.swift:291` | Ordinary keys down |
| 4 | `state.spoiled` | `Shortcut.swift:293` | An ordinary key joined while a modifier key was down (`:348`); cleared when a flags event shows none (`:330`) |
| 5 | `isDown` | `HotkeyMonitor.swift:102` | Dedicated key: a press is counted as down |
| 6 | `cancelledByLargerChord` | `:104` | Dedicated key: no press until the modifiers are empty (`:236`) |
| 7 | `latch` | `:105` | `TalkKeyLatch`: idle, holding(down, second), tapped(up), latched, ending (`ZeusCommand.swift:282-288`) |
| 8 | `pendingStop` | `:106` | The timer that sends a quick tap after 0.4 s |
| 9 | `directPressActive` | `:107` | The toggle mode last seen; a flip resets 5, 7 and 8 with no callback (`:225-231`) |
| 10 | `sharedDown` | `:98` | Shared key: counted as down |
| 11 | `gesture` | `:97` | `SharedKeyGesture`: idle, down(at, second, holding, spoiled), tapped(up) (`SharedKeyGesture.swift:10-14`) |
| 12 | `holdTimer` | `:99` | The 0.25 s hold delay timer |
| 13 | `commandLatched` | `:100` | Shared key, talk side: a hands-free command turn is open |
| 14 to 17 | a second `ShortcutState` | `PointingKeyGesture.swift:32` | As 1 to 4 |
| 18 to 21 | `isActive`, `blockedByVoiceOver`, `waitForRelease`, `activeSince` | `PointingKeyGesture.swift:29-34` | A hold is running; VoiceOver owns the chord; nothing begins until everything is up; when the hold began |
| 22 to 24 | `controlDownAt`, `controlTapClean`, `lastControlTap` | `:35-37` | The double Control tap |
| 25 to 27 | `turnOpen`, `announcedBlock`, `watchdog` | `PointingHotkeyMonitor.swift:50-53` | An end is owed; the VoiceOver notice was shown; the 0.25 s stuck key timer |

Wiring, not counted: the monitor and observer handles (`HotkeyMonitor.swift:95-96`, `PointingHotkeyMonitor.swift:49`,
`:54-55`). State outside the monitors that the key logic leans on: `WakeWordController.talkKeyHeld`
(`AppDelegate.swift:282`, `:289`), `topBar.isDictating` (`DictationController.swift:393`), `run.isActive`
(`PolyglotController.swift:120`).

### 1.2 Sources of events

- Local monitor (Zeus's own windows, `HotkeyMonitor.swift:126-130`) and global monitor (other apps, once Accessibility
  or Input Monitoring is on, `:125`, `:134-139`): flags, key-down, key-up. Both pass through `convert` (`:141-149`): a
  flags event carries the whole modifier set, a repeat is dropped (`:145`).
- Consumed key feed: the tiling tap turns a key it consumed into the event a monitor would have seen
  (`TileKeyMatcher.swift:54-60`) and posts it on the main queue (`TilingKeyTap.swift:270-273`); each monitor feeds it to
  itself (`HotkeyMonitor.swift:114-121`). Nothing orders it against the monitors' own events (`TilingKeyTap.swift:265-268`).
- Timers: the hold delay (`HotkeyMonitor.swift:199-206`) and the send after a tap (`:306-316`), stored work items.
  Settings (key, shared test, toggle test, VoiceOver) are read in `evaluate` (`:219-241`): a change shows only at the
  next key event.
- Pointing: its own event tap (`PointingHotkeyMonitor.swift:112-117`), the same feed (`:59-66`), the watchdog
  (`:98-110`), sleep, wake and display changes (`PointingController.swift:278`), and `stop()` (`:81-88`).

### 1.3 Transitions as the code behaves

`evaluate` picks a path at every event (`HotkeyMonitor.swift:223-235`): shared when the talk key the owner chose equals
the dictation key (`:88`); toggle for a dictation role with the toggle setting on its own key (`:224`); else the latch.

**Dedicated key, hold** (talk; dictation with "Hold to speak").
- Pressed means held exactly and not `cancelledByLargerChord` (`:237`). Exactly: the modifiers are equal, no ordinary
  key is down, the chord is not spoiled, and the side matches (`Shortcut.swift:355-367`).
- Press edge (`:251-258`): the latch starts a turn from idle, continues a tapped one (a second tap when within 0.4 s),
  or ends a latched one at once and becomes `ending` (`ZeusCommand.swift:301-315`).
- Release edge (`:259-270`): when Control, Option or Command joined (`:277-280`) the turn is cancelled, or only blocked
  when the latch is `ending` (`:285-299`). Otherwise the latch takes a key-up (`ZeusCommand.swift:317-337`): a first
  press of up to 0.3 s waits 0.4 s and sends; a second quick one latches hands-free; a longer one sends.
- Shift or Fn joining is also a release edge: the exact hold fails and `:279` does not count them. For dictation that
  is the documented Shift means Return (`docs/VOICE-KEY.md:47`; the Return is read from the live flags at delivery,
  `DictationController.swift:977`, `:1005`). For talk it is F1: the send timer runs with `isDown` false, `spoilHold`
  guards on `isDown` (`:170`), so nothing cancels it. Shift let go again is a second press: a quick swap can latch.
- Another key down (`:154-157`): the talk monitor cancels (`:169-177`, `cancelsWhenSpoiled` from
  `AppDelegate.swift:287`). The dictation monitor does not (`:170`): the release edge sends the turn or counts a tap.
- A larger set shrinking to the key's set (Command, Control, Option, then Command up) starts a turn (`:237`).
- VoiceOver on and the key Control-Option: `onBlocked` and nothing else, on every event while held (`:252-255`). The
  talk key itself moves to a fallback meanwhile (`VoiceKey.swift:23-27`, `HotkeyMonitor.swift:74-80`), same paths.

**Shared key** (`handleShared`, `:185-216`).
- A press is armed only on an exact hold (`:187`). Before the hold begins, an extra modifier other than Fn spoils the
  press (`:188-189`), and so does another key (`:161-165`).
- Dictation role: after 0.25 s unspoiled the turn starts (`:199-206`, `SharedKeyGesture.swift:41-45`); the key-up sends
  it (`:211`). A running hold tolerates every extra modifier (`:187` stops asking for exact), which is how Shift means
  Return here; only another key cancels it (`SharedKeyGesture.swift:48-55`).
- Talk role: two taps of up to 0.25 s, at most 0.35 s apart (`SharedKeyGesture.swift:16-18`, `:57-65`), start a
  hands-free command turn (`:212`). The next key-down sends it and is itself a first tap (`:192-197`).
- No VoiceOver check: the check sits after the `return` at `:234`.

**Toggle** (dictation "Press to start and stop" on its own key; Polyglot always, `PolyglotController.swift:110-115`).
The press edge calls `onPress`, the release edge nothing (`:238-250`). The owner decides start or finish from its own
state (`DictationBehavior.swift:24-29`, `PolyglotController.swift:120`). A foreign modifier tapped during one physical
hold makes a second press edge and toggles again. Polyglot's default key, Control-Option-T (`PolyglotSettings.swift:13`),
is keyed: held when the modifiers are equal and T is down; other keys and `spoiled` are ignored (`Shortcut.swift:359-363`).

**Settings change.** The key becomes nil while `isDown`: the turn is sent (`:219-222`). The toggle setting flips: the
latch and `isDown` reset with no callback, and an open turn runs on with no owner in the monitor (`:225-231`).

**Esc.** `TalkKeyLatch.cancelFromEsc` (`ZeusCommand.swift:347-351`) has no caller in `Sources/Zeus`. Dictation's own Esc
monitor cancels the turn (`DictationController.swift:613-616`) without telling the key monitor, so a latched monitor
stays latched and the next press is spent ending a turn that is gone.

**Pointing** (`PointingKeyGesture.feed`, `:41-68`). A hold begins on an exact hold when not waiting (`:58-64`), unless
VoiceOver owns Control-Option (`:59-60`). When no longer exact it ends if what is left is inside the key's set,
unspoiled, with no key down (`:49-50`); otherwise it is cancelled and waits for everything to be up (`:51-55`). Also
the watchdog and the 95 s bound (`:75-84`), the interrupt (`:88-94`), Esc and the double Control tap (`:66`, `:96-118`).
The monitor adds one-turn bookkeeping (`PointingHotkeyMonitor.swift:120-144`) and starts no turn when the pointing key
is the talk key (`VoiceKey.swift:31-33`). Like the dedicated path it starts on a shrink.

## 2. What must not change

| Behaviour | Pinned by |
| --- | --- |
| A hold starts at once and the release sends | `TalkKeyLatchTests.holdToTalk`, `ShortcutTests.holdToTalkStartsAndStops`, `TilingConsumedKeyTests.aPlainHoldAndReleaseStillSendsTheTurn` |
| A quick tap sends after the gap; tap then hold is a hold | `singleTapStopsAfterTheGap`, `aSingleTapStopsAfterTheGap`, `tapThenHoldIsANormalHold` |
| A double tap latches until the next tap | `doubleTapLatchesUntilTheNextTap` (both suites) |
| The press that ends a hands-free turn sends once, cancels nothing, starts nothing | `theTapThatEndsALatchedTurnIsEndingUntilItsKeyUp`, `aModifierJoiningThePressThatEndedAHandsFreeTurnDoesNotCancelIt`, `theKeyThatEndedAHandsFreeTurnDoesNotStartANewOneWhenTheExtraModifierIsLetGo` |
| The owner ends a turn itself | `escapeCancelsHoldOrLatch` |
| Shared key: hold dictates, double tap talks, a shortcut is ignored or cancels | `SharedKeyGestureTests` (5), `aSharedHoldOfExactlyItsOwnKeyStillStartsDictationAndExtraModifiersDoNotEndIt`, `aSharedHoldOfAPairInsideTheTilingPairDoesNotStartDictationWhenCommandComesFirst`, `aSharedHoldInTheSameOrderStartsNothingWhenTheRestOfThePairArrivesInTime` |
| A larger chord cancels, never sends | `aTalkTurnThatTheRestOfTheTilingPairEndsIsCancelledNotSent`, `aSlowPressOfTheSameOrderIsCancelledToo`, `aDedicatedDictationHoldThatTheRestOfThePairEndsIsCancelledNotInserted`, `aSingleModifierHoldThatAnotherModifierEndsIsCancelledToo`, `aModifierJoiningTheSecondTapOfADoubleTapStillCancelsTheOpenTurn` |
| Nothing restarts until every modifier is up | `aCancelledHoldDoesNotRestartWhenTheExtraModifierIsLetGo`, `aTalkHoldDoesNotStartWhenCommandIsReleasedFirstAfterAConsumedChord`, `aDictationKeyOnRightCommandDoesNotStartWhenTheOthersAreReleasedFirst`, `aModifierChangeHeardBeforeTheForwardedKeyOnlyCostsACancelledTurn` |
| Shift on a dedicated dictation hold sends | `shiftJoiningAHoldStillEndsItTheNormalWay` |
| The keyboard picture | `ShortcutTests`: `optionCommandChord`, `aKeyPressedDuringTheChordSpoilsIt`, `rightCommandIsNotLeftCommand`, `repeatedFlagsChangedWhileHeldDoesNotReadAsARelease`, `anUnrelatedCommandShortcutElsewhereDoesNotSpoilALaterBareModifierHold`, `fnAloneAndKeyedShortcuts` |
| The feed carries one event and nothing else | `theNotificationCarriesTheEventAndNothingElse`, `withTheForwardedKeyTheTalkHoldStaysSpoiledUntilEveryModifierIsUpThenWorksAgain` |
| Pointing | `PointingKeyGestureTests` (9), the stuck key, sleep and wake suite beside it (10), `PointingHotkeyMonitorTests` (6), `thePointingHoldStaysSpoiledToo`, `aPointingHoldDoesNotBeginWhenCommandIsReleasedFirstAfterAConsumedChord`, `aPointingHoldThatTheRestOfTheTilingPairEndsIsCancelledNotEnded` |
| One owner per hold; the VoiceOver fallback | `VoiceKeyTests.everyHoldHasAtMostOneOwner`, `voiceOverKeepsControlOptionAndTalkMovesToAFallback` |
| Every key monitor is read by the clash check | `TilingKeyClashTests.everyKeyMonitorInTheAppIsAccountedForByTheLiveKeys` |

**No test pins these today.** The toggle path through the monitor (Polyglot, press to toggle). The VoiceOver refusal in
the monitor. The talk side of the shared key through the monitor (`commandLatched`). A settings change mid turn. A key
joining a dedicated dictation hold. Fn joining a hold. A keyed hold key (Option-Space) meeting a foreign modifier. The
shrink start. Esc while latched. The real timers, except through sleeps in `TilingConsumedKeyTests`.

**Changed on purpose.** Each row is a behaviour no test pins, changed because a rule in part 3 demands it.

| # | Today | After |
| --- | --- | --- |
| C1 | Shift or Fn joining a talk hold is a release: sent, or a tap that can latch (F1) | Cancelled |
| C2 | A key joining a dedicated dictation hold is a release | Cancelled |
| C3 | Command, Control, Option or Fn joining a running shared dictation hold is tolerated until a key lands | Cancelled |
| C4 | Shift joining a dedicated dictation hold is the latch's key-up: a quick one waits 0.4 s and can latch | Sent at once; the key does nothing more until every modifier is up |
| C5 | A tap waiting out its 0.4 s, then a foreign key or modifier: sent | Cancelled |
| C6 | A larger set that shrinks to the key's set starts a turn, and re-fires a toggle (talk, dictation, Polyglot, pointing) | Nothing until every modifier is up |
| C7 | Settings change mid turn: a nil key sends, a mode flip leaves the turn open | Cancelled |
| C8 | VoiceOver refusal repeats on every event and is skipped on the shared key | Once per press, in every mode |
| C9 | A keyed hold key that a foreign modifier or key joins is a release | Cancelled |
| C10 | A cancel with no `onCancel` falls back to `onRelease`, which sends (`HotkeyMonitor.swift:176`, `:298`) | A cancel never calls `onRelease` |

## 3. Safety rules

Words. The key's **own set** is its modifiers, with its side, and its key code when it has one. **Foreign** is a
modifier outside the own set, or an ordinary key that is not the key's own. A **press** lasts while the whole own set is
down. A **turn** runs from `start` to `send` or `cancel`. A step is one key going down or up, or time passing. The rules
hold after every step of every order, and the walk in part 5 checks them against the keys physically down, not against
the machine's own picture.

- **I1. A foreign press never sends and never latches.** For every `send`, nothing foreign was down at any step between
  the turn's `start` and the `send`, except while the turn was latched hands-free, and except Shift on a dictation key
  (Shift means Return). A turn becomes latched only if nothing foreign was down since its `start`. The press that ends
  a hands-free turn sends at the step where exactly the own set came down.
- **I2. After a cancel, nothing starts until everything is up.** No `start` after a `cancel` until every key is up.
- **I3. Nothing starts on a larger chord.** No `start` at a step where the keys down are a strict superset of the own set.
- **I4. Every turn ends exactly once.** `start` is followed by exactly one `send` or `cancel` before the next `start`;
  no `send` or `cancel` without an open turn. With every key up and every timer run out, only a latched turn is open.
- **I5. A consumed key is a key.** The machine's event has no field that says where a key came from, so a consumed key
  and the same key unconsumed give the same effects. Arriving late (after the next modifier event), every other rule still holds.
- **I6. Nothing starts when a larger chord shrinks.** Once the whole own set has been down with something foreign, no
  `start` until every key is up. This closes the gap `TilingKeyTap.swift:265-268` calls bounded, whatever the feed's order.
- **I7. A toggle fires once per press.** At most one `start` per press of a toggle key, and none while I2 or I6 bar it.
  A toggle cannot be taken back, so I1 and I4 do not apply to it; part 6 refuses the pairs that would need them.
- **I8. Never stuck.** From every state, letting go of everything, waiting, then pressing exactly the own set acts.

## 4. The target

### 4.1 One reducer

`Sources/ZeusCore/VoiceKeyMachine.swift`, about 170 lines, `Sendable` and `Equatable`, no clock, no timer, no callback.

```swift
public struct VoiceKeyMachine: Sendable, Equatable {
    public enum Role: Sendable { case talk, dictation }
    public enum Mode: Sendable { case hold, shared, toggle }
    /// Read by the adapter at every event. `key` nil is off; `voiceOverHoldsKey`: VoiceOver is on and the key is Control-Option.
    public struct Config: Sendable, Equatable { var key: Shortcut?; var role: Role; var mode: Mode; var voiceOverHoldsKey: Bool }
    public enum Event: Sendable, Equatable {
        case key(ShortcutEvent, at: TimeInterval)    // from a monitor or from the consumed key feed: no way to tell
        case tick(at: TimeInterval)                  // a wake the machine asked for
        case abandon                                 // the owner ended the turn itself
    }
    public enum Effect: Sendable, Equatable { case start, send, cancel, refused, wake(after: TimeInterval) }
    public enum Phase: Sendable, Equatable {
        case idle                                        // nothing open, no press counted
        case armed(since: TimeInterval, second: Bool)    // shared key: the press is down, nothing started yet
        case holding(since: TimeInterval, second: Bool)  // a turn is open and the key is down
        case tapped(at: TimeInterval, open: Bool)        // the key is up after a quick tap; open: its turn waits for the gap
        case latched                                     // hands-free: a turn is open and the key is up
        case spent                                       // the key is down and this press has done all it will do
    }
    public mutating func handle(_ event: Event, config: Config) -> [Effect]
}
```

The whole state is four values: `config` (the last one seen), `keys` (a `ShortcutState`, unchanged, the picture of the
keyboard), `barred` (nothing may begin until everything is up) and `phase`. `mode` is the choice made today at
`HotkeyMonitor.swift:223-224`. Times are fixed per mode and keep today's values: hold 0.3 s tap and 0.4 s gap
(`ZeusCommand.swift:290-291`); shared 0.25 s hold delay, 0.25 s tap, 0.35 s gap (`SharedKeyGesture.swift:16-18`); a due
check allows 1 ms (`SharedKeyGesture.swift:42`). A `wake` asks for a `tick` later; the machine decides from the tick's
time and its own phase, so a late or stale tick does nothing and nothing ever needs cancelling.

### 4.2 Key facts

`Sources/ZeusCore/KeyFacts.swift`, a pure function of a `ShortcutState` and a `Shortcut`, used by the machine and by
`PointingKeyGesture`, so both mean the same thing by every word below.

| Fact | Meaning |
| --- | --- |
| `ownDown` | Every modifier of the key is down, its side key if it has a side, its key code if it has one |
| `foreignModifier` | A modifier outside the key's set is down (Fn is ignored for a keyed key that does not ask for it, as `Shortcut.swift:359`) |
| `foreignKey` | Modifier-only key: an ordinary key is down, or `spoiled`. Keyed key: an ordinary key other than its own is down |
| `allUp` | No modifier key is physically down (`deviceKeys` is empty) and no ordinary key is down. Not `modifiers.isEmpty`: a key-down can leave `modifiers` stale (`Shortcut.swift:335`) |

One **reading** per event, from the facts and the role:
- **E**, exact: `ownDown` and nothing foreign. For a modifier-only key this equals `isHeld(key, exact: true)`.
- **R**, let go: not `ownDown` and nothing foreign.
- **S**, Shift only, dictation role only: Shift is the one foreign thing down. For a talk key Shift is plain foreign.
- **F**, foreign: anything else.

### 4.3 The transition table

Before the row, in this order: (1) apply a key event to `keys` and take the facts; (2) if `config` differs from the
stored one, emit `cancel` when a turn is open (holding, tapped open, latched), go to idle, store it, and set `barred`
unless `allUp` (a nil key stops here); (3) `barred` becomes false when `allUp`, else true when `ownDown` with anything
foreign; (4) the row. **Begin** means reading E and not `barred`. Every `cancel` also sets `barred` unless `allUp`.

| # | Phase | Input | Mode | Next phase | Effects |
| --- | --- | --- | --- | --- | --- |
| 1 | idle | begin, `voiceOverHoldsKey` | any | spent | `refused` |
| 2 | idle | begin | hold | holding(t, first) | `start` |
| 3 | idle | begin | shared | armed(t, first) | dictation: `wake(0.25)`; talk: none |
| 4 | idle | begin | toggle | spent | `start` |
| 5 | armed(since, second) | R | shared, talk | up to 0.25 s and second: latched. Up to 0.25 s and first: tapped(t, not open). Longer: idle | `start` when latched |
| 6 | armed | R | shared, dictation | idle | none |
| 7 | armed | F or S | shared | idle | none |
| 8 | armed(since, second) | tick, 0.25 s since | shared, dictation | holding(since, second) | `start` |
| 9 | holding(since, second) | R | hold | up to 0.3 s and second: latched. Up to 0.3 s and first: tapped(t, open). Longer: idle | tapped: `wake(0.4)`. Longer: `send` |
| 10 | holding | R | shared | idle | `send` |
| 11 | holding | F | any | idle | `cancel` |
| 12 | holding | S with the key still down | hold | idle | `send` |
| 13 | holding | S with the key still down | shared | holding | none |
| 14 | holding | S with the key let go | any | idle | `send` |
| 15 | tapped(at, open) | begin | hold | holding(t, second when within 0.4 s of at) | none |
| 16 | tapped(at, open) | F or S | any | idle | `cancel` |
| 17 | tapped(at, open) | tick, 0.4 s since at | any | idle | `send` |
| 18 | tapped(at, not open) | begin | shared, talk | armed(t, second when within 0.35 s of at) | none |
| 19 | tapped(at, not open) | F or S | any | idle | none |
| 20 | latched | begin | hold | spent | `send` |
| 21 | latched | begin | shared, talk | armed(t, first) | `send` |
| 22 | spent | R, F or S | any | idle | none |
| 23 | any | `abandon` | any | idle, `barred` unless `allUp` | none |
| 24 | any | anything else | any | unchanged | none |

How the rules follow. I3: only a begin starts, and a begin needs reading E. I2 and I6: `barred` is set by every cancel
and by step 3, cleared only at `allUp`, and a begin needs it false. I1: rows 11 and 16 are the only exits from an open,
unlatched turn when something foreign shows, and both cancel; rows 12 to 14 are the Shift exception. I4: a turn is open
only in holding, tapped open and latched; `start` appears only on entering them (rows 2, 5, 8; row 4 is a toggle's
press and opens no turn here), and every move from them to another phase carries exactly one `send` or `cancel` (rows
9 to 12, 14, 16, 17, 20, 21, step 2), except `abandon`, where the owner has already ended the turn. I5: `Event.key` is
the only way in. I7: rows 1 and 4 go to spent, which no begin leaves. I8: every phase reaches idle at `allUp` or keeps
a turn that the next begin ends. F1 on the table: Control, Option is row 2 (`start`). Shift is reading F for a talk
key: row 11, `cancel`, `barred`. Command, Left, and Shift let go again change nothing until everything is up.

### 4.4 The adapter

`HotkeyMonitor` keeps its callbacks and providers (`HotkeyMonitor.swift:68-90`), so its three owners do not change, and
keeps the monitors, `convert` and the feed observer (`:114-149`). Everything else goes. What is left is one stored
`machine`, an injectable `now`, and two entries: `feed(_:)` runs `machine.handle(.key(event, at: now()), config:)` and
`tick()` runs `.tick(at: now())`. `config()` reads the providers into a `Config`. The effects map `start` to `onPress`,
`send` to `onRelease`, `cancel` to `onCancel`, `refused` to `onBlocked` with today's sentence (`:241`), and
`wake(after:)` to one `asyncAfter` that calls `tick()`. It stores no timer and no flag: the only stored value that
changes after `start()` is `machine`. Both monitors and the feed call the same `feed`, which is I5 at the adapter.

### 4.5 Pointing keeps its own reducer

`PointingKeyGesture` does not join. It is already a pure reducer with three suites (`docs/STATE-MACHINES.md:170`). It
carries four things the voice keys have no use for (Esc, the double Control tap, the watchdog with live modifiers, the
interrupt) and none of theirs (tap, latch, hold delay, toggle, Shift): one reducer for both would be two tables behind
a mode switch. What must be the same is the rule. So pointing reads the same `KeyFacts`, runs under the same walk and
invariants, and takes two small changes: `waitForRelease` is also set when the whole own set is down with something
foreign while no hold is active (I6), and it is cleared on `KeyFacts.allUp` in place of `PointingKeyGesture.swift:55`.

## 5. Tests first

**The table.** `Tests/ZeusCoreTests/VoiceKeyMachineTests.swift`: one test per row of 4.3, the prelude steps, F1's order,
and each row of the "changed on purpose" list. `Tests/ZeusCoreTests/KeyFactsTests.swift`: every fact for a modifier-only
key, a sided key and a keyed key, the stale modifier case, and `E == isHeld(exact: true)` over every modifier set.

**The walk.** `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift`, pure, no sleep. Five physical keys: Control, Option, Right
Command, Shift and one ordinary key (Left arrow; T for Polyglot). Seven moves at every step: toggle one of the five keys
(a press if it is up, a release if it is down, so every order is valid), wait 0.2 s (inside every window), or wait 0.5 s
(past every window). The harness is the stand-in adapter: it keeps the wakes and delivers each due `tick` in order as
time passes. A key-down is offered to the real `TileKeyMatcher` with `TileKeymap.defaults(base: .standard)`; a consumed
key reaches the machine as `TileKeyDecision.monitorEvent`, which the harness asserts equals what a monitor would have seen.

Eight runs, one per role, mode and key: **A** talk, hold, Control-Option (shipped talk). **B** dictation, hold, Right
Command (shipped dictation). **C** dictation, hold, Control-Option. **D** dictation, shared, Control-Option. **E** talk,
shared, Control-Option. **F** dictation, toggle, Right Command. **G** toggle, Control-Option-T (shipped Polyglot).
**H** `PointingKeyGesture`, Control-Option (shipped pointing): began is `start`, ended and timed out are `send`.

Each run is walked twice: consumed keys delivered in order, and late (after the next key event, or before a wait). From
rest, every order up to 6 steps: 7 + 49 + 343 + 2,401 + 16,807 + 117,649 = 137,256 sequences per walk, 16 walks,
2,196,096 sequences. From a latched hands-free turn (runs A, B, C, E), every order up to 5 steps: 19,607 sequences per
walk, 8 walks, 156,856 sequences. Total 2,352,952. After every step a small checker, which sees only the effects and the
keys physically down, asserts I1 to I7; at the end of every sequence it lets go of everything, waits, and asserts I4's
last clause and I8. The walk is a depth-first search that copies the machine value at each step, so a step costs one
reducer call; each run is one case of a parameterised test, and the cases run in parallel. Budget: under 1 s a run and
under 5 s for the suite in a debug build. Not measured: nothing was built for this plan. Step 2 records the time here;
if it is over, the search skips a state already expanded with as many steps left (times compared as ages), and a depth
4 run without the skip must reach the same states.

**The existing suites stay.** `TalkKeyLatchTests`, `SharedKeyGestureTests` and the rig in `ShortcutTests.swift:171-230`
keep their names, their timelines and their expectations, and drive the machine in place of the two deleted types
(`stopLater(0.4)` reads `wake(after: 0.4)`, `cancelPendingStop` reads no effect, `isLatched` reads `phase == .latched`,
`isEnding` reads `phase == .spent`, `cancelFromEsc` reads `abandon`). `TilingConsumedKeyTests` loses one line, the
`cancelsWhenSpoiled` setter at `:134`.

**The monitor.** `Tests/ZeusAppTests/HotkeyMonitorMachineTests.swift`: F1's order through the real monitor sends nothing
and latches nothing; a key joining a dictation hold cancels; a cancel never calls `onRelease`; a toggle fires once per
press; the VoiceOver refusal comes once; a consumed key and the same key fed directly give the same callbacks.

## 6. The tiling clash rule

Once the machine holds I1 to I7, the rule needs no knowledge of how a monitor cancels. Let **B** be the modifier sets of
the chords the keymap really binds (`TileKeymap.bindings`, `TileKeybind.swift:56`): for the default table, the pair and
the pair plus Shift (`TileKeybind.swift:117-129`). For each modifier-only Zeus key with modifiers **K** (talk as the
monitor hears it, pointing, dictation, Polyglot; `TileBaseConflicts.swift:59-62`):

| K against B | Hold key | Key that switches on at the press (press to toggle dictation, modifier-only Polyglot) |
| --- | --- | --- |
| K equals a set in B | Refused | Refused |
| K is strictly inside a set in B | Free | Refused |
| K is inside no set in B | Free | Free |

In one sentence: a modifier-only key is refused when its modifiers equal those of a bound chord, and a key that switches
on at the press is refused when its modifiers are inside those of a bound chord. It is total: every key lands in one
cell. `TileBaseConflicts.notes` keeps its signature and takes B from the keymap it is already given.

Each case still refused, and why:
1. **Equal** (today only against the pair, `:67`; F2). Every chord of that set has exactly the key's modifiers down
   before its key lands, so the turn starts on every such chord in every press order. The machine would cancel it (I5),
   but the microphone would open each time. A dictation key recorded as the pair plus Shift (the recorder takes any
   modifier peak, `Shortcut.swift:395-403`) is now refused with a note that names the key.
2. **A toggle inside** (today only against the pair, `:80-81`; F2). The smaller set down first fires the toggle, and I7
   says it cannot be taken back. Now also caught against the pair plus Shift, for example a key that holds Shift.
3. **A keyed Zeus shortcut the keymap binds** (`:88-100`, unchanged): the tap would swallow it.
4. **VoiceOver on and a bound chord holds Control and Option** (`:55-57`, unchanged).

A hold key strictly inside a bound set stays free: by I1, I2 and I6 such a chord can never send or latch a turn, in any
order, with the feed early or late. That is the shipped case, so **the shipped pair stays Control-Option-Command**
(`TileKeybind.swift:12`): shipped talk and pointing are Control-Option and shipped dictation is Right Command in hold
mode, hold keys strictly inside; shipped Polyglot is keyed and its chord is not bound.
`theShippedDefaultsClashWithNothing` and `theShippedDefaultPairClashesWithNoShippedDefaultKey` stay as they are.

**Can the microphone open, even briefly, on a tiling chord with shipped defaults? Yes.** A hold key starts the moment
exactly its own set is down (row 2). When the owner's fingers land Control and Option before Command, the talk turn
starts at the second of them and is cancelled when Command lands (row 11). The same holds for Right Command landing
before Control or Option, for dictation. What the owner sees and hears in that moment: any answer Zeus was speaking
stops, the listen sound plays, other audio dips, the companion shows listening and the microphone light comes on
(`VoiceTurnController.swift:128-175`); then the turn is dropped with no sound (`:205-223`). Dictation shows "Dictation
cancelled" (`DictationController.swift:723-727`). Nothing is sent, nothing is inserted, nothing is latched, and nothing
starts again until every key is up. With Command down first, nothing opens at all (I3, I6), and talk and pointing keys
inside no bound set, such as Fn (`Shortcut.swift:47`), never open on a tiling chord. `docs/VOICE-KEY.md` will say so.

No simple rule takes that moment away, and none is planned:
- Refusing every pair that contains a hold key is simple and total, but it refuses all three pairs
  (`TileKeybind.swift:4-7`) against the shipped keys: Control-Option equals talk, the other two contain Right Command.
- Another shipped pair moves the moment and does not remove it: Option-Command still contains Right Command, and it is
  where talk moves while VoiceOver runs (`VoiceKey.swift:19`). Not verified from the code: how many app shortcuts
  Option-Command plus an arrow or a letter would take.
- A start delay on the hold key shortens the window and never closes it (a slow chord still opens), delays every talk
  turn, and changes what a quick tap means. The machine could take it later as one more use of `armed`.

## 7. Steps

Small commits that each build. A step named "failing tests" builds and its new tests are red until the next step.

| # | Commit | What |
| --- | --- | --- |
| 1 | Add the key facts both key reducers read | `KeyFacts.swift`, `KeyFactsTests.swift`. Green |
| 2 | Add failing tests for the voice key machine and the walk over every press order | `VoiceKeyMachine.swift` with the types of 4.1 and a `handle` that only applies keys; `VoiceKeyMachineTests`, `VoiceKeyWalkTests`. Red. Record the walk's time |
| 3 | Fill the voice key machine from its transition table | Rows 1 to 24. Walk green for runs A to G |
| 4 | Hold the pointing gesture to the same start rule | The two changes of 4.5. Walk green for run H; the three pointing suites unchanged |
| 5 | Drive the latch and shared gesture suites through the machine | The ports of part 5. Green; the two old types have no test left |
| 6 | Add failing monitor tests for the press orders the reviews found | `HotkeyMonitorMachineTests`. Red |
| 7 | Make HotkeyMonitor an adapter over the voice key machine | 4.4. Deletes the flags and functions below. Green |
| 8 | Delete TalkKeyLatch and SharedKeyGesture | No caller is left |
| 9 | Add failing tests for a key on the modifiers of any bound tiling chord | `TileBaseConflictsTests`: equal to the pair plus Shift (hold and toggle), a toggle inside the pair plus Shift only, a hold inside it free, the copy has no dashes |
| 10 | Compare modifier-only keys with every modifier set the tiling keymap binds | Part 6 in `TileBaseConflicts.notes`; rewrite its header comment (`:3-30`) |
| 11 | Create the tiling tap disabled until its thread installs it | `create()` disables the port right after `system.create` (`TilingKeyTap.swift:133-139`); install enables it after adding the source (`:149-150`); fix the comment at `:154`. Stand-in test: the first switch is off on the owner's thread, the next is on, on the tap thread |
| 12 | Close the tiling gate under the lock when the tap stops | `stop()` sets `snapshot.gate.enabled = false` in its locked region (`:175-180`). The layer builds a new tap and calls `update` before every start (`TilingKeyLayer.swift:110-114`), so nothing reopens a stopped one. Stand-in test with the teardown held open, through an internal entry that decides one `TileKeyEvent` (the part of `handleKey` at `:226-230`): a bound chord decided after `stop()` took the lock passes through |
| 13 | Switch the tiling tap on outside its lock | `start()` records the port under the lock and calls `setEnabled` after unlocking (`:117-128`), as `handleDisabled` already does (`:244-258`). Stand-in test: a `setEnabled` that takes the tap's lock returns |
| 14 | Record the voice key machine in the docs | `docs/VOICE-KEY.md` (the "Chords" section at `:37-56` becomes the rules of part 3 and the plain answer of part 6), `docs/STATE-MACHINES.md` (a new entry: voice hold key, explicit, with the 13 variables it replaces), `docs/TILING-PLAN.md` (the key clash paragraph at `:458-489` becomes part 6), `qa/regressions.json` rows after REG-409 for F1 to F5 |

**Deleted.** From `HotkeyMonitor.swift`: the stored `gesture`, `sharedDown`, `holdTimer`, `commandLatched`, `isDown`,
`cancelledByLargerChord`, `latch`, `pendingStop`, `directPressActive`, `state` (`:97-109`); the functions
`otherKeyPressed`, `spoilHold`, `handleShared`, `evaluate`, `endedByLargerChord`, `finishEndedTurn`, `cancelHold`, `fire`
(`:161-322`); `cancelsWhenSpoiled` (`:93`) and its setter (`AppDelegate.swift:286-287`); the release fallback of a
cancel. From ZeusCore: `TalkKeyLatch` (`ZeusCommand.swift:271-352`) and `SharedKeyGesture.swift`. Thirteen variables in
three types become four values in one. Kept: `ShortcutState`, the feed, `PointingKeyGesture`, the monitor's callbacks.

**Risks.**
- Ten behaviours change on purpose (C1 to C10). None is pinned by a test today, so only the Mac list below can say they
  feel right. C2 and C5 change dictation on its shipped key: a shortcut made with Right Command now cancels the turn.
- The three ported suites change their bodies. The review must check each timeline and expectation against the old one.
- A release the monitors never see (secure input hides keys from them; not verified here) leaves a turn open until the
  next event, as today. This plan adds no watchdog to `HotkeyMonitor`.
- `allUp` trusts `deviceKeys`. A modifier already down when the monitor starts is not in it, so `barred` can clear early.
- Fn is foreign for a key that does not hold it. Not verified on hardware: that no flags event carries the Fn flag
  without the Globe key down. The walk's time is an estimate until step 2 measures it.
- Not changed here: the shared test compares the talk key the owner chose, not the one heard while VoiceOver runs
  (`HotkeyMonitor.swift:88`); and Esc while latched does not reach the machine (`abandon` exists and is tested; wiring
  it from the two controllers is a change of its own).
- F3 and F5 rest on the event tap contract (a new tap starts enabled; enabling a dead port does nothing): not verified.

**Only a person at the Mac can check.**
1. Control, Option, Shift, Command, Left, fast and slow, twice in a row: nothing sent, hands-free never latched (F1).
2. Part 6: Control and Option before Command gives one listen sound and a dropped turn; Command first, nothing.
3. Hold to talk, quick tap, double tap hands-free and the tap that ends it, on Control-Option and on Right Command.
4. Dictation: hold and release; hold, Shift, release gives Return, on a dedicated key and on the shared key.
5. Right Command with C, with V, and with Tab: dictation is cancelled and the shortcut works (C2).
6. Press to toggle dictation and the Polyglot key: one toggle per press, none on a tiling chord.
7. VoiceOver on: the talk key moves, Control-Option refuses once per press, tiling shows its note.
8. A dictation key recorded as the pair plus Shift: tiling shows the note and installs no tap (F2).
9. Tiling switched on and off twenty times while typing in another app: no lost or late keystroke (F3 to F5).
10. A real keyboard's rollover: no dead talk key after fast typing, and no turn opened by typing.
