# Ultron chord plan: Control+Option+Space talks, Chat moves to Control+Option+C

Base 9ffe84e (`<models-dir>/zeus-mdf`). Research was read-only: nothing was built, run or edited.

## 0. Verified facts (file:line)

**Voice key machine and adapter**
- Talk turns run through one reducer, `VoiceKeyMachine`.
  - Readings E, R, S, F: `Sources/ZeusCore/VoiceKeyMachine.swift:116-130`.
  - `begin` is `reading == .exact && !barred`: `:315`.
  - `updateBarred`: `:203-209`.
  - Rows: `:313-385`.
  - `settle` and `readLive`: `:229-302`.
  - A config only "differs" by key, mode or `voiceOverHoldsKey`: `:144-146`.
- `HotkeyMonitor` builds the config at every event (`Sources/Zeus/Voice/HotkeyMonitor.swift:202-211`).
- It drops autorepeat key-downs: `event.isARepeat ? nil` at `:159`.
- `feed` is at `:173-178`.

**Why Space cancels a talk turn today**
- A modifier-only key counts any ordinary key as foreign: `foreignKey = !keysDown.isEmpty || spoiled` (`Sources/ZeusCore/KeyFacts.swift:34`).
- `spoiled` is set by any key-down while modifiers are held (`Sources/ZeusCore/Shortcut.swift:353`).
- It clears only when every modifier is up (`:335`, `:375`).
- So letting go of Space still leaves the press foreign. This has to change, or the chord cannot continue a turn.

**Chat shortcut**
- `ChatHotkey.standard = .controlOptionSpace`: `Sources/ZeusCore/ChatHotkey.swift:13`.
- `.controlOptionC` already exists (`:11`, key code 8).
- `stored(nil)` falls back to the default: `:68-70`.
- `chat.hotkey` is written only by `ChatHotkeyMonitor.set` (`Sources/Zeus/Chat/ChatHotkeyMonitor.swift:28-31`). A stored value therefore means an explicit choice.
- `ChatHotkeySection` (`:58-76`) is never mounted.
- The Shortcuts page (`Sources/Zeus/Settings/GlanceSettingsPages.swift:723-756`) has no Chat row. Today the owner cannot change Chat in Settings at all.

**Carbon hot keys: a bug that already exists**
- Chat registers signature `'ZEUS'` id 1 (`ChatHotkeyMonitor.swift:48`). Its handler ignores which hot key fired and returns `noErr` (`:37-40`).
- `HotKeyCenter` uses the same signature and ids from 1 (`Sources/Zeus/App/ExtraPreferences.swift:244`). Its handler reads only the id (`:258-264`).
- So whichever handler runs first answers every Zeus hot key.
- Any new registration (the talk chord swallow) could therefore open Chat or the agent picker. This must be fixed as part of this work.
- Agent picker and Quick to-do presets offer `.controlOptionSpace` (`ExtraPreferences.swift:9`, `:75-80`).

**Tiling**
- Default keymap binds only Control-Option-Command and that set plus Shift, with arrows, J, T, P, R, [, ], K. No Space (`Sources/ZeusCore/Tiling/TileKeybind.swift:117-136`). The tap does not consume Control+Option+Space by default.
- Bindings must hold Control, Option or Command, so an edited keymap could bind Control+Option+Space.
- `TileBaseConflicts.notes` checks Chat against the keymap (`Sources/ZeusCore/Tiling/TileBaseConflicts.swift:157-161`). There is no check for a talk chord.
- `holdConfirm = 0.15` (`:41`). `confirm(for:)` (`:46-52`) gives Control-Option 0.15 s while the tap is installed (C14).

**Recorder**
- `ShortcutRecorderModel` uses a local `NSEvent` monitor and swallows the events it reads (`Sources/Zeus/Settings/GSShortcutRecorder.swift:22-26`).
- A key with modifiers is captured as a keyed shortcut at key-down (`Shortcut.swift:418-421`).

**Pointing**
- Pointing reads `KeyFacts` and pins Space cancelling a separate pointing hold (`Tests/ZeusCoreTests/PointingKeyGestureTests.swift:30`).
- With shipped defaults pointing equals talk and stands down (`docs/VOICE-KEY.md:16-20`).

