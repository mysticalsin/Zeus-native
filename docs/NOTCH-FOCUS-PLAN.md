# Focus name in the notch: plan and design

Written 14 November 2026 against `codex/island-20261113` (HEAD `9f2ffe4`), revised the same day after review. Line
numbers below were read on that commit. Same rules as `docs/NOTCH-SOURCES-PLAN.md` and
`docs/NOTCH-EQUALISER-PLAN.md`: pure rules in ZeusCore with tests first, `docs/DESIGN-DIRECTION.md` for anything
visible, nothing accepted until the named tests run on macOS and the behaviour is seen on a Mac. The owner approved
the route: the name of the active Focus is read from the Focus store files, which needs Full Disk Access. Off by
default; nothing is read until the owner turns it on.

**Refactor first.** Zeus has no Focus state today, only two inline reads of the public status, written twice
(`Sources/Zeus/Routines/RoutineRunner.swift:143-145`, `Sources/Zeus/Proactive/ProactiveController.swift:123-124`). A
third reader bolted beside them would give Zeus two answers to "is a Focus on". Ticket F0 moves both reads behind one
owner and lays down the shared types, with no change in behaviour, before anything else is built. A second small
refactor, F6, makes the closed notch width obey Reduce Motion, which it does not today (see F6).

In this plan "Focus" always means the macOS Focus. Zeus also has a timer tab titled "Focus"
(`Sources/ZeusCore/TopBar/TopBarLayout.swift:23`, wing kind `.focus` at `Sources/Zeus/TopBar/TopBarViews.swift:1349`).
Every new type, file and setting here is named `SystemFocus` so the two never meet in code.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| F0 | One owner for the Focus read (refactor first) | Two inline reads, no state, no shared types | One monitor owns the read; shared values and a `@MainActor` control protocol so later tickets compile apart. Same behaviour |
| F1 | Store rules | None | A pure parse of the two store files into one reading: cleaned name, checked symbol, bounded input |
| F2 | The machine | None | One reducer: route, single-flight reads, change edges, cue limit, hidden details, and the values the views draw |
| F3 | Monitor | Reads only when a card wants to show | Bounded read-only file reads, a watch, a re-check when Zeus becomes active. Runs effects only |
| F4 | Notch surface | No Focus in the notch | A resting wing with the symbol and name, and a short cue when the Focus changes |
| F5 | Settings row | None | One row: the switch, the one reason, a status word, a button to the right pane. Never on by import |
| F6 | Reduce Motion for the closed width (refactor) | The width springs even with Reduce Motion on | The width changes at once with Reduce Motion on, for every wing kind |

Worktrees and order:

| Ticket | Files it owns | Runs |
| --- | --- | --- |
| F0 | new `Sources/ZeusCore/SystemFocus/SystemFocusTypes.swift`, new `Sources/Zeus/SystemFocus/SystemFocusMonitor.swift` (the public read only), `RoutineRunner.swift` (`:143-145`), `ProactiveController.swift` (`:123-124`), new `qa/closed-loop/tests/test_system_focus_lint.py` (one lint), new `Tests/ZeusCoreTests/SystemFocusTypesTests.swift`, this plan copied to `docs/NOTCH-FOCUS-PLAN.md` | First, alone. Does not wait for step zero |
| F1 | new `Sources/ZeusCore/SystemFocus/SystemFocusStore.swift`, new `Tests/ZeusCoreTests/SystemFocusStoreTests.swift` | After F0 and step zero, parallel with F2 |
| F2 | new `Sources/ZeusCore/SystemFocus/SystemFocusMachine.swift`, new `Sources/ZeusCore/SystemFocus/SystemFocusDisplay.swift`, their two test files, `docs/STATE-MACHINES.md` (one entry) | After F0 and step zero, parallel with F1 |
| F3 | `SystemFocusMonitor.swift`, new `Sources/Zeus/SystemFocus/SystemFocusStoreReader.swift`, new `Sources/Zeus/SystemFocus/SystemFocusWatch.swift`, `AppDelegate.swift` (start near `:135-138`, two `onChange` cases near `:884-898`, one line after `:969`, stop at `:88`), `test_system_focus_lint.py` (two lints), new `Tests/ZeusAppTests/SystemFocusMonitorTests.swift`, `qa/feature-map.json` (one native-fixture entry) | After F1 and F2, parallel with F4 and F5; merges first |
| F4 | `TopBarLayout.swift` (`NotchCue`), `TopBarViews.swift` (`ClosedWings`), `TopBarModel.swift` (one stored value, one method), `SnapshotRenderer.swift` (two fixtures), new `Tests/ZeusAppTests/SystemFocusWingTests.swift`; then, in one last commit made after rebasing on merged F3, three wiring lines in `AppDelegate.swift` and its own `qa/feature-map.json` entry | After F2, parallel with F3 and F5; rebases on F3 |
| F5 | new `Sources/Zeus/Settings/GSSystemFocusRow.swift`, `GlanceSettingsPages.swift` (one insertion after `:350`, the text at `:1000`), `scripts/gen-settings-catalog.py` and its two generated outputs, `SettingsStore.swift` (`:255-258`), new `Tests/ZeusAppTests/SystemFocusRowTests.swift` | After F2, parallel with F3 and F4 |
| F6 | `Sources/Zeus/Notch/NotchView.swift` (`:201`, `:300`), new `qa/closed-loop/tests/test_wings_motion_lint.py` | Any time, alone. Does not wait for step zero |

Every branch appends to `qa/regressions.json`. This plan reserves REG-530 to REG-539 (the file ends at REG-409 today);
feature `F13`, as REG-217 uses for the Focus usage string (`qa/regressions.json:2621`). Clashes go through
`<models-dir>/zeus-merge-reg.py`. The settings files are regenerated, never hand-merged. Builds go in
`<models-dir>/<name>-build`, never inside OneDrive. Lints live in this plan's own two files, as
`qa/closed-loop/tests/test_alerts_lint.py` does, so `test_source_lint.py` is not touched.

Files shared with plans in flight, rebased in merge order and never hand-merged: `TopBarViews.swift`,
`TopBarModel.swift`, `TopBarLayout.swift` and `SnapshotRenderer.swift` (sources A1 and A4, drawn notch P2, earbuds E6);
`GlanceSettingsPages.swift`, the generator and `SettingsStore.swift` (A3, P2, E7); `AppDelegate.swift`;
`NotchView.swift` (drawn notch D0, D2, D4). F4 merges before A1 starts or after A4 lands, never beside them, and after
P2 when both are in flight, because its new branch sits directly under the music line P2 rewrites
(`TopBarViews.swift:1362`). Against E6 the order is free: each adds its own arms to `extraWidth`, `cueIcon` and
`cueDetail`; the later one rebases and re-runs the snapshots. F6 merges before D0 starts, or rebases after it.

