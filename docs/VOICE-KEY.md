# The Zeus voice key: Control+Option

Owner request (2026-11-11): holding Control and Option is the way to talk to Zeus by voice. Hold, speak (point at
something if you want), let go, and Zeus answers out loud in the Zeus voice.

## What one hold does

| Step | What happens | Code |
|---|---|---|
| Key down | The talk turn starts: listen sound, microphone, screens captured while you talk (cursor screen first, with the pointer position in pixels) | `HotkeyMonitor` (talk role) to `AppDelegate.talkKeyPressed` to `VoiceTurnController.press` |
| Release | Transcript, instant commands, fast path, then the fast tier race (Haiku, fast OpenAI model) with the Sonnet deep follow-up | `VoiceTurnController.release` |
| Answer | Spoken sentence by sentence through `Speaker` (engine router plus the Ultron effect chain), `[POINT]` and `[HIGHLIGHT]` marks drawn on screen when the answer refers to it | `VoiceTurnController.runTurn` |

Exactly one turn starts per hold. `VoiceKey` (Sources/ZeusCore/VoiceKey.swift) is the single routing rule:

- The talk turn owns every hold of the talk key.
- The desktop pointing monitor starts its own turn only on a pointing key that differs from the talk key
  (`VoiceKey.pointingStartsTurns`). With the shipped defaults (talk and pointing both Control+Option) the pointing
  monitor stands down for that hold: no second microphone, no second listen sound, no VoiceOver notice. Esc and the
  double Control text entry still pass through.
- Pointing off: the same talk turn.
- No Screen Recording: the same talk turn without screenshots (a plain talk turn). Nothing ever prompts.

### Why the talk turn and not the pointing turn

Before this change a Control+Option hold went only to the pointing turn (`PointingKeyGesture`, default
`.controlOption`), because the talk key had been migrated to Option+Command. The pointing turn has its own model
router (Sonnet or OpenAI) and its own voices (vendor voice or the plain Mac voice, no Ultron chain), and it has no
fast path or instant commands. Giving it the Zeus voice and the fast tier would mean rebuilding the talk pipeline
inside it. The talk turn already is that pipeline and already sees the screen, so it owns the hold and nothing is
duplicated.

What the owner gives up on the shared key: the pointing turn's ink trail while held and its timed scene drawings.
Choose Right Option or Fn as the pointing key in Settings > Assistant > Desktop pointing to keep a separate pointing
turn with drawings; Control+Option then stays the Zeus talk key.

## Chords built on Control+Option

Control+Option+C (Chat), Control+Option+T, Control+Option+Y/N/O are not the bare hold. A key joining the held chord
cancels the talk turn: nothing is sent, and the chord cannot restart until every key is up. The listen sound can still
play for the instant before the extra key lands, as the pointing hold did before.

### The talk chord: Control+Option+Space