**Walk test**
- Up to 16 keys per run, held in `UInt16` masks (`Tests/ZeusCoreTests/VoiceKeyWalkTests.swift:88-117`).
- The state key holds `spoiled: Bool` (`:418`).
- `Phys` and the checker read one fixed `ownMask` (`:254-269`, `:807-835`).
- Runs are at `:129-171`.

**QA ids and features**
- `qa/regressions.json` ends at REG-627 (REG-625 to 627 are the machine work).
- No plan doc claims REG-628 or later.
- The only unclaimed gap is REG-385 to 389.
- Voice key rows bind F11.
- App-test suites have no `native-*` check id, so new REG guards go in ZeusCoreTests (`native-ZeusCoreTests`).

**Settings catalog**
- The talk row is at `scripts/gen-settings-catalog.py:217` (id `voice.talkKey`).
- There is no Chat row.
- `scripts/check-settings-catalog.sh` regenerates and diffs the catalog.

**Unknown, and planned so the answer does not matter**
1. Whether the app's own `NSEvent` monitors see a key-down that its own Carbon hot key matched.
2. Whether the macOS "next input source" shortcut (normally Control+Option+Space) wins over a Carbon registration.
3. Whether Carbon also swallows the matching key-up.

## 1. Architecture

There is still one talk turn and one machine. The chord is not a second shortcut or a second monitor (two machines owning one turn would break I4). It is the bare Control+Option hold, during which Space is allowed.

- **Starting.** The turn always starts on Control+Option exactly as today, so the 0.15 s confirm (C14) applies unchanged.
- **Space joins after Control and Option are down.** It is not foreign: same turn, no second start, no second listen sound.
- **Space down before Control and Option are both down.** It is foreign, so nothing starts until every key is up (I6).
- **Repeats.** The monitors already drop autorepeat. A repeated key-down from any source is idempotent (`keysDown` is a set).
- **No typed space.** Zeus registers a Carbon hot key on Control+Option+Space whose handler does nothing, while the chord is active. Carbon already holds this exact combination for Chat today, so the path is proven. It also takes the press away from other apps and from the input-source shortcut.
- **Not the tiling tap.** The tiling tap could consume the key too, but it is not used. It runs only with tiling on and Accessibility, and part 6 forbids the tap binding Zeus keys. A global monitor cannot consume.
- **Correct either way.** If Carbon hides Space from the monitors, nothing changes and the turn continues. If they see it, Space is allowed and the turn continues. If the registration fails (another app holds it), Space is allowed and Settings says so.

**When the chord is active** (pure, `VoiceKey.talkChord`): all of these must hold.
- The talk key as heard is exactly `.controlOption`.
- Talk is in hold mode, not shared with dictation.
- VoiceOver is off. Control+Option+Space is VoiceOver's own activate key.
- No Carbon shortcut (Chat, agent picker, Quick to-do) is Control+Option+Space.

The machine also honours the chord only for role `.talk` in mode `.hold`. Dictation, the Polyglot key, pointing and the shared gesture are unchanged, and Space stays foreign there.

## 2. Machine changes

**`ShortcutState`**
- `spoiled: Bool` becomes `spoilers: Set<UInt16>`: the codes of keys pressed while a modifier was held, cleared when every modifier is up.
- `spoiled` stays as a computed `!spoilers.isEmpty`, so `isHeld`, pointing and the recorder do not change.

**`KeyFacts`** gains `init(of:key:chord: UInt16? = nil)` and a new fact `chordDown`.
- For a modifier-only key, the chord code is left out of `keysDown` and `spoilers` when working out `foreignKey`.
- With `chord` nil the facts are byte-for-byte today's, so pointing is unaffected.

**`VoiceKeyMachine.Config`** gains `chord: UInt16?`, default nil.
- It is used only when role is `.talk` and mode is `.hold`.
- Like `confirm`, it is stored, not compared: switching it never cancels a hands-free turn. After it is turned off, a Space still down simply reads foreign.

**New reading C, chorded:** `ownDown`, nothing foreign, and `chordDown`.

**Rows of 4.3** (shown as diffs):