## Step zero, on the Mac, before F1 to F5 are scheduled

The private study of 13 November 2026 could not read the store from its sandboxed session and found sources that
disagree on whether recent macOS still writes it. Nothing below is built on a guess. In a Terminal that has Full Disk
Access, the owner checks and writes down key paths and yes or no answers only (real Focus names stay on the Mac):

1. `~/Library/DoNotDisturb/DB/` holds `Assertions.json` and `ModeConfigurations.json` on macOS 27.2.
2. Turning a Focus on from Control Center changes `Assertions.json` within a second, the record carries
   `assertionDetailsModeIdentifier`, and that id is a key under `modeConfigurations`. Turning it off empties
   `storeAssertionRecords` or removes the key. Whether the file itself is ever deleted or left empty while no Focus
   is on, and whether it exists on an account that never used a Focus.
3. The same for a Focus started by its schedule, and for one switched on from the phone with sharing across devices.
4. A custom Focus has a `name` and a `symbolImageName` under `mode`, and the symbol name is a system symbol.
5. `ls -li` before and after a change: is the file replaced (new inode) or rewritten in place.
6. From a process without Full Disk Access: the read fails with "Operation not permitted", no prompt appears, and
   whether that process is then listed in the Full Disk Access pane.
7. After the grant, whether a running process can read at once or only after it is reopened; and after the grant is
   taken away, whether a running process is refused at once or only after it is reopened.
8. With the grant given to a development build of Zeus: whether a shell started by Zeus can read a protected file
   (for example the Safari bookmarks file). This says whether the grant also covers the tools Zeus starts.
9. Mirror the display, then let the Mac sleep and wake: does any record appear in `storeAssertionRecords` while
   Control Center shows no Focus, and does it carry a mode id.
10. On one Mac with macOS 14 or 15, if one is at hand: items 1, 2 and 6. Zeus runs from macOS 14.2
    (`Resources/Info.plist:21-22`).

If item 2 fails, F1 to F5 are not built: F0 and F6 stay, and the owner chooses between on or off only and the
supported Focus filter (see "Out of scope"). If item 3 fails for schedules, that gap is an owner decision below.
Items 5 to 9 set the watch, the row sentence, the re-check and the record rule, as marked in F1, F3 and F5. Without
item 10 the feature is checked on macOS 27.2 only and relies on failing closed everywhere else (owner decision 7).

## Open source checked first

| Need | Source | Licence | Use |
| --- | --- | --- | --- |
| The two paths and the key path to the active id and its name | drewkerr's public gist (a JXA Focus reader), read 14 November 2026 | None stated | Facts only. No code. Its schedule guess (reading trigger hours when no record exists) is not taken |
| Schema detail: `symbolImageName`, `tintColorName`, `assertionStartDateTimestamp`; live records sit in `storeAssertionRecords` and ended ones in a separate history list; a record raised by the system has reason `system-state` and still carries a mode id; any detail key may be absent; a missing `Assertions.json` is normal where no Focus was ever used | eugenehp/macos-focus (`src/macos/database.rs` and its test fixture), read 14 November 2026 and again for this revision | MIT declared in `Cargo.toml` and the README; the study found no LICENSE file | Key names and technique only. It also switches a Focus by writing the store: Zeus never writes |
| Watch cadence and gating on Full Disk Access | Ebullioscopic/Atoll | GPL-3.0 | Named by the study as technique. Not read for this plan; no code enters Zeus |
| Public on or off | Apple documentation for `INFocusStatusCenter`, as recorded by the study (not re-read here) | n/a | The public status answers one question, whether this app should stay quiet now. It is nil until authorized and never says which Focus is on |
| File change events | Dispatch documentation: a file system object source on a descriptor opened for events only | n/a | Unverified against the local SDK header in this session; the F3 builder confirms at compile |
| Symbol check | AppKit `NSImage(systemSymbolName:accessibilityDescription:)` gives nil for an unknown name | n/a | Same note: confirmed at compile and by an App test |
| The pane link | Already in Zeus: `Sources/ZeusCore/Permissions/PermissionSweep.swift:65` | n/a | Reused through `PermissionSweep.Item.fullDiskAccess.settingsURL` |

No code is copied, no dependency is added and nothing is bundled, so no licence duty arises. No private call,
framework or symbol is used, so there is nothing to load at run time. The private part is a file layout: every key is
optional in the decoder and a missing one switches the name off.

## Privacy and consent

- Off by default. `systemFocus.showName` joins `SettingsStore.neverEnabledByImport`
  (`Sources/Zeus/App/SettingsStore.swift:255-258`, applied at `:314`) and the `opt_in` tuple in
  `scripts/gen-settings-catalog.py:243-246`, so neither an imported file nor a table edit can turn it on.
- With the switch off Zeus never opens, lists or stats the store, at launch or later, and no read starts after the
  switch goes off (a read already running finishes and its result is dropped). Tests prove zero reader calls.
- Full Disk Access has no prompt and no request call (`PermissionSweep.swift:25-33`). Zeus never asks for it at
  launch, never adds this feature to onboarding or the permission sweep, and opens System Settings only when the
  owner presses the button in the row. The first read happens only after the owner turns the switch on.
- What the grant really covers. macOS gives Full Disk Access to Zeus as an app, and a process Zeus starts is judged
  by that same grant (system behaviour, unverified here; step zero item 8). Zeus starts the Claude CLI
  (`Sources/Zeus/Brain/Providers/ClaudeCLIProvider.swift:65`, `:327`, `PersistentClaudeSession.swift:13`), the browser
  agent (`Sources/Zeus/BrowserAgent/BrowserAgentRunner.swift:317`), MCP tools (`MCPStdioClient.swift:91`) and terminal
  commands (`Sources/Zeus/Terminal/TerminalLauncher.swift:55`); none gives that up (no hit for "disclaim" under
  `Sources/`). So a grant made for a Focus name also lets every agent and tool Zeus runs read Mail, Messages and
  browser data. The mirror already invites the same grant (`Sources/Zeus/Onboarding/OnboardingSteps.swift:266`,
  `GlanceSettingsPages.swift:1000`); this adds a second reason, so the row says it (F5) and decision 6 is owed.
- One grant serves two features. Granting it for the Focus name does not turn on the notification mirror
  (`notifications.mirror`, `Sources/Zeus/TopBar/TodayController.swift:220-225`), which keeps its own switch.
