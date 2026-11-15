# Right Option talk key plan: hold Right Option alone to talk, beside Control+Option

Base: `codex/ultron-chord-20261115` at committed HEAD `3cd2e03` (`/Users/tony/AI-Brain-build/zeus-ultron`). This was read-only research: nothing was built, run or edited, and uncommitted files were ignored.

## 0. Verified facts (file:line, at HEAD)

**The machine and its adapter**
- `VoiceKeyMachine` is one reducer per monitor.
  - `Config` (key, role, mode, voiceOverHoldsKey, confirm, chord) is at `Sources/ZeusCore/VoiceKeyMachine.swift:11-32`.
  - A config "differs" only by key, mode or voiceOverHoldsKey: `:162-164`.
  - `generation` and `abandon(turn:)`: `:89`, `:207-208`.
  - `updateBarred`: `:225-237`. Rows: `react` `:350-422`, `beginPress` `:425-445`, `endHandsFreeTurn` `:448-465`.
- `HotkeyMonitor` holds one `machine` and one `ownerTurn` (`Sources/Zeus/Voice/HotkeyMonitor.swift:119-121`).
  - It rebuilds the config at every event (`:215-225`).
  - `feed` sweeps first, then injects a Space it missed by asking the live key state (`:176-191`).
  - `send` maps effects to `onPress`, `onRelease`, `onCancel` and `onBlocked` (`:229-254`).
  - The same class runs dictation and Polyglot (`PolyglotController.swift:59`, `:111`).

**A refused press is not free, so arbitration cannot happen in the owner**
- `talkKeyPressed` (`Sources/Zeus/App/AppDelegate.swift:638-661`) does several things before it can return false:
  - `ExplanationAudioArbitration.yieldToNewCapture()`
  - sets `talkKeyHeld`
  - `buddy.call()`
  - posts `Speaker.talkKeyPressed`
- `VoiceTurnController.press()` (`Sources/Zeus/App/VoiceTurnController.swift:132`) is a barge-in: it cancels the fast race and calls `PersistentClaudeSession.shared.abortBusy()`.
- So a second key's press must never reach `onPress` while a turn is open. Arbitration has to sit in front of the owner.
- `press()` takes no key argument, so the turn and its DrivePlan approval levels cannot tell which key started it. Nothing in the drive path changes.

**Sided keys**
- `Shortcut.rightOption = Shortcut(modifiers: .option, side: .right)` (`Sources/ZeusCore/Shortcut.swift:45`). A side is kept only for a single modifier with no key code (`:40`).
- `KeyFacts`:
  - A sided key needs its own device key (61). The other side (58) sets `otherSideDown`, which is foreign (`Sources/ZeusCore/KeyFacts.swift:42-47`, `:24`).
  - `.controlOption` has side `.any`, so Control plus Right Option is exactly its own set.
- `ShortcutState` tracks device keys from the flags key code (`Shortcut.swift:322-336`). Run B of the walk already has both Commands (`VoiceKeyWalkTests.swift:169`), so the harness handles two keys with one flag.
- `ShortcutConflicts.overlaps` and `sidesOverlap` exist (`Shortcut.swift:256-276`).

**Routing**
- `VoiceKey.voiceOverFallbacks = [.optionCommand, .rightOption, .function]` (`Sources/ZeusCore/VoiceKey.swift:19`).
- `effectiveTalkKey` is at `:23-27`.
- `pointingStartsTurns(talk:pointing:pointingEnabled:)` is at `:31-33`, and `owner(ofHold:)` at `:36-44`.
- The pointing key choices include "Right Option" (`Sources/Zeus/Pointing/PointingHotkeyMonitor.swift:17-19`). The default is Control-Option (`:21`). A stored Right Option is therefore always an explicit choice.
- Pointing asks `pointingStartsTurns` at `PointingHotkeyMonitor.swift:36-38`.
- Pointing warns when another key is a superset of its own: "Holding X first holds Y" (`PointingShortcutConflicts.swift:40-49`).