Space is the one key that may join a held Control+Option without cancelling the turn (`VoiceKey.talkChord`,
docs/ULTRON-CHORD-PLAN.md). It is the same turn: one start, one listen sound, the hold sends when a modifier is let go.
The chord exists only when all of these hold: the talk key as heard is exactly the bare Control+Option, talk is a hold
key (not shared with dictation), VoiceOver is off (Control+Option+Space is VoiceOver's own activate key), and no
Carbon shortcut (Chat, the agent picker, Quick to-do) is Control+Option+Space. `Config.chord` carries it to the machine
for the talk role in hold mode only; dictation, Polyglot, pointing and the shared gesture treat Space as foreign.

A Carbon hot key on Control+Option+Space (`TalkChordHotkey`, signature `ZTLK`, handler that does nothing) takes the press
away from other apps and the input-source shortcut while the chord is active. The machine is correct either way: if
Carbon hides Space from the monitors nothing changes, if they see it Space is allowed, and if the registration fails
(another app holds it) Space is still allowed and Settings says so.

- A **clean chord** is Space going down while the talk key's own set is down alone. It stays clean until Space or an own
  modifier goes up. A Space that is not clean (before the pair, beside a third modifier, typed with nothing held) is
  foreign: the machine marks it (`chordSpoiled`) until every key is up, and nothing starts on a pair that came after it.
- Space then Control+Option starts nothing until every key is up; Control, Space, Option starts nothing.
- Space let go before the modifiers keeps the turn; a modifier let go with Space still down is a clean release (sends,
  taps or latches). Control+Option+Space+Command, Shift or any other key is foreign: cancel when holding, drop when armed.
- Beside tiling the turn starts 0.15 s after the pair as before; a chord tap shorter than that does nothing.
- Double-tap latches hands-free. Space does not end a hands-free turn when it comes first; the pair then Space does, after
  the confirm (at the press when confirm is 0).
- New rule **I9**: an event that only moves a clean chord's Space gives no `start`, `send` or `cancel`, except what an
  overdue timer owes, settled first. New rule **I8c**: from rest, pressing Control, Option, Space acts as I8.
- The walk models the Carbon swallow as a move with no event (`swallowed`). A watchdog tick that finds a modifier gone
  resyncs the picture and forgets every ordinary key, Space included: an existing limit the walk header names for an arrow.
- Carbon hides Space from the key monitors, so `HotkeyMonitor.feed` asks the live key state on each flags event while the
  chord is on: a Space that is down and unknown to the machine is told to it first, on the flags the machine had, at the
  time of that flags event. A Space that came before the set then spoils the hold, and one that joined it does not. The walk
  run A-carbon swallows every Space and checks this with rule I6s (no start beside a Space the keyboard did not earn as a
  chord); with the injection off the search finds the violation.
- The Carbon hot key behind the chord (`ZTLK`) is asked for again on every sync while it is refused, is taken only while
  Accessibility or Input Monitoring is on, and is registered after the Chat key has moved and the shortcuts have been told.
  Moving Chat lets go of the old key, tells the chord, then registers the new key. Settings recorders pause the Carbon hot
  keys by count, and an app switch ends a recording.

### Chat moved to Control+Option+C

`ChatHotkey.standard` is Control+Option+C. Nothing is written to UserDefaults by the change: no `chat.hotkey` value means
Control+Option+C. A stored `controlOptionSpace` is an explicit choice (`ChatHotkeyMonitor.set` is the only writer) and is
kept: the chord then yields, Space stays foreign, Chat keeps the press, and Settings shows the clash with one button to
move Chat to Control+Option+C (`VoiceKey.chatClash`). A tiling binding on Control+Option+Space is named by
`TileBaseConflicts.notes(talkChord:)`. Every Carbon registration has its own signature (`CarbonHotkeySignature`: `ZCHT`
Chat, `ZTLK` the chord, `ZEUS` the other hot keys) and each handler answers only its own, so one Zeus hot key can no longer
run another's action. The recorder lets go of the Carbon hot keys while it listens.

The hold keys (talk, dictation, the Polyglot key) follow one explicit state machine, `VoiceKeyMachine`
(`Sources/ZeusCore/VoiceKeyMachine.swift`). `HotkeyMonitor` is a stateless adapter: it feeds the machine every key, wake
and sleep notice and runs the effects that come back (`start`, `send`, `cancel`, `refused`, a wake). The rules hold after
every step of every press order, and `VoiceKeyWalkTests` walks the orders to check them.

Foreign means a modifier outside the key's own set (the other side of a sided key counts) or an ordinary key that is not
the key's own (the talk chord's Space is the one exception, below). The rules:

1. A press that something foreign joined never sends and never latches. Shift on a dictation key is the one exception:
   it marks the turn (Return) and the turn is sent when the key is let go. On a talk key Shift is foreign like any other.
2. After a cancel nothing starts until every key is up.
3. Nothing starts on a larger chord, and nothing starts when a larger chord shrinks to the key's own set.
4. Every turn ends exactly once, by `send`, `cancel` or the owner's own end.
5. A consumed key is a key. A chord key the tiling tap forwards and the same key from a monitor give the same effects.
   Each is read at the time it went down or up, not the time a busy main thread handled it.
6. A toggle key (press to toggle dictation, the Polyglot key) fires once per press.
7. A hands-free turn is sent only by a press of exactly the key's own set. Typing and larger chords neither send nor
   cancel it.
8. Never stuck: let go of everything, wait half a second, press the key's own set, and it acts. With the chord on, pressing
   Control, Option, Space from rest acts the same (I8c).
9. A clean chord's Space is not foreign for rules 1, 3 and 7, and moving it alone gives no start, send or cancel (I9).

A hold key waits `confirm` seconds alone before it acts. It is 0 except while a tiling chord holds the key's modifiers
(see below), and 0.25 s for dictation on a key it shares with talk. A hold sends when the key is let go, a quick tap
sends after the gap, and two quick taps latch a hands-free turn until the next tap. The press that ends a hands-free
turn waits for `confirm` too, on a shared key as well as a hold key.

### Tiling chords and the voice keys

The tiling keymap binds sets of modifiers: with the shipped table the pair (Control-Option-Command) and the pair plus
Shift (swap and nudge). `TileBaseConflicts` compares every modifier-only voice key with every set the keymap binds,
without Fn, and a key that differs from a bound set only by Fn counts as equal. Fn alone is free.

