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

Control+Option+Space (Chat), Control+Option+C, Control+Option+T, Control+Option+Y/N/O are not the bare hold. A key
joining the held chord cancels the talk turn: nothing is sent, and the chord cannot restart until every key is up. The
listen sound can still play for the instant before the extra key lands, as the pointing hold did before.

The hold keys (talk, dictation, the Polyglot key) follow one explicit state machine, `VoiceKeyMachine`
(`Sources/ZeusCore/VoiceKeyMachine.swift`). `HotkeyMonitor` is a stateless adapter: it feeds the machine every key, wake
and sleep notice and runs the effects that come back (`start`, `send`, `cancel`, `refused`, a wake). The rules hold after
every step of every press order, and `VoiceKeyWalkTests` walks the orders to check them.

Foreign means a modifier outside the key's own set (the other side of a sided key counts) or an ordinary key that is not
the key's own. The rules:

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
8. Never stuck: let go of everything, wait half a second, press the key's own set, and it acts.

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
`Tests/ZeusAppTests/HotkeyMonitorMachineTests.swift` (the adapter), `Tests/ZeusAppTests/TilingConsumedKeyTests.swift`
(`aTalkTurnThatTheRestOfTheTilingPairEndsIsCancelledNotSent`,
`aDedicatedDictationHoldThatTheRestOfThePairEndsIsCancelledNotInserted`,
`aModifierJoiningThePressThatEndedAHandsFreeTurnDoesNotCancelIt`,
`aSharedHoldOfAPairInsideTheTilingPairDoesNotStartDictationWhenCommandComesFirst`),
`Tests/ZeusAppTests/PointingHotkeyMonitorTests.swift` (`theTalkKeyHoldStartsNoPointingTurn`),
`Tests/ZeusCoreTests/ShortcutConflictsPointingTests.swift`, `Tests/ZeusCoreTests/ShortcutTests.swift`. Rows REG-380 to
REG-384 in `qa/regressions.json`.