| # | Phase | Input | Change |
|---|---|---|---|
| prelude 3 | any | C | New: `barred` becomes true when the phase before the row is not `armed` or `holding` |
| 1 to 4 | idle | C | Not a begin (row 25). Prelude 3 bars it |
| 5c (new) | armed(since, press) | C | Same as E: stay armed. The tick of row 5 reads C as E, so the start comes at `since + confirm` |
| 6, 8 | armed | R, F, S | Unchanged |
| 11c (new) | holding | C | Stay holding. No effect: no start, no send, no wake |
| 14 | holding | tick, reading C | Same as E |
| 9 | holding | R with Space still down | Unchanged. Space is not foreign, so the turn sends, taps or latches as a clean release |
| 16, 19 | tapped(open / not open) | F, S **or C** | C added: cancel if open, else idle |
| 20, 21 | latched | C | Not a begin (row 25), so a hands-free turn is left as it is. Prelude 3 bars the shrink back to E (I6) |
| 22 | spent | R, F, S **or C** | C added: idle |

**Rules** (`docs/VOICE-KEY.md`; part 3 of `docs/VOICE-KEY-MACHINE-PLAN.md`)
- A **clean chord** is Space going down while the talk key's own set is down alone. It stays clean until Space or an own modifier goes up.
- A clean chord's Space is not foreign for I1, I3 and I6. A Space that is not clean is foreign.
- New **I9:** an event that only moves a clean chord's Space gives no `start`, `send` or `cancel`. Effects owed by an overdue timer, settled first, are the only exception.
- New **I8c:** from rest, pressing Control, Option, Space acts as I8.

**The cases you asked about**
| Order | Result |
|---|---|
| Bare Control+Option, then Space joins | Same turn, one start, one listen sound |
| Space first, then Control+Option | Nothing; barred until every key is up |
| Control, Space, Option | Nothing (Space came before the whole set) |
| Space released before the modifiers | Turn continues; releasing a modifier sends |
| A modifier released with Space still down | Clean release: sends, taps or latches |
| Fast chord with tiling on | Armed, then starts after 0.15 s. A chord tap shorter than that does nothing, as the bare key |
| Double-tap the chord | Latches hands-free (the second press begins on Control+Option) |
| Chord to end a hands-free turn | Sends after the confirm, or at the press when confirm is 0 |
| Space-first to end a hands-free turn | Does nothing |
| Control+Option+Space+Command, Shift or another key | Foreign: cancel (holding) or drop (armed) |
| Space typed with nothing held | Reads R: nothing. Carbon never matches it |

**Sixth-pass items #32 and #33**
- **#32:** the plan does not touch `HotkeyMonitor.feed`. It only adds a `chordProvider` read in `config`, so #32 is not folded in. A Space key-down reports Control+Option, already in `flagModifiers`, so `readLive(joinedOnly:)` adds nothing.
- **#33:** not reachable in a new way. Space-first reaches the queue before the modifiers, so no wake can exist yet. Space after the pair turns #33's "start then cancel" into a correct start with no cancel.
- **Note for whoever fixes #33:** a tick that reads `keysStillDown` must pass `chord` to `KeyFacts`. Otherwise a held Space would read foreign.

## 3. Migration (needs your approval)

- `ChatHotkey.standard` becomes `.controlOptionC`. Nothing is written to UserDefaults: no `chat.hotkey` value means Control+Option+C.
- A stored `"controlOptionSpace"` is an explicit choice and is kept. The chord then yields (`talkChord` gives nil):
  - Space stays foreign and cancels the talk turn, as today.
  - Chat keeps the press.
  - Settings shows the clash with a one-click "Move Chat to Control-Option-C".
- Why: the rule matches how talk keys migrate (`docs/VOICE-KEY.md:116-117`, a recorded key is never migrated), it never overwrites a choice, and yielding keeps today's behaviour.
- **Risk on your own Mac:** if your defaults already hold `controlOptionSpace`, the chord stays off until you click Move. On-device check 1 reads it.

## 4. Settings and clash UX

- **Shortcuts page, "Summon Zeus" card.**
  - The Talk row text gains "or Control + Option + Space" while the chord is active.
  - New row "Open the chat window": a `GSPopup` over `ChatHotkey.allCases`, calling `ChatHotkeyMonitor.set`, showing `problem` as today.