| The key's modifiers against the bound sets | Hold key (talk, pointing, dictation hold) | Key that switches on at the press (press to toggle dictation, modifier-only Polyglot) |
|---|---|---|
| Equal to a bound set | Refused | Refused |
| Strictly inside a bound set | Free, with a confirm of 0.15 s while the tiling tap is installed | Refused |
| Inside no bound set | Free | Free |

A dictation hold key is also refused one Shift short of a bound set, because Shift joining it only marks the turn, so a
bound chord of the key's modifiers plus Shift would reach its own key before anything foreign showed. A note names the
bound chord ("Control-Option-Command-Shift is also your Dictation key").

The shipped defaults clash with nothing: talk and pointing are Control-Option and dictation is Right Command in hold
mode, all strictly inside the pair, and Polyglot is keyed.

Can the microphone open on a tiling chord? Without the confirm, yes, on a chord pressed with Control and Option first
and Command last. A start is not cheap: it stops speech and drops the answer Zeus was working on, lets the wake word
listener release the microphone, plays the listen sound, dips other audio, shows listening, and starts a screen capture
and a browser tab read. The cancel that follows sends nothing and brings none of that back. With the confirm the answer
is: only on a chord pressed one key at a time, with the first keys held alone for 0.15 s. Pressed as a chord, nothing
opens. `TileBaseConflicts.confirm(for:keymap:)` is the middle cell as a pure function. Talk, dictation and pointing
read it through `TilingController.holdConfirm(for:)`, which asks the installed tap's keymap and says 0 with no tap, so
the keys act at once while tiling is off. A tap shorter than the confirm does nothing; a double tap still latches. The
same facts and the same start rule hold for pointing (`PointingKeyGesture` reads `KeyFacts`): a larger chord that shrinks
to the key starts nothing, and a sleep, wake or timeout takes the live modifiers. 0.15 s is a first value, not measured.

When talk and dictation share one key, the hold begins only on an exact match: nothing else may be down when it is armed
(Command pressed first, then Control and Option, starts nothing). Once the hold runs, a foreign key or modifier cancels it (Shift on dictation only marks the turn).

## The second talk key: Right Option

Right Option alone is a second talk key beside Control+Option (and its Space chord). It starts the same talk turn, which
can drive the Mac and asks the same approvals. Plan: `docs/RIGHT-OPTION-TALK-PLAN.md`.

`TalkKeyPair` (`Sources/ZeusCore/TalkKeyPair.swift`) is a pure arbiter in front of two unchanged `VoiceKeyMachine`s, one
for each key, with one owner and one bar. It sits inside the talk `HotkeyMonitor` in place of the single machine. Dictation
and Polyglot give it no second key, and then it passes every effect through (`aPairWithoutASecondKeyActsAsTheMachine`).

- **I10. One talk turn.** Across both talk keys at most one turn is open. A start while a turn is open never reaches the
  owner. Every send or cancel belongs to the open turn and is judged by I1 to I9 against the own set of the key that opened it.
- **I11. The other key waits.** After a turn ends (send, cancel or abandon) with any key still down, the other talk key
  starts nothing until every key is up.
- **I8p.** From rest, pressing exactly either key's own set acts. When a hands-free turn is open, only the key that opened
  it ends it. The other key is swallowed: it neither continues nor ends the turn.

Right Option is a typing key, so its second key waits `VoiceKey.secondKeyConfirm` (0.25 s, or the tiling confirm when that
is longer) before it starts. A letter inside that time reads as typing and starts nothing (accents). Left Option never
starts it, and joining a Right Option turn cancels it. A tap shorter than the confirm does nothing; a double tap latches.

**The mouse cancels it** (owner decision). While the second key's turn is armed or held, any mouse button going down (left, right,
other; a drag starts with one) is a foreign key for the second key only: a press still inside its confirm is dropped, a held turn is
cancelled and never sent, and nothing starts until every key is up. An Option-click or Option-drag therefore does not talk.
`TalkKeyPair.mouseDown` is the pure event (the machine hears a foreign key that is down and up at once, and only the second
slot is told); `HotkeyMonitor.mouseDown` is fed by global and local monitors of the three mouse-down types. The click is read at the time it happened
(`NSEvent.timestamp`, never later than now), as a key is, so a busy main thread cannot let a confirm that came due after the click
start the turn first. After a mouse cancel nothing starts until every key is up, the other talk key included (I11: the turn ended
with a key still down). The primary key and a hands-free second turn (no key held) are not affected.

**Timers run in order.** Each machine asks for its own timers (the confirm, the 0.4 s gap, the 0.25 s check). The pair keeps their
times and, before it hands a key to the machines, runs every timer that fell due by that key's own time, earliest first across
both machines, as the tick the adapter would have delivered. A busy main thread therefore gives the effects of timers that ran
on time (`timersThatRunLateGiveTheEffectsOfTimersThatRunOnTime`, and the three orders of the review). With no second key the
pair does none of this and is the machine.