**Carbon**
- Chat offers `optionSpace` (`Sources/ZeusCore/ChatHotkey.swift:5-12`).
- The agent picker and Quick to-do presets have no Option-only entry (`Sources/Zeus/App/ExtraPreferences.swift:9`).
- Answer keys and Prompter pause are Control-Option plus a letter (`AppDelegate.swift:1112-1119`, `TilingKeyClash.swift`).
- The holders list for the chord is `TalkChordRouting.holders()` (`Sources/Zeus/Voice/TalkChordHotkey.swift:8-23`).

**Tiling**
- `holdConfirm = 0.15` (`Sources/ZeusCore/Tiling/TileBaseConflicts.swift:41`); `confirm(for:)` is at `:46-52`.
- `notes(...)` lists the voice keys at `:111-125`.
- Right Option `{option}` is strictly inside Control-Option-Command, so it is free with the 0.15 s confirm while the tap is installed.
- `TilingKeyClash.Keys` and `live()` are at `Sources/Zeus/Tiling/TilingKeyClash.swift:43`, `:60`.

**Settings and catalog**
- `ShortcutStore` keys are at `Shortcut.swift:148-158`.
- `Preferences.chooseTalkKey` and `talkKeyHint` are at `Sources/Zeus/App/Preferences.swift:47-63`.
- `ShortcutRecorderRow` (`Sources/Zeus/Settings/GSShortcutRecorder.swift:124-150`):
  - It supports `allowsOff`, `notes` and Reset.
  - Reset calls `set(defaultValue)`.
- The "Summon Zeus" card is at `Sources/Zeus/Settings/GlanceSettingsPages.swift:772`.
- The catalog Talk row is `scripts/gen-settings-catalog.py:218` (section `voice`, from `:215`).
- The `opt_in` guard covers mic-opening toggles only (`:264-273`). A recorder row of kind `choice` is not checked by it.

**Walk and QA**
- Runs are at `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift:162-210`. Keys have no Right Option today (`:69-79`).
- The checker and `Phys` read one `ownMask` (`:302-310`, `:945-984`).
- Run H already swaps the subject behind `Sim.handle` (`:905-931`). That is the pattern to reuse.
- `WALK_ONLY` is at `:41`, `:1228-1231`.
- The highest REG on this branch is **REG-636** (`qa/regressions.json:5547`). No doc claims a later one. **The next free ids are REG-637 to REG-644.**
- `F11.talk-chord` is at `qa/feature-map.json:4785`. App test suites have no `native-*` check id (ULTRON plan, section 0), so the REG guards go in ZeusCoreTests.
- `qa/portable-core/prepare.py` does not list `VoiceKeyMachine.swift` or `VoiceKey.swift` (`:122-127`). A new Core file beside them needs no change there.

**Unknowns, planned around**
1. The "Eighth pass" has no section in the committed docs. It exists only as walk tests (`VoiceKeyWalkTests.swift:1307`) and commits `538d5af` to `f2c2770`. This plan calls its doc section the Ninth pass. If the builder lands an Eighth pass section first, it is the next number.
2. Whether Carbon hides a matched key-down from the monitors (ULTRON unknown 1). It matters for Chat on Option-Space, and the design yields so the answer does not matter.
3. How fast people type Right Option plus a letter. 0.25 s is a first value, not measured (on-device check 3).

## 1. Architecture: one talk turn, two machines behind a pure arbiter

**Choice: `TalkKeyPair`, a new pure Core struct.** It holds two unchanged `VoiceKeyMachine`s (primary, second), one owner and one bar. It sits inside the single talk `HotkeyMonitor`, in place of `machine`.

**Why not one machine with a set of own keys**
- Control plus Right Option reads E for the primary key and F for Right Option. Every reading, `barred`, `chordSpoiled` and every row would have to be worked out per key. That is two machines inside one.
- It would change the reducer that dictation, Polyglot and all 15 walk runs depend on. Each would need re-proving and re-measuring.