- **Clash rule** (pure, `VoiceKey.chatClash(talk:heard:chat:shared:voiceOverOn:holders:)`). It returns a sentence and a fix:
  - Chat is Control+Option+Space while talk is the bare Control+Option: "Control-Option-Space also talks to Zeus. While Chat uses it, it opens Chat instead." Fix: move Chat to Control+Option+C.
  - Chat equals a keyed talk key (for example talk recorded as Control+Option+Space): "This is also your Talk to Zeus key. Chat takes it." Fix: move Chat to C, or turn Chat off when talk is Control+Option+C.
  - The agent picker or Quick to-do preset is Control+Option+Space: the chord yields, and the Talk row names the holder.
- **Resolution: warn and offer, not refuse.** A Carbon choice always beats the chord, so there is exactly one owner and it is decided ahead of time. Refusing would leave a dead menu option and contradict the migration rule. Notes show under both rows; `ShortcutRecorderRow` gains `notes: [String] = []`.
- **Recorder.**
  - `ShortcutRecorderModel.begin` calls a static `pauseGlobalHotkeys(true)` hook and `end()` calls it with false.
  - AppDelegate wires the hook to `ChatHotkeyMonitor.setPaused` and `TalkChordHotkey.setPaused`, which unregister and re-register.
  - Recording Control+Option+Space then works whether or not Carbon hides the key-down from the window. `HotKeyCenter` presets are left alone (out of scope).
- **Registration failure.** If `RegisterEventHotKey` fails for the chord, `TalkChordHotkey.problem` shows: "Another app uses Control-Option-Space. Hold Control + Option alone to talk."

## 5. Files

**Core**
- `Sources/ZeusCore/ChatHotkey.swift`
  - Standard becomes C.
  - `var shortcut: Shortcut?`.
  - `enum CarbonHotkeySignature { chat 'ZCHT', talkChord 'ZTLK', center 'ZEUS' }`, with a pure `owner(signature:)`.
- `Sources/ZeusCore/Shortcut.swift`: `ShortcutState.spoilers`.
- `Sources/ZeusCore/KeyFacts.swift`: `chord`, `chordDown`.
- `Sources/ZeusCore/VoiceKeyMachine.swift`: `Config.chord`, reading C, prelude 3, rows above.
- `Sources/ZeusCore/VoiceKey.swift`:
  - `static let talkChord = Shortcut(keyCode: 49, modifiers: [.control, .option])`
  - `talkChord(heard:shared:voiceOverOn:holders:) -> (chord: Shortcut?, heldBy: String?)`
  - `chatClash(...)`
- `Sources/ZeusCore/Tiling/TileBaseConflicts.swift`: `notes(..., talkChord: Shortcut? = nil)`. A binding on it gives "Control-Option-Space is both your Talk to Zeus chord and a tiling key."
- No new Core file, so `qa/portable-core/prepare.py` does not change.

**App**
- `Sources/Zeus/Voice/HotkeyMonitor.swift`: `var chordProvider: () -> UInt16? = { nil }`, read in `config`.
- `Sources/Zeus/Voice/TalkChordHotkey.swift` (new):
  - `sync(_ chord: Shortcut?)`, idempotent, with a no-op handler that answers only `'ZTLK'`.
  - `setPaused`, `problem`, and an injectable registrar for tests.
- `Sources/Zeus/Chat/ChatHotkeyMonitor.swift`: own signature; handler returns `eventNotHandledErr` for others; `setPaused`.
- `Sources/Zeus/App/ExtraPreferences.swift`: `HotKeyCenter` handler checks `'ZEUS'`, else `eventNotHandledErr`.
- `Sources/Zeus/App/AppDelegate.swift`, beside `:298-318` and `:204`:
  - `hotkey.chordProvider`, which also calls `TalkChordHotkey.sync` as a backstop.
  - Sync at start, after `ChatHotkeyMonitor.set`, `chooseTalkKey`, dictation key or enabled changes, `ExtraPreferences.onShortcutsChange`, and VoiceOver changes (`TilingKeyClash.watchVoiceOver`).
  - The recorder pause hook.