**A Space the system says is down** at the release of a second-key turn means a launcher on Option-Space that Carbon cannot see
took the press: the turn is cancelled, not sent. A Space tapped and let go between two looks at the keyboard is caught too: the
monitor asks the system on every key event and tick while the second key's turn is open, and a Space seen once cancels the turn.

**The default is written nowhere.** `ShortcutStore.loadSecondTalk` returns Right Option when `talk.secondShortcut` is
absent or does not parse, and never writes. Only the recorder writes (`off`, or a key); Reset removes the key.

**The default yields** (`VoiceKey.secondTalkKey`, in this order): to the talk key as heard (the VoiceOver fallback on Right
Option included), to dictation, to Polyglot, to pointing when pointing is on the same key and the second key is still the
default, to VoiceOver when the key is Control-Option, and to a Carbon shortcut on Option alone (Chat on Option-Space), since
Carbon may hide Space from the monitors. A key the owner recorded for the second key is kept against pointing, and
`pointingStartsTurns(secondTalk:)` makes pointing stand down. Recording the talk, dictation or Polyglot key is refused
(`VoiceKey.secondTalkRefusal`).

Tests: `TalkKeyPairTests`, runs K and K0 and `theSecondKeyOrdersKeepTheRules` in `VoiceKeyWalkTests`, the second-key tests
in `VoiceKeyTests` and `TileBaseConflictsTests`, `HotkeyMonitorMachineTests`, `TilingKeyClashTests`. Rows REG-637 to REG-644.

## VoiceOver

VoiceOver uses Control+Option as its own modifier. While VoiceOver is on, Zeus leaves Control+Option to it and the
talk key moves to Option+Command (or Right Option, then Fn, whichever no other Zeus key uses):
`VoiceKey.effectiveTalkKey`. Settings shows this under the talk key while VoiceOver runs. When VoiceOver is off,
Control+Option is the talk key again.

## Migration

`ShortcutStore.loadTalk`:

1. A fresh install gets Control+Option.
2. Earlier builds wrote Option+Command (and before that Right Command) into `talk.shortcut` on first load. Those are
   auto-written defaults, not choices, so they move to Control+Option once. The flag
   `talk.shortcut.migratedToControlOption` makes it run once only.
3. Settings, Reset and onboarding record the key through `Preferences.chooseTalkKey`, which also sets
   `talk.shortcut.chosen`. A recorded key is never migrated.
4. The old fixed names in `pushToTalk` carry over: Right Option and Fn are kept as choices; Right Command and
   Control+Option become Control+Option.

## Tests

`Tests/ZeusCoreTests/VoiceKeyTests.swift` (default, migration matrix, single owner, VoiceOver, conflicts, pointer
pixels), `Tests/ZeusCoreTests/VoiceKeyMachineTests.swift` (one test per row of the transition table),
`Tests/ZeusCoreTests/VoiceKeyWalkTests.swift` (every press order against the rules above),
`Tests/ZeusCoreTests/KeyFactsTests.swift`, `Tests/ZeusCoreTests/TileBaseConflictsTests.swift` (the clash table),
`Tests/ZeusAppTests/HotkeyMonitorMachineTests.swift` (the adapter and `theTalkChordCallsPressOnceAndReleaseOnce`),
`Tests/ZeusAppTests/TalkChordHotkeyTests.swift` (the Carbon registration), `Tests/ZeusAppTests/TilingKeyClashTests.swift`
(`everyCarbonRegistrationHasItsOwnSignature`), `Tests/ZeusCoreTests/ChatHotkeyTests.swift`, `Tests/ZeusAppTests/TilingConsumedKeyTests.swift`
(`aTalkTurnThatTheRestOfTheTilingPairEndsIsCancelledNotSent`,
`aDedicatedDictationHoldThatTheRestOfThePairEndsIsCancelledNotInserted`,
`aModifierJoiningThePressThatEndedAHandsFreeTurnDoesNotCancelIt`,
`aSharedHoldOfAPairInsideTheTilingPairDoesNotStartDictationWhenCommandComesFirst`),
`Tests/ZeusAppTests/PointingHotkeyMonitorTests.swift` (`theTalkKeyHoldStartsNoPointingTurn`),
`Tests/ZeusCoreTests/ShortcutConflictsPointingTests.swift`, `Tests/ZeusCoreTests/ShortcutTests.swift`. Rows REG-380 to
REG-384 and REG-628 to REG-635 (the chord) in `qa/regressions.json`.