- `ModeConfigurations.json` also holds each Focus's allowed people and apps. Zeus decodes three fields only (the id,
  `mode.name`, `mode.symbolImageName`), drops the bytes as soon as the parse returns, and keeps nothing else. The
  history lists in `Assertions.json` are never decoded.
- The name lives in memory only. It is never written to disk, a log, the flight recorder (cues are recorded by case
  name only, `Sources/Zeus/TopBar/TopBarModel.swift:390-392`), diagnostics, a settings export, a macOS notification
  (`SystemNotificationPayload.forCue` returns nil by default, `Sources/Zeus/App/SystemNotificationService.swift:47-48`),
  the CLI, or any model, voice, chat or agent context.
- While meeting mode is active or "Show project and command details" is off (`MeetingState.hideDetails`,
  `SettingsStore.swift:351`), the notch shows "Focus on" with the plain moon, not the name or its symbol, and a name
  cue still on screen is withdrawn. The machine holds this as state (F2), because `MeetingState.active` is a plain
  static that no view observes (`SettingsStore.swift:339`). Meeting mode is sampled every 2 s
  (`Sources/Zeus/App/AppDelegate.swift:967-969`), so the name can stay up to 2 s after a call or a mirror starts.
- No new window. The notch panels already follow the capture rule (`ZeusWindowSharing.apply`,
  `Sources/Zeus/App/ZeusWindowSharing.swift:29`, reached through `NotchController.swift:122-126`).
- Tests use synthetic JSON with invented names in temporary folders. A lint keeps the store's folder name out of
  `Tests/`, so no test binary ever touches the real store or lands in the Full Disk Access list.

What the owner sees if the system vendor closes the route: the row reads "Not available on this macOS", the notch
shows no Focus wing and no Focus cue, and the morning brief and routine cards still hold during a Focus exactly as
today through the public status. The switch may stay on; Zeus re-checks at launch and when it becomes active, so the
name returns by itself if a later release restores the files. If the vendor stops honouring Full Disk Access for this
folder, the read is refused while Zeus's general access probe still passes, and the row also reads "Not available on
this macOS" instead of sending the owner to grant what is already granted (F3).

## F0. One owner for the Focus read (refactor first)

### Behaviour

No change. The morning brief and routine cards hold while the public status says Zeus should be quiet, as today.
The consent for that status stays where it is (`ProactiveController.swift:67-68`, asked only when the owner turns the
morning brief on, through `SystemAuthorization.requestFocusStatus`, `Sources/Zeus/App/SystemAuthorization.swift:18-22`).

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/SystemFocus/SystemFocusTypes.swift`, all `Sendable` values:

- `SystemFocusMode` (`id: String?`, `name: String?`, `symbol: String?`). `SystemFocusReading`: `unknown`, `off`,
  `on(SystemFocusMode)`.
- `SystemFocusStamp` (inode, size, modification time in seconds and nanoseconds) and `SystemFocusStamps` (one
  optional stamp per store file).
- `SystemFocusStoreRead`: `ok(SystemFocusReading)`, `unchanged`, `denied`, `missing` (the folder is absent),
  `unreadable(Reason)` with `Reason` of `malformed`, `tooLarge`, `notAFile`, `refused` (refused although Full Disk
  Access is granted), `other`.
- `SystemFocusShown`: `none`, `on(label: String, symbol: String)`. `SystemFocusCue` (`label`, `symbol`, `on`).
- `SystemFocusRowStatus`: `off`, `checking`, `allowed`, `needsAccess`, `unavailable`. `SystemFocusSurface` (`shown`,
  `row`) with `snapshotSample`.
- `SystemFocusPublic.quiet(authorized: Bool, isFocused: Bool?) -> Bool`: true only when authorized and `isFocused`
  is true. This is the expression both call sites write today.
- `@MainActor public protocol SystemFocusControlling: AnyObject` with `surface`, `setEnabled(_:)`, `recheck()` and
  `openSettingsPane()`, the same shape as `EqualiserControlling` in the equaliser plan.

App side: new `SystemFocusMonitor` (`@MainActor @Observable`, `shared`) with one method, `quietForCards() -> Bool`,
that reads `INFocusStatusCenter` and applies `SystemFocusPublic.quiet`. `RoutineRunner.showCard` and
`ProactiveController.presentBrief` call it and pass the result to `ProactiveQuiet.allowsCard`
(`Sources/ZeusCore/Proactive.swift:110-112`), which is unchanged. New lint `test_focus_status_has_one_reader`:
`INFocusStatusCenter.default.focusStatus` appears only in `SystemFocus/SystemFocusMonitor.swift`, with a fail-first
sample. The monitor already conforms to `SystemFocusControlling` in F0, with a surface fixed at off and the three
methods empty, so F4 and F5 compile against `SystemFocusMonitor.shared` before F3 fills it in. F0 reads no file.

### Tests first

`Tests/ZeusCoreTests/SystemFocusTypesTests.swift`: `quiet` for authorized and focused, authorized and not, authorized
and nil, not authorized and true; a `@MainActor` fake conforms to `SystemFocusControlling` and compiles (the isolation
mismatch class of TYPE-012). `ProactiveTests` (`Tests/ZeusCoreTests/ProactiveTests.swift:57-59`) pass unchanged.
REG-530 binds the lint.

## F1. Store rules

### Behaviour

- One live record with a known id gives the Focus name and symbol. No live record gives off.
- A live record whose id is missing, unusable or has no configuration, or a configuration file that cannot be
  parsed, still gives on, with no name: the notch then says "Focus on" with the plain moon. A wrong name is never
  shown, and one odd record never turns the feature off.
- A Focus is never guessed from schedule hours. Only a live record counts; the history lists are ignored.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/SystemFocus/SystemFocusStore.swift`:

| Name | Rule |
| --- | --- |
| `SystemFocusStore.maxBytes` | 4 MB per file. Larger input is `unreadable(.tooLarge)` before any decode |
| `SystemFocusStore.parse(assertions: Data, configurations: Data?) -> SystemFocusStoreRead` | Decodes with Foundation, every key optional, unknown keys ignored. The first entry of `data` that carries `storeAssertionRecords` is used. No such key, or an empty list, is `ok(.off)`. Not JSON, a top level that is not an object, or no `data` list is `unreadable(.malformed)` |
| Active record | Chosen among the live records whose `assertionDetails.assertionDetailsModeIdentifier` is a non-empty string of at most 200 characters: the one with the greatest `assertionStartDateTimestamp`; with no timestamps, the first. Records without such an id are skipped. If records exist and none has a usable id, the result is `ok(.on)` with a nil id and no name. The reason key is not read. Step zero item 9 confirms this for records the system raises |
| Mode lookup | `data[0].modeConfigurations[id].mode`. Each mode decodes on its own, so one bad entry never hides the rest. At most 64 modes are examined |
| `SystemFocusText.cleanName(_:)` | Removes control characters, line breaks, the bidirectional controls U+202A to U+202E and U+2066 to U+2069, and zero-width characters, except that the joiner U+200D is kept where it sits between two emoji; collapses spaces; trims; keeps at most 64 grapheme clusters, never cutting inside one. Empty gives nil |
| `SystemFocusText.cleanSymbol(_:)` | 1 to 64 characters, lower-case letters, digits and full stops only, else nil. Whether the system has that symbol is checked in the app (F4) |
| `SystemFocusStore.read(forErrno:at:)` | For the folder: `EPERM` and `EACCES` give `denied`, `ENOENT` gives `missing`, `ENOTDIR` and `ELOOP` give `unreadable(.notAFile)`. For `Assertions.json`: `EPERM` and `EACCES` give `denied`, `ENOENT` gives `ok(.off)` (the folder is there, no Focus was written), `ELOOP` gives `unreadable(.notAFile)`. For `ModeConfigurations.json` every failure means "no configurations", so the name is nil. Anything else is `unreadable(.other)` |

Fail closed: a file that is not the expected shape is `unreadable`, never on. Any doubt about the id or the name is
on without a name. Nothing throws.

### Tests first (`Tests/ZeusCoreTests/SystemFocusStoreTests.swift`)

Synthetic JSON written in the test file, invented names only. One record with a matching mode; an empty list and an
absent key give off; two records pick the later timestamp and, without timestamps, the first; a record with no id
beside a good one picks the good one even when the bad one is later; only records without an id give on with nil
name, never `unreadable`; a system-raised record with an id resolves like any other; records in the history lists
alone give off; an id missing from the configurations gives on with nil name; nil and malformed configurations give
on with nil name; one malformed mode beside a good one; extra keys ignored; a name that is a number gives nil; a
10,000 character name is cut to 64, not rejected; control, bidirectional and zero-width characters removed; a
joined family emoji and a flag survive whole; a joiner between two letters is removed; a 20 character CJK name is
kept; a name of spaces gives nil; symbols `moon.fill` kept and `../x`, `Moon Fill`, empty and 65 characters refused;
input one byte over the cap; not JSON, a top-level list and an empty `data`; a schedule trigger inside its hours
with no record still gives off; every `errno` mapping for each of the three places. REG-531 (hostile content is
cleaned and bounded) and REG-532 (a missing key never yields a wrong name or turns the feature off).

## F2. The machine

### Behaviour

- Switch off: nothing runs. Switch on: one read. Then the store is watched and read again only when it changes.
- One read in flight. A change during a read causes exactly one more read after it.
- The first reading after the switch goes on, after launch, or after access or the route returns is a baseline: no
  cue.
- A cue fires when a Focus turns on, when another replaces it, and when it turns off. At most 3 cues in any 30
  seconds; past that only the resting wing changes, so a flapping store cannot strobe the notch.
- One malformed read while a name is showing keeps the last reading and reads once more a second later (the file
  may be mid-write). A second one in a row is "Not available".