- `Sources/Zeus/Settings/GSShortcutRecorder.swift`: pause hook; `notes` on the row.
- `Sources/Zeus/Settings/GlanceSettingsPages.swift`: Chat row, Talk text and notes.
- `Sources/Zeus/Tiling/TilingKeyClash.swift`: `Keys.talkChord`, passed to `notes`.
- Comments only: `Sources/Zeus/App/VoiceTurnController.swift:208`, `Sources/ZeusCore/Pointing/PointingKeyGesture.swift:9`.

**Tests**
- `Tests/ZeusCoreTests/ChatHotkeyTests.swift`, `KeyFactsTests.swift`, `VoiceKeyMachineTests.swift`, `VoiceKeyWalkTests.swift`, `VoiceKeyTests.swift`, `TileBaseConflictsTests.swift`.
- `Tests/ZeusAppTests/HotkeyMonitorMachineTests.swift`, `TilingKeyClashTests.swift`.
- `Tests/ZeusAppTests/TalkChordHotkeyTests.swift` (new).

**QA and docs**
- `scripts/gen-settings-catalog.py`, `Sources/Zeus/App/SettingsCatalog.swift` (generated), `docs/settings-inventory.md` (generated).
- `qa/regressions.json`, `qa/feature-map.json`.
- `docs/VOICE-KEY.md`, `docs/VOICE-KEY-MACHINE-PLAN.md`, `docs/STATE-MACHINES.md` (voice hold key entry: `Config.chord`), `docs/ULTRON-CHORD-PLAN.md`.

## 6. Commits (tests first; each one builds)

0. **Plan.** Add `docs/ULTRON-CHORD-PLAN.md`.
1. **Red: Chat tests.** Fail at `ChatHotkeyTests`:
   - `aFreshInstallOpensChatOnControlOptionCAndAChoiceIsKept`: `stored(nil) == .controlOptionC`, `stored("controlOptionSpace") == .controlOptionSpace`, standard symbols "⌃⌥C".
   - `eachCarbonHotkeyAnswersOnlyItsOwnSignature`.
2. **Green: Chat.** Standard C, `shortcut`, `CarbonHotkeySignature`. Fix `symbolsAndCodes:7`.
3. **Red: KeyFacts.** Fail at `KeyFactsTests`:
   - `aChordKeyJoiningTheOwnSetIsNotForeign`
   - `aChordKeyWithShiftOrAnotherKeyIsForeign`
   - `aKeyThatSpoiledTheChordStaysForeignAfterItIsUp`
   - `withoutAChordSpaceSpoilsAsBefore`
   - `spoilersClearWhenEveryModifierIsUp`
4. **Green: KeyFacts.** `spoilers` and `KeyFacts(chord:)`. Pointing suites stay green unchanged.
5. **Red: machine and walk.** Add `Config.chord` (stored, not yet read).
   - Unit tests in `VoiceKeyMachineTests`:
     - `aChordJoiningAHeldTalkTurnContinuesIt`
     - `theChordReleasedBeforeTheModifiersKeepsTheTurn`
     - `releasingAModifierWithTheChordKeyDownSends`
     - `aChordPressedFastBesideTilingStartsAfterTheConfirm`
     - `theChordKeyFirstStartsNothingUntilEverythingIsUp`
     - `aChordKeyBeforeTheWholePairIsForeign`
     - `aChordWithCommandCancels`
     - `theChordKeyDuringAnOpenTapCancelsIt`
     - `theChordEndsAHandsFreeTurnOnlyAfterTheConfirm`
     - `aChordKeyFirstNeverEndsAHandsFreeTurn`
     - `aRepeatedChordKeyDownStartsNothingMore`
     - `withoutAChordSpaceStillCancels`
     - `dictationAndSharedKeysIgnoreTheChord`
   - Walk changes:
     - `WalkKey.space` (49) and `WalkRun.chord`.
     - The state key holds `spoilers` in place of `spoiled`.
     - `Checker.chordClean`, set when a Space arrives while `Phys(seen).exactOwn`, cleared when Space or an own modifier goes up. `Phys` leaves out Space while it is clean.
     - The I9 check in `checkEffects` for key and deliver events whose only change is the clean Space.
     - The I8c probe in `restCheck`.
     - Move `.swallowed(i)` for chord runs: Space goes down or up with no event, standing for the Carbon swallow.
     - Restricted key `onlyWith: [.control, .option]` for B and B2.
     - New `theChordOrdersKeepTheRules`, a replay that also asserts the effect log.
     - New `theSearchSeesAMachineThatDoesNotTolerateTheChord`: run A with `run.chord` set and the config's chord nil must report I9.
   - Run changes:
     - **A, A0:** add Space; config chord 49; add `.swallowed`.
     - **C, D, E, E2, G, H, I, F, J:** add Space as a full key, chord nil. Space must stay plain foreign for dictation, shared, a keyed toggle, pointing and Fn.
     - **B, B2:** Space only with Control and Option down, because these are the costly runs.
   - Record states, moves and time per run. Expected growth: about 2 to 3 times for each run with a full Space key (A about 150k to 200k; C about 220k), about 1.3 to 1.5 times for B and B2, and the suite perhaps 10 to 15 minutes under load.
   - Fallback if over budget: give C, D and G the restricted Space too.