**Why not a second `HotkeyMonitor` with an arbiter in AppDelegate**
1. The order in which two NSEvent monitors fire is undefined, so who wins one flags event would not be deterministic.
2. The owner's refusal path already runs barge-in side effects (see the facts above).
3. It cannot be walked.

**What the pair gives**
- `VoiceKeyMachine` stays byte-for-byte unchanged: zero diff, and runs A to J keep their proofs and numbers.
- One feed, one sweep, one Space probe and one `ownerTurn`.
- The arbiter is about 100 pure, walkable lines.
- With the second key nil, the pair passes everything through, so dictation and Polyglot (second always nil) behave exactly as today. A test proves this equivalence.

**Second key config**
- `Config(key: second, role: .talk, mode: .hold, voiceOverHoldsKey: second == .controlOption && voiceOver, confirm: max(VoiceKey.secondKeyConfirm, tilingConfirm(second)), chord: nil)`, with `secondKeyConfirm = 0.25`.
- The confirm is the C14 mechanism used for typing. A Right Option plus letter inside 0.25 s reads armed then F, which drops the press: no start, no mic.
- A tap shorter than 0.25 s does nothing. A double tap still latches (row 6, quick second tap).

## 2. Pair rules (the "transition table diff")

The machine table in part 4.3 is unchanged: **no row is added, removed or edited.** The new table is the pair's.

Every event except `abandon` goes to the primary first, then to the second, with each one's config. Each effect is then filtered in order:

| # | Effect from slot s | Condition | Pair emits | Pair state after |
|---|---|---|---|---|
| P1 | `start` | no open turn, s not barred by the pair | `start` | owner = (s, s.generation); pair `generation += 1` |
| P2 | `start` | the other slot owns an open turn | nothing | feeds s `.abandon(turn: s.generation)` at once. s goes idle, barred unless allUp (machine row 23) |
| P3 | `start` | no open turn, but the pair bars s (P4, P8) | nothing | as P2 |
| P4 | `send` or `cancel` | s is the owner | the effect | owner = nil; if any key is down, bar the *other* slot until allUp |
| P5 | `send` or `cancel` | s is not the owner | nothing | unreachable (the machine's I4: a slot with no open turn ends none). The walk asserts it never fires |
| P6 | `refused` | a turn is open | nothing | none (do not speak over a live turn) |
| P6b | `refused` | no turn open | `refused` | none |
| P7 | `wake` | any | `wake` | none (a stale tick is row 25) |
| P8 | event `abandon(turn)` | turn == pair generation and there is an owner | nothing | forward `.abandon(turn: owner's slot generation)` to the owner only; owner = nil; bar the other slot unless allUp |
| P9 | after any event | primary's `keys` are allUp | none | clear the pair bar |

- `isLatched` and `turnIsOpen` are the owner's.
- `keys` is primary.keys. Both machines apply the same key events; a test pins that the two pictures are equal.
- The same slot is never barred by the pair. Its own machine governs it, and that is already proven: `[send, start]` from one `handle` (a late gap tick, then the next press) stays legal.

**New rules** (added to `docs/VOICE-KEY.md` and part 3 of `docs/VOICE-KEY-MACHINE-PLAN.md`)
- **I10. One talk turn.** Across both talk keys, at most one turn is open. A start while a turn is open never reaches the owner. Every send or cancel belongs to the open turn and is judged by I1 to I9 against the own set of the key that opened it.
- **I11. The other key waits.** After a turn ends (send, cancel or abandon) with any key still down, the other talk key starts nothing until every key is up.
- **I8p.** From rest, pressing exactly either key's own set acts. When a hands-free turn is open, only the key that opened it ends it.

**The cases asked about**

| Order | Result | Why |
|---|---|---|
| Right Option alone, held 0.25 s or more | One start; release sends; quick taps follow the hold key rules | Second slot rows 4, 5, 9 |
| Right Option plus a letter inside 0.25 s (accent typing) | Nothing | Armed, then F: row 8 drops it and bars until all up |
| Right Option held past 0.25 s, then a letter | Start, then cancel; never sent | Row 11, I1 |
| Left Option, alone or with anything | Never starts | `ownDown` needs device key 61 |
| Left Option joining a Right Option turn | Cancel | `otherSideDown` is foreign |
| Right Option plus Space | Foreign: drop (armed) or cancel (holding) | The second key has no chord |
| Control, then Right Option | Primary turn only | Control is foreign to the second key, which is barred |
| Right Option, then Control inside 0.25 s | Primary turn only, the same as today's Option-then-Control | The second key drops and is barred; the primary begins |
| Right Option held past 0.25 s, then Control | Second turn cancelled; nothing starts until all up | Second key row 11; the primary start is suppressed by P2 (or P3 if the order were reversed): I11 |
| Right Option pressed during a primary turn | Continues | Option is already in the flags; the primary key is side `.any` |
| Control released while Control plus Right Option is held | Primary sends; Right Option left down starts nothing | The second key was barred when it saw Control |
| Right Option during a primary hands-free turn | Nothing; the turn continues | P2 swallows the second key's start |
| Control+Option during a Right Option hands-free turn | Nothing | Primary start swallowed by P2; for the second key Control is foreign, so the latched turn is left as it is (rule 7) |
| Right Option within 0.4 s of a primary quick tap | Nothing | P2 while the gap is open; P3/I11 after the gap's send |
| Control+Option during a Right Option tap's gap | The Right Option turn is cancelled; nothing starts | Second key row 16 (its own rule) plus P2 |
| Second key set to Off or changed mid-turn | That turn is cancelled (the machine's config differs) | Step 2 |
| Primary key changed during a Right Option turn | Right Option turn continues | The primary has no open turn |
| Primary set equal to Right Option mid-turn | The second key yields (key nil), which cancels; the primary is barred | Step 2 on both |
| Late timers, swallowed Space, watchdog resync, sleep | Each slot handles them as today. `interrupt` cancels the owner's turn once (P4) | Unchanged machine |

**Recommendation on the other key during an open turn:** it neither continues nor ends the turn. It is swallowed (P2).

- Ending the turn with the other key would break rule 7 per key (a hands-free turn is sent only by its own set).
- It would need a cross-machine send that no walk proves.
- It would let Right Option, a typing key, end a turn the owner is speaking or typing into.

If Tony wants "either key ends hands-free", that is a P2 variant to decide later and walk separately.

## 3. Settings, migration, clash UX

**Storage**
- UserDefaults key `talk.secondShortcut`, read by a new `ShortcutStore.loadSecondTalk(_:) -> (key: Shortcut?, explicit: Bool)`:

| Stored value | Result |
|---|---|
| absent | `(.rightOption, false)` |
| `"off"` | `(nil, true)` |
| parses to a shortcut | `(s, true)` |
| does not parse | `(.rightOption, false)` |

- **It never writes.** Writing happens only in `Preferences.chooseSecondTalkKey(_:)`.
- Reset (`set(.rightOption)` from the row) removes the key, so the default rules apply again.

**Migration:** none, and nothing is written. Existing users get Right Option on update unless it yields (below).

**Runtime yield** (pure: `VoiceKey.secondTalkKey(chosen:explicit:heard:dictation:pointing:polyglot:voiceOverOn:carbonHolders:) -> (key: Shortcut?, yieldsTo: String?)`). Rules, in order:
1. If the chosen key is nil, the result is nil.
2. It equals or overlaps (`ShortcutConflicts.overlaps`) the heard talk key, including the VoiceOver fallback Right Option: yield to "Talk to Zeus".
3. It equals or overlaps an enabled dictation key: yield to "Dictation".
4. It equals or overlaps the enabled Polyglot key: yield to "Polyglot".
5. Pointing is enabled and on the same key:
   - If the second key is the default, it yields to "Pointing" (the owner chose Right Option for pointing).
   - If it is an explicit choice, talk owns the key and pointing stands down. `pointingStartsTurns` gains `secondTalk: Shortcut? = nil` and returns false when the pointing key equals it.
6. VoiceOver is on and the key is Control-Option: yield.
7. A Carbon holder whose modifiers are exactly Option (today only Chat on Option-Space) and an Option-only second key: yield to "Chat". This is the same "Carbon beats the chord" rule. If Carbon hides Space from the monitors, Right Option would otherwise start the mic while Chat opens.

`effectiveTalkKey` is not changed. If the VoiceOver fallback lands on Right Option, the second key yields and Right Option still talks once.

**Recording refusals** (pure `VoiceKey.secondTalkRefusal(_:talk:dictation:polyglot:) -> String?`)
- A recorded key equal to or overlapping the chosen talk, dictation or Polyglot key is not saved. The note reads: "This is already your <name> key."
- Everything else warns and yields.

**Shortcuts page, "Summon Zeus" card** (`GlanceSettingsPages.swift:772`): a new row under Talk.
- `ShortcutRecorderRow(symbol: "mic", title: "Second talk key", text: "Hold to talk, let go to send, double-tap to keep listening, like the talk key. Left Option and Right Option with a letter type as usual.", defaultValue: .rightOption, allowsOff: true, notes: ...)`
- Notes:
  - the yield sentence, for example: "Pointing uses Right Option, so this key is off. Record another key or change pointing."
  - the tiling note
  - "Hold it a quarter second before speaking."

**Tiling:** `TileBaseConflicts.notes(..., secondTalk: Shortcut? = nil)` adds `("Second talk key", secondTalk, false, false)` to the items at `:124`. `Keys.secondTalk` goes in `TilingKeyClash.Keys`.

**Catalog row** (after `gen-settings-catalog.py:218`):
```
o(S,'Talk to Zeus','Second talk key','recorder','-','Hold Right Option alone to talk, let go to send. Double-tap to keep listening. Turn it off or record another key.','missing','voice.secondTalkKey','choice',[],'Right Option','custom','Zeus addition. Recorder on Shortcuts. Stored under talk.secondShortcut only when you record or turn it off. The default gives way to a key you chose for pointing, dictation or Polyglot, and to Chat on Option-Space.')
```

## 4. Files

**Core**
- New `Sources/ZeusCore/TalkKeyPair.swift`:
  - `public struct TalkKeyPair: Sendable, Hashable`
  - `enum Slot { case primary, second }`
  - `handle(_ event: VoiceKeyMachine.Event, primary: Config, second: Config) -> [Effect]`
  - read-only: `keys`, `generation`, `isLatched`, `owner: Slot?`
  - an internal `arbitrate = true` test seam
- `Sources/ZeusCore/VoiceKey.swift`: `secondKeyConfirm`, `secondTalkKey(...)`, `secondTalkRefusal(...)`, `pointingStartsTurns(..., secondTalk:)`, `owner(ofHold:..., secondTalk:)`.
- `Sources/ZeusCore/Shortcut.swift`: `ShortcutStore.secondTalkKey`, `loadSecondTalk`, `recordSecondTalkChoice`.
- `Sources/ZeusCore/Tiling/TileBaseConflicts.swift`: the `secondTalk` parameter.

**App**
- `Sources/Zeus/Voice/HotkeyMonitor.swift`:
  - `machine` becomes `pair`.
  - `var secondKeyProvider: () -> Shortcut? = { nil }`.
  - `secondConfig` is built beside `config`.
  - `feed` reads `pair.keys`.
- `Sources/Zeus/App/AppDelegate.swift` (beside `:308-330`): `hotkey.secondKeyProvider = { SecondTalkRouting.current().key }`.
- New enum `SecondTalkRouting` in `Sources/Zeus/Voice/TalkChordHotkey.swift`, beside `TalkChordRouting`. It gathers the live keys and holders.
- `Sources/Zeus/Pointing/PointingHotkeyMonitor.swift:36-38`: pass the effective second key.
- `Sources/Zeus/App/Preferences.swift`: `secondTalkKey`, `chooseSecondTalkKey`; `talkKeyHint` gains "or hold Right Option".
- `Sources/Zeus/Tiling/TilingKeyClash.swift`: `Keys.secondTalk`.
- `Sources/Zeus/Settings/GlanceSettingsPages.swift`: the new row.

**Tests**
- New `Tests/ZeusCoreTests/TalkKeyPairTests.swift`.
- `VoiceKeyWalkTests.swift`, `VoiceKeyTests.swift`, `TileBaseConflictsTests.swift`.
- `Tests/ZeusAppTests/HotkeyMonitorMachineTests.swift`, `TilingKeyClashTests.swift`.

**QA and docs**
- `scripts/gen-settings-catalog.py` plus the generated `Sources/Zeus/App/SettingsCatalog.swift` and `docs/settings-inventory.md`.
- `qa/regressions.json`, `qa/feature-map.json`.
- `docs/VOICE-KEY.md`, `docs/VOICE-KEY-MACHINE-PLAN.md`, `docs/STATE-MACHINES.md` (new entry `TalkKeyPair` next to `:50`).

## 5. Commits (tests first; each one builds)

**0. Plan.** Add `docs/RIGHT-OPTION-TALK-PLAN.md`.

**1. Red: pair and walk.**
- Add `TalkKeyPair` as a stub that passes the primary through and ignores the second key.
- `TalkKeyPairTests` (fail against the stub):
  - `aPairWithNoSecondKeyGivesTheMachinesEffects`
  - `rightOptionHeldPastTheConfirmStartsOneTurnAndReleaseSends`
  - `rightOptionWithALetterInsideTheConfirmStartsNothing`
  - `rightOptionHeldThenALetterCancelsAndNeverSends`
  - `leftOptionNeverStarts`
  - `leftOptionJoiningARightOptionTurnCancelsIt`
  - `rightOptionWithSpaceIsForeign`
  - `controlThenRightOptionIsThePrimaryTurnOnly`
  - `rightOptionThenControlInsideTheConfirmIsThePrimaryTurnOnly`
  - `rightOptionHeldThenControlCancelsAndStartsNothingUntilAllUp`
  - `rightOptionDuringAPrimaryTurnChangesNothing`
  - `rightOptionDoesNotEndAPrimaryHandsFreeTurn`
  - `controlOptionDoesNotEndASecondHandsFreeTurn`
  - `doubleTapRightOptionLatchesAndTheNextPressEndsIt`
  - `aStartFromTheOtherKeyNeverReachesTheOwner`
  - `theOwnersAbandonEndsOnlyItsTurn`
  - `anAbandonOfAnOldTurnIsIgnored`
  - `turningTheSecondKeyOffMidHoldCancelsItsTurn`
  - `changingThePrimaryKeyLeavesASecondTurnAlone`
  - `sleepCancelsTheOpenTurnOnce`
  - `bothMachinesKeepOnePicture`
- Walk:
  - `WalkKey.rightOption` (code 61, flag `.option`).
  - `WalkRun.second: (own: [UInt16], config: Config)?`; `Sim.pair` behind `Sim.handle`, as run H does with pointing.
  - One `Checker` per slot, each with its own mask. The owning slot's checker judges a turn; the pair's `owner` is read by the harness only.
  - Pair checks: I10, I11, P5 never fires, and I8p in `restCheck` (from rest, press each key's set).
  - Run **K**: primary Control-Option, confirm 0.15, chord 49; second Right Option, confirm 0.25. Keys `[.control, .option, .rightOption, .leftArrow, .spaceOnPair]`, `late: true`, `refusal: true`.
  - Run **K0**: the same with primary confirm 0, `late: false`.
  - `theSecondKeyOrdersKeepTheRules`: replay the table in part 2 and assert the effect logs.
  - `theSearchSeesAPairThatLetsTheOtherKeyStart`: K with `arbitrate = false` must report I10.
  - `aPairWithoutASecondKeyActsAsTheMachine`: the plain walk of run A's moves to length 5 (66,429 sequences), pair against machine, identical effects.

**2. Green: `TalkKeyPair` (P1 to P9).** All runs green. Print and record states, moves and seconds for K and K0.

**3. Red: routing and clashes.**
- `VoiceKeyTests`:
  - `theSecondTalkKeyDefaultsToRightOptionAndWritesNothing`: a fresh suite, `dictionaryRepresentation` unchanged after load.
  - `theSecondKeyYieldsToAKeyChosenElsewhere`: talk equal, the VoiceOver fallback, dictation, Polyglot, pointing default against explicit, Chat Option-Space, VoiceOver with Control-Option.
  - `theSecondKeyChoiceIsRefusedOnTalkDictationAndPolyglot`
  - `pointingStandsDownForAnExplicitSecondKey`
  - `theSecondKeyWaitsAtLeastTheTypingConfirm`
- `TileBaseConflictsTests.aSecondTalkKeyIsComparedWithTheBoundSets`:
  - shipped keymap: free, confirm 0.15
  - a keymap that binds Option alone: refused note
  - `theShippedDefaultsClashWithNothing` stays unchanged

**4. Green: routing.**

**5. Red: adapter.** `HotkeyMonitorMachineTests` (add `secondKeyProvider`, not yet read):
- `theSecondKeyCallsPressOnceAndReleaseOnce`
- `aSecondKeyPressDuringAPrimaryTurnCallsNothing`: `onPress` once, no extra `onRelease` or `onCancel`
- `theDictationMonitorNeverHearsTheSecondKey`
- `TilingKeyClashTests`: `Keys.live().secondTalk`

**6. Green: adapter and wiring.** HotkeyMonitor holds the pair; AppDelegate, PointingHotkeyMonitor, `TilingKeyClash.Keys`.

**7. Settings UI.** Preferences, the Second talk key row, notes, `talkKeyHint`. Covered by commit 3's pure tests and on-device check 8.

**8. Catalog.** The row above. Regenerate; `scripts/check-settings-catalog.sh` must be green.

**9. QA records.** REG-637 to 644 (confirm with `~/AI-Brain-build/zeus-merge-reg.py` at merge; if taken, use the gap REG-385 to 389 and then 396 to 399). All use `native-ZeusCoreTests`:

| Id | Features | Guard |
|---|---|---|
| 637 | F11 | `TalkKeyPairTests.aStartFromTheOtherKeyNeverReachesTheOwner` |
| 638 | F11 | `TalkKeyPairTests.rightOptionWithALetterInsideTheConfirmStartsNothing` |
| 639 | F11 | `TalkKeyPairTests.leftOptionNeverStarts` |
| 640 | F11 | `TalkKeyPairTests.rightOptionHeldThenControlCancelsAndStartsNothingUntilAllUp` |
| 641 | F11 | `TalkKeyPairTests.rightOptionDoesNotEndAPrimaryHandsFreeTurn` |
| 642 | F11 | `VoiceKeyTests.theSecondTalkKeyDefaultsToRightOptionAndWritesNothing` |
| 643 | F11 | `VoiceKeyTests.theSecondKeyYieldsToAKeyChosenElsewhere` |
| 644 | F11 | `TileBaseConflictsTests.aSecondTalkKeyIsComparedWithTheBoundSets` |

Feature map: new obligation **`F11.second-talk-key`**, check `native-ZeusCoreTests`.
- Acceptance: "Holding Right Option alone starts the same talk turn, with one turn at a time across both keys. Left Option and quick Right Option typing never start it. The other key never ends an open turn. The default writes nothing and yields to a key chosen elsewhere."
- Cases: the eight guards plus `VoiceKeyWalkTests.theSecondKeyOrdersKeepTheRules`.

**10. Docs.**
- `VOICE-KEY.md`: new section "The second talk key: Right Option", rules I10, I11 and I8p, the yield list, tests and REG list.
- `VOICE-KEY-MACHINE-PLAN.md`: part 3 rows, part 5 K and K0 numbers, and a "Ninth pass" section (machine unchanged; pair rules; #32 and #33 not reachable in a new way, since the pair adds no feed path).
- `STATE-MACHINES.md`: the `TalkKeyPair` entry.

**Walk budget** (now about 8.7 min wall time with runs in parallel; run A alone was 511 s)
- Runs A to J are not touched (machine unchanged), so their cost is unchanged.
- K is bounded by design: 5 keys, one of them offered only while Control and Option are down, and no Command or Shift. Command and Shift are plain foreign modifiers for both slots, already covered by A.
- Gate: K and K0 must each stay under run A's states (1.41M) and time on the same Mac, so wall time grows by at most the plain-walk equivalence (about 6 s).
- Fallbacks, in order, if over:
  1. K drops `late`.
  2. K drops `.spaceOnPair` (the chord beside Right Option stays in the unit tests).
  3. K0 becomes a plain walk to length 6.
- `WALK_ONLY=K` is for local runs.

**Gates at the end**
- `swift build`
- ZeusCoreTests and ZeusAppTests with the walk unfiltered
- `scripts/check-settings-catalog.sh`
- the qa closed-loop tests
- **Vera PASS at the head SHA before merge.**

## 6. Risks

- **A default that opens the mic, on update.** Every existing user gets a new key that opens the microphone. This is Tony's decision (2026-11-15). It is not an `opt_in` toggle, so the catalog guard does not cover it. Say it in the release notes.
- **Option-click and Option-drag** with Right Option held (copying in Finder) give no key event. The mic starts after 0.25 s, and the release sends a turn that is probably empty. Not mitigated here. A mouse-down cancel would need a mouse monitor, which is a wider change. Owner decision; on-device check 6.
- **Typing speed.** Right Option held 0.25 s or more before a letter gives start then cancel: listen sound, speech stopped, answer dropped. Never sent. 0.25 s is a first value.
- **Two bare Right Option taps within 0.4 s latch hands-free**, the same as Control+Option today.
- **The pointing marker can flash.** With the talk key moved off Control-Option and pointing on Control-Option, Right Option held past 0.25 s and then Control gives a second-key start and cancel while pointing begins. Pointing's own reducer cannot see the pair. Existing warning text applies.
- **Sided limit, unchanged.** A missed Right Option release while Left Option stays down keeps the hold until Left is released, because the live flags have no sides. Right Command dictation has the same limit today.
- **Scope decisions that need Tony's approval:**
  - the other key is swallowed rather than ending an open turn (P2)
  - the default yields to pointing on Right Option and to Chat on Option-Space
  - the 0.25 s confirm
- **Irreversible actions:** none. Nothing is written to UserDefaults until the owner records a key.

## 7. Owner on-device checks

1. `defaults read <bundle id> talk.secondShortcut` after update: absent. Settings shows "Right Option".
2. In TextEdit, hold Right Option, speak, release: one listen sound, one spoken answer. A drive request still asks for the same approvals as with Control+Option.
3. Type accented letters with Right Option (for example Right Option+E, then E) at normal speed for a minute: no listen sound. Note any false start, and how long Option was held.
4. Left Option held, and Left Option plus letters: never a listen sound.
5. Control then Right Option, and Right Option then Control quickly: one Control+Option turn. Right Option held about 0.5 s, then Control: one cancel and no second sound until everything is up.
6. Option-drag a file in Finder with Right Option: report whether the mic opens (risk above).
7. Hands-free:
   - Double-tap Control+Option, then press Right Option: nothing; Control+Option ends it.
   - Double-tap Right Option, then press Control+Option: nothing; Right Option ends it.
8. Settings:
   - Record Left Option as the second key: it works, and Right Option no longer talks.
   - Record the talk key there: refused with the note.
   - Turn it off: Right Option types normally.
   - Set pointing to Right Option: the default second key shows "Pointing uses Right Option" and stops talking.
   - Set Chat to Option-Space: the yield note shows.
9. VoiceOver on, with the fallback landing on Right Option: Right Option talks once, not twice.
10. Tiling on: Right Option still waits 0.25 s, and tiling chords never start a turn.
11. Sleep while holding Right Option, then wake: no stuck turn, and the next press works.