- When details become hidden the name is replaced by "Focus on" in the same step, and a name cue is withdrawn.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/SystemFocus/SystemFocusMachine.swift`:

| Name | Rule |
| --- | --- |
| `State` | `enabled`; `route`: `off`, `checking`, `named`, `needsAccess`, `unavailable(Reason)`; `reading`; `flight`: `idle`, `reading(generation)`, `readingStale(generation)`; `watch`: `none`, `events`, `stat`; `stamps` (of the last finished read); `detailsHidden`; `baselineTaken`; `cueTimes` (the last three); `malformedStreak`; `generation` |
| `Event` | `launched(enabled:detailsHidden:)`, `settingChanged(Bool)`, `detailsHidden(Bool)`, `appBecameActive`, `sessionBecameActive`, `rowAppeared`, `didWake`, `storeChanged`, `statTick`, `readFinished(generation:result:stamps:now:)`, `watchStarted`, `watchFailed`, `openSettingsPressed` |
| `Effect` | `read(generation:after:ifChangedFrom:)`, `cancelRead`, `startWatch`, `stopWatch`, `scheduleStat(after:)`, `cancelStat`, `cue(SystemFocusCue)`, `withdrawCue`, `openPane` |
| `reduce(_:_:) -> (State, [Effect])` | The only place the route changes |
| Off | `settingChanged(false)` from any state: route `off`, reading `unknown`, stamps cleared, generation bumped, effects `cancelRead`, `stopWatch`, `cancelStat` and `withdrawCue`. Every other event while off gives no effect, except that `detailsHidden` is still stored |
| Results | A `readFinished` with an old generation is dropped. `unchanged`: the flight ends (a stale flight still gives its one more read) and nothing else changes. `denied`: `needsAccess`, reading `unknown`, stamps and baseline cleared, `stopWatch`, `cancelStat`. `missing` or `unreadable`: `unavailable`, cleared the same way (after the one retry above). `ok`: `named`, stamps stored, and `startWatch` when the watch is `none`. The first `ok` after `off`, `needsAccess` or `unavailable` is a baseline |
| Re-check | `appBecameActive`, `sessionBecameActive`, `rowAppeared` and `didWake` cause one read in `needsAccess`, `unavailable` and `named` (single flight makes a burst one read), so a grant taken away is noticed without a file change. In `off` they do nothing. `openSettingsPressed` gives `openPane` only in `needsAccess` |
| Changes | `storeChanged` with the flight idle: `read(after: 0.25, ifChangedFrom: nil)`. During a read: `readingStale`, and the finish emits one more read. `watchFailed`: watch `stat`, `scheduleStat(after: 15)`; `statTick` reads with `ifChangedFrom: stamps` and schedules the next |
| Hidden details | `detailsHidden(x)` with the stored value: nothing. A new value is stored; turning true also emits `withdrawCue`. No read. Cues built while hidden carry "Focus on" or "Focus off" only |
| `SystemFocusEdge.between(_:_:)` | `turnedOn`, `replaced`, `turnedOff` or nil. Same id and same name is nil |
| `SystemFocusCueLimit.allows(times:now:)` | False when three cues fall inside the last 30 s |

New file `Sources/ZeusCore/SystemFocus/SystemFocusDisplay.swift`:

- `surface(for: State) -> SystemFocusSurface`. `shown` is `on` only in `named` with a reading of `on`; the label is
  the cleaned name, or "Focus on" without one or while `detailsHidden`; the symbol is the cleaned symbol, or
  `moon.fill` without one or while `detailsHidden`.
- `cue(for edge:, hidden:)`: on and replaced give the label and symbol above; off gives "Focus off" with `moon`.
- `rowWord(_:)` and `rowSymbol(_:)`: "Allowed" with `checkmark.circle.fill` (true whether or not a Focus is on);
  "Not allowed" and "Not available on this macOS" with `exclamationmark.circle`; nothing for `off` and `checking`.
- `accessibilityLabel(_:)`: "Focus on, Work", "Focus on", "Focus off". The label is never cut here: width is the
  view's job (F4).

Fail closed: `unknown` never draws. A stale read never lands. Off stops every effect, pending reads included, in one
step.

### Tests first

`Tests/ZeusCoreTests/SystemFocusMachineTests.swift`: off ignores every event; on gives one read; a stale generation
is dropped; `denied`, `missing` and `unreadable` each reach their route and stop the watch; one malformed read keeps
the reading and retries once, two reach `unavailable`; a burst of `storeChanged` gives one read; a change during a
read gives exactly one more; `unchanged` ends the flight, keeps the reading, gives no cue, and after a stale flight
still gives one more read; the baseline gives no cue after switch-on, after launch, after `needsAccess` and after
`unavailable`; on, replaced and off each give one cue; the fourth cue inside 30 s is withheld while `reading` still
updates; each re-check event reads once in `named`, `needsAccess` and `unavailable` and never in `off`; `named` plus
`appBecameActive` plus `denied` reaches `needsAccess` with no reading; `openSettingsPressed` outside `needsAccess`
gives nothing; `watchFailed` falls back to stat ticks that carry the stamps; switching off from every state emits
`cancelRead`, stops the watch and bumps the generation; a name showing, then `detailsHidden(true)`, gives a surface
of "Focus on" with the moon and one `withdrawCue`, and `detailsHidden(false)` brings the name back with no cue.
`Tests/ZeusCoreTests/SystemFocusDisplayTests.swift`: every surface, label, cue, word and symbol, both values of
`detailsHidden`, a CJK name and an emoji name passed through whole, and no string holding U+2014 or U+2013 (the app
lint covers only `Sources/Zeus`, `qa/closed-loop/tests/test_source_lint.py:126-132`). REG-533 (a stale read cannot
overwrite a newer state; no read starts after off) and REG-534 (no baseline cue, the cue limit, and the name masked
in the step details become hidden). `docs/STATE-MACHINES.md` gains an entry marked explicit from the start.

## F3. Monitor

### Behaviour

- Starts with the top bar services (`Sources/Zeus/App/AppDelegate.swift:135-138`), so never under `--qa-startup`,
  and sends `launched`. The switch sends `settingChanged` through a new `onChange` case (`:884-898`).
- `NSApplication.didBecomeActiveNotification` sends `appBecameActive` (observer with `queue: .main` and
  `MainActor.assumeIsolated`, as `Sources/Zeus/Notch/NotchController.swift:78-82`). Zeus is an agent app
  (`Resources/Info.plist:23-24`), so this fires when the owner comes back to the Settings window after System
  Settings. `NSWorkspace.didWakeNotification` sends `didWake`, and `NSWorkspace.sessionDidBecomeActiveNotification`
  sends `sessionBecameActive` (unlock and the return from fast user switching, as `ProactiveController.swift:44`).
- Hidden details reach the machine two ways: one line after the 2 s meeting check (`AppDelegate.swift:969`) sends
  `detailsHidden(MeetingState.hideDetails)`, and a `privacy.details` case in `onChange` sends it at once.
- It holds one `State`, applies effects, and publishes `SystemFocusDisplay.surface`. It decides nothing itself.

### App side

| File | Notes |
| --- | --- |
| `SystemFocusStoreReader.swift` | A `Sendable` struct with no stored state: an injected folder and an injected access probe. `static func live()` in this file builds the real folder and passes `OnboardingServices.hasFullDiskAccess` (`Sources/Zeus/Onboarding/OnboardingServices.swift:228`), so the folder name stays in this file. `read(ifChangedFrom:) -> (SystemFocusStoreRead, SystemFocusStamps?)` runs on a utility queue, never on the main actor and never from a view body (the hang recorded at `Sources/Zeus/App/FolderAccess.swift:45-56`). It opens the folder read-only as a directory with no-follow, then each file relative to that descriptor with no-follow, non-blocking and close-on-exec; `fstat` must show a regular file no larger than `maxBytes` and gives the stamp. Equal stamps return `unchanged` without reading. Otherwise it reads in a loop until end of file, up to `maxBytes` plus one byte, and crossing the cap is `tooLarge`. `errno` goes through `SystemFocusStore.read(forErrno:at:)`. On `denied` it calls the probe once: a probe that passes turns the result into `unreadable(.refused)`. The bytes go straight to `SystemFocusStore.parse` and are released |
| `SystemFocusWatch.swift` | Two event-only descriptors, the folder and `Assertions.json`, each with a file system object source for write, extend, rename, delete and link; `static func live()` here too. A folder source does not report an in-place rewrite of a file, which is why both are kept. Handlers are built in a `nonisolated static` function, carry no actor isolation, and hop to the main actor with no payload. After a rename or delete, or when the file first appears, the file source is rebuilt. With no file yet, the folder source alone runs. If a source cannot be made it reports `watchFailed` |
| `SystemFocusMonitor.swift` | Conforms to `SystemFocusControlling`. Holds one cancellable delayed read: `cancelRead` cancels it, and the effect's generation is compared with the state on the main actor right before the reader is called. Delays go through an injected sleeper so tests do not wait. `openSettingsPane()` opens `PermissionSweep.Item.fullDiskAccess.settingsURL` and nothing else. `onSurface`, `onCue` and `onWithdrawCue` closures carry values to the top bar model (wired by F4). Under `TopBarStyle.isSnapshot` it publishes `snapshotSample` and never starts |
| `AppDelegate.swift` | Start (calls the two `live()` factories), the two `onChange` cases, the meeting line, and `applicationWillTerminate` (`:88`) stops the watch |

Lints in `test_system_focus_lint.py`, each with a fail-first sample: `test_focus_store_path_has_one_owner` (the
folder name appears in `Sources/` only in `SystemFocus/SystemFocusStoreReader.swift` and
`SystemFocus/SystemFocusWatch.swift`, and never in `Tests/`); `test_focus_store_is_read_only` (those two files name
no write flag, no `FileManager` create, move, copy or remove call and no `write(`).

Fail closed: a refused read is `needsAccess` with no retry loop; the next attempt waits for the row, activation,
unlock, wake or relaunch. A missing folder, a link in place of a file, an oversized or malformed file, or a refusal
while the general probe passes is "Not available". A folder with no `Assertions.json` is off, with the folder still
watched. A watch that cannot start falls back to a 15 s stamp check. With the switch off there are no descriptors,
no sources and no timer.

### Tests first (`Tests/ZeusAppTests/SystemFocusMonitorTests.swift`, `@MainActor`, serialized)

With a fake reader, a fake watch and a fake sleeper: switch off at launch makes zero reader calls; switch on reads
once and starts the watch; `storeChanged` then `settingChanged(false)` before the 0.25 s delay ends makes zero
further reader calls; `denied` publishes `needsAccess` and stops the watch; activation in `needsAccess` reads again
and a grant publishes the name with no cue; activation in `named` reads once and a `denied` clears the wing; a
change publishes the new label and one cue; hidden details publish "Focus on" and call `onWithdrawCue`; switching
off clears the surface. Reader tests in a temporary folder: two regular files parse; a folder with no
`Assertions.json` gives off and no folder gives `missing`; a symbolic link as the file is refused; a named pipe
returns without hanging; a file over the cap is refused; a file read in one-byte chunks parses whole; equal stamps
return `unchanged` and a rewrite of the same size a moment later is read again; an unreadable folder gives `denied`
with a failing probe and `unreadable(.refused)` with a passing one. REG-535 (path owner and read-only lints) and
REG-536 (a refusal never loops). One native-fixture entry in `qa/feature-map.json`.

## F4. Notch surface

### Behaviour

- Resting wing: while a Focus is on and nothing more important holds the closed notch, the left wing shows the
  Focus symbol and the right wing its name. It sits below music and above the idle mascot in `ClosedWings.kind`
  (after `Sources/Zeus/TopBar/TopBarViews.swift:1362`, before `:1363`). The timer wing (`:1361`) wins over it.
- Cue on change, 2.5 s, no sound:

| Change | Symbol | Text |
| --- | --- | --- |
| A Focus turns on | Its symbol, else `moon.fill` | Its name, else "Focus on" |
| Another Focus replaces it | The new symbol | The new name |
| The Focus turns off | `moon` | "Focus off" |

- The cue follows the existing "short cues" switch (`topBar.cues`, `TopBarModel.swift:112-114`); it is not in the
  essential list (`:365-368`). With cues off the wing still changes.

### App side

- `NotchCue` (`Sources/ZeusCore/TopBar/TopBarLayout.swift:231`) gains `systemFocus(label: String, symbol: String,
  on: Bool)`, with duration 2.5 in the switch at `:258-274`.
- `ClosedWings`: a `systemFocus` kind; the cue joins the 150 point text group (`TopBarViews.swift:1472`); the
  exhaustive `cueIcon` (`:1494-1513`) and `cueDetail` (`:1520-1561`) each gain one case. The resting wing adds 30
  points (`extraWidth`, `:1468-1489`), which gives the name a fixed 78 point frame (`:1462`), to be judged on the Mac.
- The symbol is drawn only if `NSImage(systemSymbolName:)` finds it, else `moon.fill`. The name is drawn with
  `Text(verbatim:)`, so it is never read as a format or a localisation key, on one line with tail truncation. Width
  is held by the frame, not by counting characters, so wide scripts and emoji cannot overflow the wing.
- `TopBarModel` gains `var systemFocus: SystemFocusShown = .none` and `withdrawSystemFocusCue()`, which clears the
  current cue only when it is a `systemFocus` case and cancels its timer (`:379-386`). After F3 merges, three lines
  in `AppDelegate` set the value from `onSurface`, call `show(.systemFocus(...))` from `onCue` and the new method
  from `onWithdrawCue`.

### Design

One line, `TopBarStyle.label(10.5, .semibold)`, `Theme.cloudSecondary` at rest and `Theme.cloudPrimary` in the cue.
The symbol and the word together carry the state; colour carries nothing, and the Focus tint is not read. Each wing
pair is one accessibility element with the label from `SystemFocusDisplay.accessibilityLabel`. No announcement is
posted. F4 adds no transition of its own: the wing arrives through the existing width spring. That spring is applied
with no Reduce Motion check (`Sources/Zeus/Notch/NotchView.swift:201`, `:300`, unlike `:208` and `:217`), so today
every Focus change would spring the closed width with Reduce Motion on, against `docs/DESIGN-DIRECTION.md:11`. F6
closes that for every wing kind, and the Reduce Motion owner check waits for it. Two `SnapshotRenderer` fixtures
beside `:873-876`: the resting wing and the on cue.

Fail closed: `none` draws nothing. An unknown symbol becomes the moon. A missing name becomes "Focus on".

### Tests first

Labels and cue text are pure and covered in F2. `Tests/ZeusAppTests/SystemFocusWingTests.swift`: a model with
`systemFocus` set and nothing else gives the `systemFocus` kind and the 30 point width; with the timer running the
timer kind wins; `TopBarModel.cueName(.systemFocus(...))` is `systemFocus` with no label in it;
`SystemNotificationPayload.forCue(.systemFocus(...))` is nil; an invented symbol name resolves to the moon;
`withdrawSystemFocusCue()` clears a Focus cue and leaves any other cue alone. REG-537 binds the last four.
`ClosedWings.kind` reads shared controllers (`:1352-1363`), so the first test is listed as a native fixture, in F4's
own `qa/feature-map.json` entry, and its result is owed from a Mac.

## F5. Settings row

### Behaviour

- One row in Settings, Appearance, "Small moments, softly signaled", after the screenshot row
  (`Sources/Zeus/Settings/GlanceSettingsPages.swift:350`), in the manner of the folder rows at `:1246` and `:1278`.
- Title "Show the Focus name in the notch". Text, always the same sentence, the one reason and what it costs:
  "Reading which Focus is on needs Full Disk Access, which also covers the agents and tools Zeus runs." It is
  visible before the switch is touched. If step zero item 8 shows started tools are not covered, the sentence ends
  at "Full Disk Access."
- Trailing, left to right: the status word with its symbol (only while on), the button "Open System Settings" (only
  in `needsAccess`), the switch (always). The sentence gives the reason and the word gives the state, so nothing is
  said twice.

| Status | Word and symbol | Button |
| --- | --- | --- |
| `off`, `checking` | none | none |
| `allowed` | "Allowed", `checkmark.circle.fill` | none |
| `needsAccess` | "Not allowed", `exclamationmark.circle` | "Open System Settings" |
| `unavailable` | "Not available on this macOS", `exclamationmark.circle` | none |

- The row sends `rowAppeared` when it appears. Coming back from System Settings sends `appBecameActive` (F3). If
  step zero item 7 shows the grant needs a reopen, macOS offers that itself and the row reads "Allowed" after it;
  Zeus already tells the owner the same for the mirror (`Sources/Zeus/TopBar/TodayPages.swift:294-297`).
- If step zero item 6 shows Zeus is not listed in the pane after a refused read, the button reads "Add Zeus in
  System Settings". No second label is added.
- The Permissions page row (`GlanceSettingsPages.swift:1000`) and the catalog note for `perm.fullDisk`
  (`scripts/gen-settings-catalog.py:149`) both read "Notifications from other apps and the Focus name. Optional."
  The catalog's last cell for that row becomes "Needed only for the notification mirror and the Focus name."

### Design

`GSRow` with `GSStatus` and `GSButtonStyle` as the rows around it; `GSStatus` already pairs a word with a symbol
(`Sources/Zeus/Settings/GlanceSettingsStyle.swift:400-411`). The button's accessibility label is "Open Full Disk
Access settings". The row draws `SystemFocusControlling.surface.row` and holds no state. In a snapshot it shows
`snapshotSample` and never touches the monitor.

### Tests first (`Tests/ZeusAppTests/SystemFocusRowTests.swift`)

Against a `@MainActor` fake `SystemFocusControlling`: the switch calls `setEnabled`; the button exists only in
`needsAccess` and calls `openSettingsPane`; appearing calls `recheck`; each status draws its word; a snapshot makes
no call. An import test: a settings file with `systemFocus.showName` true leaves it off, and one with false turns it
off (no import test exists today: `importJSON` has no hit under `Tests/`). The generator refuses a table where the
row is not a false-default toggle. REG-538.

## F6. Reduce Motion for the closed width (refactor)

### Behaviour and app side

With Reduce Motion on, the closed notch changes width at once when a wing arrives or leaves, for music, the timer,
a cue and the Focus wing alike. With it off nothing changes. `NotchView.swift:201` and `:300` apply
`Self.wingsSpring` unguarded; both become `Motion.reduced ? nil : Self.wingsSpring`, the form already used at
`:208`. No per-kind guard is added: one rule for the closed width. The level cue's own `withAnimation`
(`Sources/Zeus/TopBar/TopBarModel.swift:430-433`) is not touched; the owner check says whether it still moves.

### Tests first

New `qa/closed-loop/tests/test_wings_motion_lint.py`, with a fail-first sample: every `.animation(` in
`NotchView.swift` that names `wingsSpring` also names `Motion.reduced` on the same line. REG-539. On the Mac, with
Reduce Motion on: start and stop music, and turn a Focus on and off; the width steps, it does not spring.

## Settings rows

| Id | Where | Control | Default | Ticket |
| --- | --- | --- | --- | --- |
| `systemFocus.showName` | Catalog section `appearance`, group "Everyday lights", after the screenshot row (`scripts/gen-settings-catalog.py:85`); on the page, the card "Small moments, softly signaled" | Toggle "Show the Focus name in the notch". Note: the row sentence in F5 | Off, opt-in, never enabled by import | F5 |
| `perm.fullDisk` | Permissions, Access status | Note only: "Notifications from other apps and the Focus name. Optional." | Unchanged | F5 |

Rows go in `scripts/gen-settings-catalog.py`; regenerate `SettingsCatalog.swift` and `docs/settings-inventory.md`,
never hand-edit; `scripts/check-settings-catalog.sh` passes. The id avoids `focus.` because `notify.focus` is the
timer (`Sources/Zeus/App/ExtraPreferences.swift:59`).

## Security: how this could be abused, and how each way is closed

| Abuse | Closed by |
| --- | --- |
| A settings file turns the feature on where Full Disk Access is already granted | `neverEnabledByImport` and the `opt_in` tuple (F5), with a test |
| Another program of the same user writes Zeus's defaults to turn it on | Not preventable for any Zeus switch. The effect is bounded: a local read-only read, a name in the notch, nothing stored or sent |
| An agent or tool started by Zeus uses the grant to read mail, messages or browser data | Not closed by this plan. Said in the row before the owner grants; decision 6; the review check below keeps this wave from adding any new launch or tool |
| A program with Full Disk Access plants a hostile name (very long, control or direction-flipping characters, text shaped like a format string) | `cleanName`, the 64 cluster cut, the fixed frame, `Text(verbatim:)`; REG-531 |
| A planted symbol name | The character rule, then the system lookup; anything else is the moon |
| A huge, growing or deeply nested file | The cap checked at `fstat` and again in the read loop; a decoder failure is `malformed`; work runs off the main actor |
| A link, pipe or device in place of a file, or the folder swapped during a read | No-follow, non-blocking opens relative to one folder descriptor, and the regular-file check (F3), with tests |
| A store rewritten in a loop to strobe the notch or burn CPU | 250 ms coalescing, single flight, the cue limit (F2) |
| The name leaking to a recording, a share, a log or a model | Hidden details are machine state and withdraw the cue; the capture rule on the notch panels; case-name-only recording; no model path reads `TopBarModel.systemFocus` (review check) |
| Zeus changing the owner's Focus | Zeus never writes the store: the read-only lint (F3) |
| A voice or agent action turning the switch on | No file under `Sources/Zeus/Intent`, `Voice`, `Agents` or `Chrome` writes a setting (grep for `store.set(` on `9f2ffe4`); the reviewer repeats the grep on the merged branch |

No network peer and no device name reaches this feature.

## Repo hazards that apply

- Swift 6: a block written inside a `@MainActor` type inherits its isolation and traps when the system calls it
  elsewhere. Watch handlers come from `nonisolated static` functions; notification observers use `queue: .main` with
  `MainActor.assumeIsolated`; detached reads capture `Sendable` values only (TYPE-001, TYPE-005).
- Never probe a protected path from a view body or on the main actor (`FolderAccess.swift:45-56`).
- Three places already test Full Disk Access with three different probes
  (`Sources/Zeus/Onboarding/OnboardingServices.swift:228-232`, `SettingsStore.swift:449-451`,
  `Sources/ZeusCore/TopBar/NotificationMirror.swift:56`), so the Permissions page can say "Allowed" while another row
  disagrees. This feature adds no fourth probe: its status is its own read, and on a refusal it asks the first of
  those three once (F3). The three are otherwise left alone; giving them one owner is named under "Out of scope".
- `cueIcon` and `cueDetail` are exhaustive switches; a new `NotchCue` case fails the build until both are updated.
- The em dash lint covers `Sources/Zeus`; Core strings are covered by the F2 test. The settings generator, REG ids
  and the ten-view builder limit noted at `GlanceSettingsPages.swift:371` apply. No semaphore or group waits.
- Sandboxes cannot compile Swift (TYPE-012): budget a Mac build for every ticket.

## Out of scope

- The supported Focus filter (`SetFocusFilterIntent`): it tells Zeus only about a Focus the owner attached the
  filter to, never the name of any other. Kept as the fallback if step zero fails.
- Guessing a Focus from schedule hours, places or apps when no record exists.
- Showing a plain "Focus on" wing from the public status alone: it has no change event, so it would need polling.
- The Focus tint, a Home card, switching a Focus from Zeus, and per-Focus rules for other cues.
- Any lock screen use. A lock screen is seen by anyone in the room without signing in, so a later plan that wants a
  Focus line there needs its own opt-in switch and shows "Focus on" only, never the name or its symbol.
- Starting agents and tools so that they do not inherit Zeus's Full Disk Access. No public launch option for that is
  known to this plan, so it needs its own study and plan (decision 6).
- One owner for the Full Disk Access status behind the Permissions page, onboarding and the mirror.
- Extracting `ClosedWings.kind` into a pure rule. F4 adds one branch to the existing chain.

## Decisions the owner owes

1. Step zero results, and whether to build F1 to F5 on them.
2. Resting wing: symbol and name (planned) or symbol only, with the name in the cue.
3. Cards during a Focus: keep today's public rule (planned), or also hold the morning brief and routine cards when
   the store says a Focus is on. The second ignores a Focus that allows Zeus, but covers the one unanswered report
   in the study that the public status stays false on macOS 27 without a communication entitlement.
4. If a scheduled Focus leaves no record: show nothing for it (planned) or accept a guess from its hours.
5. The timer tab is also titled "Focus". Keep it (planned, the symbols differ) or rename it "Timer".
6. The grant also covers every agent and tool Zeus starts. Build with the row saying so (planned); or hold F3 to F5
   until started tools no longer inherit the grant; or keep on or off only. Facts: "Privacy and consent", item 8.
7. Versions: offer the row on every macOS Zeus supports and rely on failing closed (planned), or show it only on
   versions checked in step zero.

Nothing is bundled, so no licence duty is owed.

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the ticket's new names).
2. `swift build --build-tests`, then `swift test --filter` for `SystemFocusTypesTests`, `SystemFocusStoreTests`,
   `SystemFocusMachineTests`, `SystemFocusDisplayTests`, `SystemFocusMonitorTests`, `SystemFocusWingTests`,
   `SystemFocusRowTests`, and the pinned `ProactiveTests`, `PermissionSweepTests`, `SystemNotificationServiceTests`.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared.
4. `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py'`, the settings generator and its check,
   `./tools/check.sh` development mode from a worktree under `<models-dir>`.
5. An independent review of each diff, reading the open flags, the size cap, the handler isolation and every place
   the name travels, and checking that the wave adds no `Process` launch, no tool and no agent path.
6. Still owed on a real Mac by the owner:
   - Step zero, all ten items (item 10 only if an older Mac is at hand).
   - Switch off at a fresh launch: no access to the store (`fs_usage` filtered on the Zeus process shows none).
     Switch on, change the Focus, switch off at once: no access after the switch.
   - Switch on without the grant: no prompt appears, the row reads "Not allowed", the button opens the Full Disk
     Access pane, and coming back to Zeus re-checks without a click.
   - With the grant: the name and symbol of each built-in Focus and one custom Focus, on, replaced and off, within
     about a second; no cue at launch; the resting wing under music, the timer and a recording; a long, a CJK and an
     emoji name stay inside the wing.
   - A Focus started by schedule and one from the phone: shown, or the gap confirmed.
   - A name showing, then a call or display mirroring starts: "Focus on" within about 2 s, and a name cue goes. The
     details switch does the same at once. A screen share with Zeus hidden shows no wing.
   - Taking the grant away while a name shows, then coming back to Zeus: the wing goes and the row reads "Not
     allowed" (after a reopen, if step zero item 7 says a running process keeps its access).
   - Lock and unlock, fast user switching and back, and plugging in a second display while a Focus is on: the wing
     is right afterwards and no cue fires for an unchanged Focus.
   - VoiceOver reads the wing and the row status. Reduce Motion, after F6: the width steps for music and the Focus.
   - Idle cost with the switch on and no Focus change: `<pid>` is `the Zeus process id`. `PID="<pid>" SECONDS_IDLE=60 scripts/check-perf-budget.sh`.
   - The morning brief still holds during a Focus as before F0.

What was verified for this plan and how: every `file:line` above by reading `9f2ffe4`; the two paths, the key path
and the schedule guess by reading the gist; `symbolImageName`, `tintColorName`, the timestamp key, the live and
history lists, the reason values, the missing-file case and the declared MIT licence by reading the named file and
`Cargo.toml`; the public status semantics from the study, not re-read; the unguarded width spring, the unobserved
meeting state and the launch sites by reading the code. Unverified: that macOS 27.2 still writes the store, that
Full Disk Access is what gates it, how the file is replaced, that started processes share the grant, whether a grant
taken away bites a running process, the Dispatch and AppKit interfaces against the local SDK, and the activation
notification for an agent app. Each has an owner check or a builder check above.

## Review notes

All 19 review findings were checked against the code, the study and the prior art, and all were confirmed in whole
or in part. Main changes: hidden details are machine state with an event and a cue withdrawal; switching off cancels
a pending read; activation, unlock and the row re-check in `named`; a live record without a usable id gives "Focus
on" and never fails the read; a missing `Assertions.json` in a present folder is off; the row and decision 6 say
the grant covers the agents and tools Zeus starts; ticket F6 for Reduce Motion; read stamps live in the machine,
with an `unchanged` rule; the reader loops to end of file and opens relative to one folder descriptor; `live()`
factories; row words "Allowed" and "Not allowed"; a refusal with general access passing is "Not available"; recovery
as a baseline; the lock screen rule; F4's feature-map entry and the merge order against the sources, drawn notch
and earbuds plans; one `perm.fullDisk` note and the catalog group; joiners kept inside emoji and width by frame;
step zero items 7 to 10; the public status row reworded. REG-539 now belongs to F6, so no id is spare.

Rejected or narrowed:

- Masking at draw time in `ClosedWings`: `MeetingState.active` is not observed, so a still wing would keep the name
  until something else redrew it. The event route was taken instead.
- The premise that the system-raised record may lack a mode id: the prior art fixture shows it with one, in the
  history list. The rule was still changed, because that source also says any detail key can be absent.
- A confirmation before the pane opens: a second surface for one fact. The row sentence carries it.
- A Reduce Motion guard for the Focus kind only: a per-kind guard is a bolt-on. F6 guards the width for all kinds.
- Planning the launch change for started tools here: it needs an interface this plan could not verify, so it sits
  under "Out of scope" and decision 6.