6. **Green: machine.** Reading C, prelude 3, rows 5c, 11c, 16, 19, 22. All runs green; record the numbers in part 5.
7. **Red: routing and clashes.**
   - `VoiceKeyTests`: `theChordIsOnlyOnTheBareControlOptionTalkKey` (VoiceOver, shared, Fn, keyed talk, held by Chat, agent picker, Quick to-do), `theChordYieldsToAnExplicitChatChoice`, `theChatClashIsNamedWithItsFix`.
   - `TileBaseConflictsTests`: `aTilingBindingOnTheTalkChordIsNamed`. `theShippedDefaultsClashWithNothing` is unchanged.
8. **Green: routing.** `VoiceKey.talkChord`, `chatClash`, `TileBaseConflicts.notes(talkChord:)`.
9. **Red: adapter.** `HotkeyMonitorMachineTests`:
   - `theTalkChordCallsPressOnceAndReleaseOnce`
   - `theTalkChordWithTheChordOffCancelsAsBefore`
   - `aSpaceTypedAloneCallsNothing`
   - Add `chordProvider`, not yet read.
10. **Green: adapter.** `config` reads it; AppDelegate wires it for talk only.
11. **Red: Carbon and tiling keys.**
    - `TalkChordHotkeyTests`: registers once, unregisters on nil, pause and resume, its handler ignores other signatures.
    - `TilingKeyClashTests`: `Keys.live().talkChord`, and a new `everyCarbonRegistrationHasItsOwnSignature` (scan for `RegisterEventHotKey`).
12. **Green: Carbon.** `TalkChordHotkey`, both handler filters, chat signature and pause, `Keys.talkChord`, AppDelegate sync points and VoiceOver watch.
13. **Settings UI.** Chat row, Talk text, clash notes and the Move button, row `notes`. Covered by commit 7's pure tests plus on-device check 8.
14. **Catalog.**
    - Talk note: "Hold Control + Option, or Control + Option + Space, to talk..."
    - New row `o('shortcuts','Global shortcut','Open the chat window','menu','-','Opens the chat window from any app.','missing','chat.hotkey','choice',['Off','Control-Option-Space','Option-Space','Option-Shift-Space','Command-Shift-Space','Control-Option-C'],'Control-Option-C','custom','Carbon hot key; an explicit choice is kept.')`
    - Regenerate both outputs; `scripts/check-settings-catalog.sh` must be green.
