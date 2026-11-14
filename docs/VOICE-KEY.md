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
joining the held chord cancels the talk turn (`HotkeyMonitor.cancelsWhenSpoiled`, `VoiceTurnController.cancelListening`):
nothing is sent, and the chord cannot restart until every modifier is up. The listen sound can still play for the
instant before the extra key lands, as the pointing hold did before.

A modifier joining a hold works the same way, with tiling on or off. The talk key and a dedicated dictation key are
holds of exactly their own modifiers: when Control, Option or Command joins a running hold (the owner is pressing a
larger chord such as Control-Option-Command), the turn is cancelled and nothing is sent, and it cannot restart until every
modifier is up (`HotkeyMonitor.cancelHold`). Shift and Fn joining still end the hold the normal way, because Shift is how
dictation asks for Return. Only a press that began or continued a turn is cancelled. The press that ended a hands-free
turn already finished it, so a modifier joining that press cancels nothing and the text is still inserted
(`TalkKeyLatch.isEnding`, `HotkeyMonitor.finishEndedTurn`).

When talk and dictation share one key, the hold begins only on an exact match: nothing else may be down when it is armed
(Command pressed first, then Control and Option, starts nothing). A hold that is already running tolerates extra
modifiers, which is why Shift can mean Return. The running shared hold is not cancelled by a modifier joining; it is
cancelled when another key is pressed, which includes a tiling chord's key forwarded by the tiling tap
(`TilingConsumedKey`, `HotkeyMonitor.otherKeyPressed`).

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
pixels), `Tests/ZeusAppTests/PointingHotkeyMonitorTests.swift` (`theTalkKeyHoldStartsNoPointingTurn`),
`Tests/ZeusCoreTests/ShortcutConflictsPointingTests.swift`, `Tests/ZeusCoreTests/ShortcutTests.swift`
(`theTapThatEndsALatchedTurnIsEndingUntilItsKeyUp`), `Tests/ZeusAppTests/TilingConsumedKeyTests.swift` (modifier-join cancel:
`aTalkTurnThatTheRestOfTheTilingPairEndsIsCancelledNotSent`, `aDedicatedDictationHoldThatTheRestOfThePairEndsIsCancelledNotInserted`,
`aModifierJoiningThePressThatEndedAHandsFreeTurnDoesNotCancelIt`; exact start on the shared key:
`aSharedHoldOfAPairInsideTheTilingPairDoesNotStartDictationWhenCommandComesFirst`). Rows REG-380 to REG-384 in `qa/regressions.json`.