15. **QA records.**
    - `qa/regressions.json`: REG-628 to REG-635 (the next free after 627; confirm through `<models-dir>/zeus-merge-reg.py` at merge). If they are taken, use the unclaimed gap REG-385 to 389, then 396 to 399. All rows use `native-ZeusCoreTests`:

      | Id | Features | Guard |
      |---|---|---|
      | 628 | F11 | `VoiceKeyMachineTests.aChordJoiningAHeldTalkTurnContinuesIt` |
      | 629 | F11 | `theChordKeyFirstStartsNothingUntilEverythingIsUp` |
      | 630 | F11 | `aChordPressedFastBesideTilingStartsAfterTheConfirm` |
      | 631 | F11 | `aChordKeyFirstNeverEndsAHandsFreeTurn` |
      | 632 | F11 | `VoiceKeyTests.theChordIsOnlyOnTheBareControlOptionTalkKey` |
      | 633 | F11, F12 | `ChatHotkeyTests.aFreshInstallOpensChatOnControlOptionCAndAChoiceIsKept` |
      | 634 | F11 | `ChatHotkeyTests.eachCarbonHotkeyAnswersOnlyItsOwnSignature` |
      | 635 | F11 | `TileBaseConflictsTests.aTilingBindingOnTheTalkChordIsNamed` |

    - `qa/feature-map.json`: add obligation `F11.talk-chord`, check `native-ZeusCoreTests`, with those cases plus `VoiceKeyWalkTests.theChordOrdersKeepTheRules`.
16. **Docs.**
    - `docs/VOICE-KEY.md`: "Chords" `:37-41` becomes the chord rules; rules 1 to 8 plus I9; Chat migration; tests and REG list.
    - `docs/VOICE-KEY-MACHINE-PLAN.md`: 4.3 rows, part 3, part 5 runs and numbers, part 6 `:415-418` (the chord now ends a hands-free turn on purpose), a "Seventh pass" note with the #32 and #33 status.
    - `docs/STATE-MACHINES.md`.

**Gates:**
- `swift build`, then ZeusCoreTests and ZeusAppTests with the walk not filtered.
- `scripts/check-settings-catalog.sh`; the qa closed-loop tests.
- Vera PASS at the head SHA before merge.

## 7. Risks

- **Muscle memory.** A habitual Control+Option+Space tap meant for Chat now opens the microphone. A quick tap sends after the 0.4 s gap, the same as a bare quick tap today.
- **Carbon behaviour is not verified** (facts 1 to 3 in section 0). The design is correct either way, but whether a space is typed and whether the input source switches can only be checked on the Mac.
- **Handler fix scope.** Fixing the handlers touches the agent picker, Quick to-do and the answer keys (shared `HotKeyCenter`). Regression risk; on-device check 10.
- **Walk time** may roughly double. The fallback is in commit 5.
- **Scope decisions that need your approval:**
  - The chord exists only on the bare Control+Option talk key, not "talk key + Space" in general. Option+Command+Space is Finder search.
  - The chord is off in shared mode.
  - Chat wins a clash, with an offer to move it.
  - The handler bug fix is folded in.
- **Irreversible actions:** none. No UserDefaults are written by the migration.

## 8. On-device checks (owner only)

1. `defaults read <bundle id> chat.hotkey`: absent means Chat is on Control+Option+C. If it says `controlOptionSpace`, the Settings note shows, and Move works.
2. In TextEdit, with two input sources set up: hold Control+Option, add Space, let Space go, let go. Expect one listen sound, one turn and a spoken answer. No space typed, no input-source switch. Read the log for whether the monitor saw Space, and record the answer in `VOICE-KEY.md`.
3. Tiling on: press the chord fast. It starts about 0.15 s later with one sound. A chord tap shorter than that does nothing.
4. Space held first, then Control+Option: nothing. Let go of everything, then Control+Option works.
5. Type quickly with nothing held: nothing starts. Control+Option then a letter cancels as before.
6. Double-tap the chord: hands-free. A chord press ends it after the confirm. Space-first does not end it.
7. Control+Option+C opens Chat. Control+Option held, then C: the talk turn is cancelled and Chat opens.
8. Settings: record Control+Option+Space as the Talk key (the recorder captures it). The clash note shows and Move works. Choose Chat Control+Option+Space: the note shows and the chord yields.
9. VoiceOver on: Control+Option+Space goes to VoiceOver and Zeus does nothing. VoiceOver off: the chord works again.
10. Agent picker, Quick to-do and the answer keys still fire after the handler fix. Agent picker set to Control+Option+Space: the chord yields and the note shows.
11. If an app such as Raycast or Alfred holds Control+Option+Space: the Settings note shows, and the bare Control+Option still talks.
