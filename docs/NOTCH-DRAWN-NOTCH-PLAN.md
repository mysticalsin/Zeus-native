# Drawn notch and collapse on pause: plan and design

Written 14 November 2026 against `codex/island-20261113` at `9f2ffe4`. Fourth notch wave, after
`docs/NOTCH-MUSIC-PLAN.md`, `docs/NOTCH-SURFACE-PLAN.md`, `docs/NOTCH-SOURCES-PLAN.md` and
`docs/NOTCH-EQUALISER-PLAN.md`. S1 (open on click) and S2 (rounded corners) are already in this branch; nothing here
redoes them. Same rules: pure rules in ZeusCore with tests first, `docs/DESIGN-DIRECTION.md` for anything visible,
nothing accepted until the named tests run on macOS and the behaviour is seen on a Mac. Public AppKit and SwiftUI
only, no new permission, no new window, no dependency. Every line number below was read on `9f2ffe4`.

**Refactor first: yes.** Today the closed shape is a `CGSize` whose zero value means "no notch" plus a `slimPill`
Bool, read on 22 lines of `NotchView` and 7 of `NotchController`, with three different rules for "this display has
a notch" and three different rectangles for a display without one. A third shape added as one more flag would be the
bolt-on this repo forbids. Ticket D0 replaces the pair with one value and changes no behaviour. D1 to D4 build on it.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| D0 | One closed-shape value (refactor) | A size, a Bool, three notch rules, three rectangles | One `NotchFootprint` per display; same pixels, same zones |
| D1 | Drawn shape rules and calibration | None | Pure limits, a per-display fit, a calibration reducer, the `drawn` footprint |
| D2 | Drawn shape on the notch | A 96 by 9 pt pill on every display without a notch | The owner's shape when chosen, live while calibrating, with zones equal to the drawing |
| D3 | Settings card | A sentence about the pill | "Displays without a notch": Shape, Calibrate, Width, Height; every way out of Settings ends calibration |
| D4 | Place | Always the top centre | A sideways position for the drawn shape; every zone and the open panel follow |
| P1 | Pause hold rules | None | A pure reducer: wings collapse at once, after a delay, or never |
| P2 | Pause hold on the notch | Wings vanish the moment a pause arrives | The setting decides; one value feeds the music wings, their width and their hover zone |

## Order, worktrees and files

D0 and P1 start at once, in parallel. D1 follows D0. P2 follows P1. D2 and D3 run in parallel after D1 and merge
D3 first. D4 is last.

| Ticket | Worktree | Files it owns | Parallel with | After |
| --- | --- | --- | --- | --- |
| D0 | `codex/notch-footprint-YYYYMMDD` | new `Sources/ZeusCore/TopBar/NotchFootprint.swift`, new `Tests/ZeusCoreTests/NotchFootprintTests.swift`, `Sources/Zeus/Notch/NotchView.swift`, `Sources/Zeus/Notch/NotchController.swift`, `Sources/Zeus/App/SnapshotRenderer.swift` (`NotchStage`, `:1010-1023`), `Sources/ZeusCore/AgentHubRules.swift` (`:146`), `Tests/ZeusCoreTests/AgentHubTests.swift` (`:273` and one new case in `DisplaySelectionTests`) | P1 | base |
| D1 | `codex/notch-drawn-rules-YYYYMMDD` | new `Sources/ZeusCore/TopBar/DrawnNotch.swift`, `NotchFootprint.swift` (the `drawn` case), new `DrawnNotchTests.swift` and `DrawnNotchCalibrationTests.swift`, additions to `NotchFootprintTests.swift`, `docs/STATE-MACHINES.md` | P1, P2 | D0 |
| D2 | `codex/notch-drawn-surface-YYYYMMDD` | new `Sources/Zeus/Notch/DrawnNotchModel.swift`, `NotchView.swift`, `NotchController.swift`, `SnapshotRenderer.swift` (`NotchStage` and three new fixtures), `AppDelegate.swift` (the model's `start()` and one wiring line at `:820`), new `Tests/ZeusAppTests/DrawnNotchModelTests.swift`, new `qa/closed-loop/tests/test_drawn_notch_lint.py`, `qa/feature-map.json` | D3, P2 | D1 |
| D3 | `codex/notch-drawn-card-YYYYMMDD` | new `Sources/Zeus/Settings/GSDrawnNotchCard.swift`, `GlanceSettingsPages.swift` (one property in `:9-22`, `:91`, one line after `:260`), `GlanceSettingsWindow.swift` (two delegate methods on the controller at `:106`), `SettingsStore.swift` (one guard beside `:263-270`, one line at `:314`), `scripts/gen-settings-catalog.py` and its two outputs, new `Tests/ZeusAppTests/DrawnNotchCardTests.swift`, new `qa/closed-loop/tests/test_drawn_notch_card_lint.py`, `qa/feature-map.json` | D2, P2 | D1 |
| D4 | `codex/notch-drawn-place-YYYYMMDD` | `NotchFootprint.swift` (`NotchAnchor`), `NotchController.swift`, `NotchView.swift`, `GSDrawnNotchCard.swift`, `SnapshotRenderer.swift` (one new fixture), the generator and outputs, `test_drawn_notch_lint.py` | none | D2, D3 |
| P1 | `codex/music-hold-rules-YYYYMMDD` | new `Sources/ZeusCore/TopBar/MusicWingsHold.swift`, new `Tests/ZeusCoreTests/MusicWingsHoldTests.swift`, `docs/STATE-MACHINES.md` | D0, D1 | base |
| P2 | `codex/music-hold-surface-YYYYMMDD` | new `Sources/Zeus/TopBar/MusicWingsHoldController.swift`, `TopBarModel.swift` (`:116-117`, `:128-134`, `:344-346`), `TopBarViews.swift` (`:1362`, `:1448-1451`), `AppDelegate.swift` (one case in `:885-897`), `GlanceSettingsPages.swift` (one row after `:354`), the generator and outputs, new `Tests/ZeusAppTests/MusicWingsHoldControllerTests.swift`, new `qa/closed-loop/tests/test_music_wings_lint.py`, `qa/feature-map.json` | D1, D2, D3 | P1 |

Shared, append only: `qa/regressions.json` (every ticket), `qa/feature-map.json`, `docs/STATE-MACHINES.md` (D1, P1), the
settings generator and its outputs (D3, D4, P2: re-run the generator on the merged table, never hand-merge
`SettingsCatalog.swift` or `docs/settings-inventory.md`). `qa/closed-loop/tests/test_source_lint.py` is edited by no
ticket: each ticket's lints live in its own new file, as `test_alerts_lint.py` does.

Shared, with a merge order, because two tickets of this plan or a ticket of the sources plan edit the same file:

| File | Order inside this plan | Against `docs/NOTCH-SOURCES-PLAN.md` |
| --- | --- | --- |
| `GlanceSettingsPages.swift` | D3, then P2 (different cards, `:9-22`, `:91`, `:260` against `:354`) | A1 adds a Music group and A3 a privacy row: P2 lands before A1 starts or after A4 lands |
| `SnapshotRenderer.swift` | D0, D2, D4. Only D0 and D2 edit `NotchStage`; fixtures are appended | A4 appends fixtures: either order, never a `NotchStage` edit there |
| `AppDelegate.swift` | D2 (`:820`) and P2 (`:885-897`), either order | none named |
| `SettingsStore.swift` | D3 only | A3 edits the import list at `:255-258`: either order, different lines |
| `TopBarModel.swift`, `TopBarViews.swift` | P2 only | A1 and A4 own them: P2 merges before A1 starts or after A4 lands, never beside them |

D3 merges before D2 because D3 adds the seam (`GSContext.drawnNotch`, nil until set, and the card is not placed
while it is nil) and D2, rebased on it, sets it in one line. Feature `F13`. Regression ids: this plan holds REG-560
to REG-579, claimed in merge order (D0 560-561, D1 562-565, D2 566-569, D3 570-571, D4 572-573, P1 and P2 574-578,
579 spare). Builds go in `<models-dir>/<name>-build`, never inside OneDrive.

## How it works today (verified)

- Hardware notch size: `NotchController.notchSize(of:)` needs a top safe-area inset above 0 and both auxiliary top
  areas present, and returns the frame width less both areas by the inset height; otherwise `.zero`
  (`NotchController.swift:726-731`). Two other rules disagree with it: `describe` calls an inset alone a notch
  (`:505`), and `ScreenCorners.hasNotch` also wants both widths above 0 (`ScreenCorners.swift:69-71`).
- The pill: `DisplaySelection.showsPill` is "no notch" (`AgentHubRules.swift:146`), passed once per window as
  `slimPill` (`NotchController.swift:565-566`). `NotchView` draws 96 by 9 pt (`NotchView.swift:124`, `:146`; the same
  constant again at `NotchClosedBodyLayout.swift:8`), shoulder 0 (`:100`), bottom radius 4.5 (`:186`), own glow
  (`:224`).
- `NotchView.notch` and `slimPill` are fixed when the window is built (`NotchView.swift:70-72`), so a size change
  today means rebuilding windows. The controller caches `notchSize` (`NotchController.swift:19`, `:577`, `:585`) and
  reads it for the panel bar (`:343`), the click zone (`:407`), the hover zone (`:437-442`), the Approve point
  (`:481-483`) and the alert line (`:683`).
- Three rectangles for one pill: drawn 96 by 9; click zone 120 by 14 (`NotchOpenTrigger.swift:19-21`, `:38-40`);
  hover zone 160 by 29 (`GlanceTopBar.swift:141-145`). With wings the body is 40 + 124 + extra wide and 30 tall
  (`NotchClosedBodyLayout.swift:29-31`, `NotchView.swift:83`, `:137-142`) while the hover island is 160 + 140 + extra
  (`NotchController.swift:437-440`).
- The window: one borderless panel per target display, as wide as the screen and 470 pt tall
  (`NotchController.swift:551-553`, `GlanceTopBar.swift:107-109`), click-through while closed (`:145`, `:562`),
  taking the mouse only over the alert line (`:319-323`), over full-screen apps (`:561`), under the capture rule
  (`:564`, `:122-127`).
- S1 promised that a click is observed and never taken, and that the closed window stays click-through
  (`docs/NOTCH-SURFACE-PLAN.md:41-42`). D2 keeps that for the hardware notch and the pill only (decision 1).
- Music wings: `ClosedWings.kind` returns `.music` only while `nowPlaying?.isPlaying == true`
  (`TopBarViews.swift:1362`) and `hasLiveActivity` repeats the same test (`TopBarModel.swift:345`). The playing edge
  is the `didSet` at `TopBarModel.swift:128-134`; a quit player clears the item (`TopBarServices.swift:120-127`,
  `:182-185`). So wings collapse the instant a pause arrives.
- Body width and hover zone use different tests. The body widens when `showWings` is true: a wing kind, a lit light
  or a live activity (`NotchView.swift:130-135`, `NotchClosedBodyLayout.swift:39-41`). The hover island widens only
  when the wing kind is not `none` (`NotchController.swift:438`).
- The closed wings hold live controls: Stop on the Recordly wing (`RecordingActivityWings.swift:40`, built at
  `TopBarViews.swift:1380-1384`) and taps that open a tab (`:1378`, `:1396`, `:1408`, `:1411`). They cannot be
  pressed today only because the closed window ignores the mouse.
- Every change of the closed width springs (`NotchView.swift:119-121`, `:201`), with no Reduce Motion check. The
  alert stack is an overlay attached after the top alignment and the drop (`:203-204`, `:209-217`).
- The Settings window is built once and kept (`GlanceSettingsWindow.swift:121-135`); its controller is the window
  delegate (`:106`) and implements no delegate method. A page change replaces the page view (`:230`), so
  `onDisappear` fires then (as `GSBeamerPage.swift:84` relies on). Whether it fires when the window closes or is
  minimised is unverified, so no ticket relies on it.

## Anchored lines in `NotchController` that must stay

`test_source_lint.py` finds a function by the first occurrence of its signature text and reads its body by brace
matching (`:490-498`). `test_alerts_lint.py` does not: it reads `alertsChanged` from its signature to the first line
that is four spaces and a closing brace (`:39-40`), so nothing added inside that function may close at that indent,
and the word `Timer` may not appear in it at all, in a comment or in a helper's name. Keep each signature unique and
first in the file, and keep these strings verbatim:

| Lint | Function | Must stay | Today |
| --- | --- | --- | --- |
| `test_alerts_lint.py:37-44` | `private func alertsChanged()` | `alertWake?.cancel()`, `nextDeadline()`, exactly one `Task.sleep`, no `Timer` in the body | `:664-679` |
| `test_source_lint.py:550-551` | `func show(_ presentation` | `model.alerts.setSuspended(presentation != .closed` | `:147` |
| `test_source_lint.py:553-554` | `func snoozeAlert(` | `whileOpen: true` | `:649` |
| `test_source_lint.py:589-591` | `func start()` | `if self?.openOnClick() == true { return }` before `self?.clickedOutside()` | `:66-67` |
| `test_source_lint.py:593-594` | `func start()` | `addLocalMonitorForEvents(matching: [.leftMouseDown])` then `openOnClick()` with no `}` between | `:71-72` |
| `test_source_lint.py:596-597` | `private func mouseMoved()` | `guard NotchOpenRules.opensOnHover(Self.openTrigger) else` before `hoverTask = Task` and before `guard topBar != nil else { show(.panel); return }` | `:326-330` |
| `test_source_lint.py:599-602` | `private func openOnClick() -> Bool` | `topBar != nil \|\| !model.sessions.isEmpty \|\| model.approval != nil`, and `NotchOpenRules.opensOnClick(trigger: Self.openTrigger, panelIsOpen: model.presentation == .panel` before `show(.panel)` | `:406-412` |

What the tickets may change around them: the `let zone =` line above the anchored call in `openOnClick` (`:407`),
the body of `inHotZone` (`:436-443`), `build` (`:540-579`), `activate`, `describe`, `notchSize(of:)`, and new lines in
`mouseMoved` placed so the first occurrences keep their order. No new text above the hover gate may contain
`hoverTask = Task`. No ticket adds a timer or a second sleep to `alertsChanged`. No ticket edits `start()`: the
local mouse-down monitor (`:71-74`) keeps returning its event, and the new observers live in `DrawnNotchModel`.

## Open source checked first

Licences are as recorded in the private study of 13 November 2026 and in the house plans; none was re-read here.

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| Reading the hardware notch from the screen | MrKai77/DynamicNotchKit | MIT | Technique only: top inset for the height, the two auxiliary top areas for the width. Zeus already does this (`NotchController.swift:726-731`) |
| Same, and a click zone on the notch rectangle | Lakr233/NotchDrop | MIT (its README footer reserves rights: nothing is taken) | Technique only, already used by S1 |
| A source kept a while after a pause | servitola/nowplayingseek | AGPL-3.0 | Technique only, as noted in `docs/NOTCH-SOURCES-PLAN.md`. The hold rule here is Zeus's own |
| Interface facts | AppKit `NSScreen` (`safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`), `NSWindow` (`ignoresMouseEvents`, `sharingType`), `NSWindowDelegate` (`windowWillClose`, `windowDidMiniaturize`), `NSWorkspace.willSleepNotification` and `sessionDidResignActiveNotification`, `NSApplication.didHideNotification`, SwiftUI `allowsHitTesting` | n/a | Public and documented; each but the two delegate methods is already compiled against in this branch (`NotchController.swift:726-731`, `:562-564`, `PointingController.swift:297`, `WakeWordController.swift:69`, `OnboardingFlow.swift:437`, `NotchView.swift:657`). The lock notice `com.apple.screenIsLocked` is an undocumented name the branch already listens to (`NotchController.swift:90`); if it stops arriving, sleep and session resign still end calibration |

A drawn shape on a display without a notch needs no prior art: it is a black shape in the window Zeus already owns.
No code is copied, nothing is bundled and no dependency is added, so no licence duty arises.

## Privacy and consent

- No permission, entitlement, usage string, private call, network use or capture is added. Nothing prompts, at
  launch or later. There is no private route for a system vendor to close: only public screen, window and
  notification interfaces are used, plus the lock notice this branch already listens to.
- If a future macOS stops reporting the side areas of a notched display, the hardware rule fails closed to "no
  notch" and that display shows the shape chosen for displays without one. If `ignoresMouseEvents` stopped taking
  effect, the drawn shape would be click-through like the pill. If the lock notice stops, sleep still ends calibration.
- No row here opens a device or sends data. One row changes what Zeus may do: choosing Notch makes the closed
  window take clicks over its own shape, on the menu bar and over a full-screen app, which S1 promised it would
  never do (`docs/NOTCH-SURFACE-PLAN.md:41-42`). So a settings import can never select Notch; it may carry Pill and
  the size rows, each checked against its range (`SettingsStore.swift:276-286`). `neverEnabledByImport` covers
  switches only (`:255-258`, applied at `:314`), so D3 adds a choice guard in the shape of `importWouldSelectCloud`
  (`:263-270`). The owner may relax this (decision 5).
- The pause hold stores two dates in memory. No title, artist or player name is stored, logged or sent.
- Capture: the shape and the guide are drawn inside the existing notch panel, which already follows
  `ZeusWindowSharing` (`NotchController.swift:564`, `ZeusWindowSharing.swift:29-32`). With "Show Zeus in screen
  shares" off, a viewer sees the menu bar under the shape. Whether newer capture paths honour `.none` is unverified.
- Logs carry sizes in points and state names only. Tests use fixed frames and a fake store; none reads real displays.

## Security: how this could be abused, and how each way is closed

| Way in | What it could do | Closed by |
| --- | --- | --- |
| Another program of the same user writes the stored rows (`defaults write`), or the owner imports a hostile settings file | An absurd, off-screen or non-finite shape; the Notch style switched on | Every read goes through `DrawnNotchLimits.sanitized` and the per-display `fitted`; an unknown style is the pill. Worst case is the largest allowed shape (280 by 44 pt), visible and removable in Settings. An import range-checks the sizes and cannot select Notch. A direct `defaults write` can, as it can change any setting today |
| The shape hides something and a click presses it unseen | A menu item or a tab under the drawing is pressed blind | Best effort, not a guarantee. The closed window takes the mouse over the drawn body once a pointer move has been handled there (pure rule, tested on both sides of every edge). A move and a click that arrive faster than the main thread handles the move still reach what is under the shape, which is what the pill allows today |
| A click on the shape presses a control drawn in the closed wings | A screen recording stopped, or a tab opened, by a click meant to open the notch | The closed wings are drawn with hit testing off for every footprint (`NotchView.swift:308`), so the closed body takes the click and passes it to nothing. A lint keeps the modifier; a Mac check clicks the shape while Recordly records |
| The window takes the mouse where nothing is drawn | Zeus blocks clicks on other apps | `takesMouse` is false for the pill, the hardware notch, any state but closed, and any point outside the body rectangle. A lint keeps every closed-state `setIgnoresMouse` call behind the rule |
| Synthetic clicks or pointer moves from another program | Opens the notch | True today for S1 and hover; opening the panel grants nothing. Calibration has no control on the notch: only the Settings card starts or changes it (lint), and no hook, command-line or URL path does. A forged lock notice from another program can only end calibration and drop an unsaved draft |
| Calibration left running (Settings closed, minimised or hidden, the Mac locked, asleep or switched to another user) | The notch stops opening by pointer with nobody at the card | Each of those ends calibration without saving (`surfaceGone`, sent by the Settings window controller and by `DrawnNotchModel`); the guide outline stays on the notch for as long as calibration runs, so the state is never silent |
| A display that reports hostile facts (a virtual display with a zero, huge, negative or non-finite frame; insets without areas) | A NaN frame reaching AppKit, or a shape wider than the screen | `hardwareSize` and `fitted` reject non-finite and non-positive input and return the pill; a display too narrow for the minimum shape gets the pill |
| A device or display name | Stored or shown text | No name is read, stored, shown or logged by any ticket. The shape is one global value, not keyed by display |
| Any local process posts the players' public playback notifications (`TopBarServices.swift:102-111`) | Fake play and pause edges; with "Never", wings that stay | True today for the wings themselves. The hold adds no text to the closed notch, keeps at most one sleeping task however many edges arrive (tested with 1000 edges), and ends when the item goes away |
| A flood of screen-change notifications during calibration | A stuck calibrating state | `surfaceGone` ends calibration without saving when no display without a notch is left |

## D0. One closed-shape value (refactor, no behaviour change)

### Behaviour

Nothing the owner can see or feel changes. The hardware notch, the pill, every zone and every snapshot stay as they
are. One edge case changes on purpose, with two effects, both under REG-560: a display that reports a top inset but
no side areas is no longer called notched by `describe` (`NotchController.swift:505`) while sized as not notched by
`notchSize(of:)`. First, such a display gets the pill instead of an empty closed notch. Second,
`DisplayDescriptor.hasNotch` also picks the "Built-in display" target (`AgentHubRules.swift:134`: the first notched
screen, else the built-in panel, else the first screen), so an inset-only display is no longer picked ahead of the
built-in panel; when it is the built-in panel itself, the pick is the same.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/NotchFootprint.swift`:

| Name | Rule |
| --- | --- |
| `NotchDisplayFacts` | `Sendable` value: screen frame, top inset, left and right area widths (0 when the area is missing) |
| `NotchFootprint` | `hardware(CGSize)` or `pill`. `layoutSize` (the hardware size; zero for the pill: what `NotchView` calls `notch` today), `idleSize` (hardware size; 96 by 9), `wingBase` (hardware width; 40), `isPill` |
| `NotchFootprintRules.hardwareSize(_:)` | Finite facts, inset above 0, both widths above 0, frame width less both widths above 0; else nil. On finite input whose frame is wider than the two areas it agrees with `ScreenCorners.hasNotch` (`ScreenCorners.swift:69-71`); elsewhere it is stricter (an infinite width, or areas as wide as the frame, give nil where `hasNotch` says true) |
| `NotchFootprintRules.resolve(_:)` | `hardware` when `hardwareSize` answers, else `pill` |
| `ClosedWingsFacts` | `Hashable` value with the three inputs of `NotchClosedBodyLayout.showWings` kept apart (`kindIsNone`, `hasLights`, `hasLiveActivity`) and the extra width. `showsWings` is the layout rule's answer |
| `ClosedWingsFacts.motionKey` | `kindIsNone`, `showsWings` and the extra width: everything the closed width depends on except the footprint. Two facts with different closed widths never share a key |
| `NotchFootprintRules.hoverZone(_:screenFrame:topOffset:wings:)` | Today's numbers exactly: the island of `NotchController.swift:437-440` through `GlanceTopBar.hoverZone`, widened by `kindIsNone == false` alone. A lit light with no wing kind widens the body and not the hover zone, as today |
| `NotchFootprintRules.clickZone(_:screenFrame:topOffset:)` | `NotchOpenRules.clickZone` with `layoutSize`, unchanged |

App side: `NotchView` takes `footprint` in place of `notch` and `slimPill` and derives both as private computed
values, so its other lines keep compiling; the duplicate `pillSize` (`NotchView.swift:124`) goes. `closedWidthKey`
(`:119-121`) returns the `motionKey` while closed and nil otherwise: for one fixed footprint that key changes
whenever the width does, so the spring at `:201` fires as before (where the key changes and the width does not, the
wing kind changed and `:300` already applies the same spring), and D2 can change the footprint live without it.
`NotchController` builds facts from the screen in one function, drops `notchSize(of:)`, keeps one stored `footprint`
where `notchSize` is set today, and calls the two zone rules from `inHotZone` and `openOnClick`. `describe` takes
`hasNotch` from `hardwareSize`. `DisplaySelection.showsPill` and its test move into the footprint suite. All 22
`NotchStage` calls pass the one fixture of 185 by 32 (`SnapshotRenderer.swift:68`), now as `.hardware(notch)`.

### Tests first (`Tests/ZeusCoreTests/NotchFootprintTests.swift`)

A 1512 pt display with two 664 pt areas and a 32 pt inset is `hardware(184 by 32)`; an inset without areas, one
zero-width area, a negative width and NaN each give `pill`. Against `ScreenCorners.hasNotch`: equal answers over a
table of finite inputs with room for a notch, and two named cases where `hardwareSize` is stricter. Pill sizes and
wing base; hover zone 184 by 31 for that notch, 160 by 29 for the pill, 300 + extra wide with a wing kind, taller by
the top offset; with a light lit and no wing kind the hover zone stays 184 by 31 and 160 by 29 while the body
widens; click zone equal to `NotchOpenRules.clickZone` for both shapes; a screen at a negative origin. Motion key:
over every combination of the three wing inputs and two extra widths, different body widths give different keys,
for the hardware notch and for the pill. In `DisplaySelectionTests` (`AgentHubTests.swift:242-243`): an inset-only
display that is built in is still the "Built-in display" target; one that is not built in is not picked ahead of
the built-in panel. `NotchOpenTriggerTests`, `GlanceTopBarTests`, `NotchClosedBodyLayoutTests` and the rest of
`DisplaySelectionTests` pass unchanged. What only a person at the Mac can check is listed under Verification.

## D1. Drawn shape rules and calibration (pure)

### Behaviour

- The drawn shape is a black notch silhouette: square top against the screen edge, the closed bottom radius of 6 pt
  (`GlanceTopBar.swift:12`), no shoulders while idle. It is laid out exactly as a hardware notch of that size: wings
  sit either side, lights follow its outline, the peek and the panel grow from it.
- Size: width 140 to 280 pt in steps of 5, default 185; height 30 to 44 pt in steps of 1, default 32 (the defaults
  equal `GlanceTopBar.closedSize`, `GlanceTopBar.swift:11`). Height never goes under 30 because every closed wing is
  laid out for a 30 pt bar (`NotchView.swift:83`). Position (D4): minus 400 to plus 400 pt in steps of 5, default 0.
- Fit per display: never wider than a quarter of the display. A display too narrow for 140 pt keeps the pill.
- One shape for every display without a notch, like the top bar position (`TopBarPosition.swift:7`).
- Calibration is a step the owner starts and ends. While it runs the notch shows a draft; Done saves it, Cancel
  drops it, and anything that takes away the card or the shape drops it too: leaving the Settings page, closing,
  minimising or hiding Settings, choosing Pill, the last display without a notch going away, the Mac locking or
  sleeping, the session switching to another user. Settings sitting behind another app does not end it: the owner
  may click elsewhere to judge the shape, and the guide outline shows that calibration is running.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/DrawnNotch.swift`:

| Name | Rule |
| --- | --- |
| `NotchlessStyle` | `pill`, `drawn`; `init(label:)`: "Notch" is `drawn`, anything else `pill` (today's behaviour) |
| `DrawnNotchShape` | `Sendable` value: width, height, offset, in points |
| `DrawnNotchLimits` | The ranges, steps and defaults above. `sanitized(_:)`: finite, snapped to the step, inside the range; a non-finite field takes its default |
| `DrawnNotchLimits.fitted(_:screenWidth:)` | Width at most a quarter of the display, snapped down; offset inside plus or minus `max(0, (screenWidth - 925) / 2 - 8)`, snapped toward zero (925 is the open panel with its ears, `GlanceTopBar.swift:15-16`, `:120-122`); nil when the display is non-finite or cannot hold 140 pt |
| `DrawnNotchCalibration.State` | `idle`, `adjusting(draft:saved:)` |
| `DrawnNotchCalibration.SurfaceLoss` | `pageLeft`, `settingsClosed`, `settingsMinimised`, `appHidden`, `pillChosen`, `noDisplay`, `locked`, `sleeping`, `sessionResigned`. Logged by name; every case has the same result |
| `DrawnNotchCalibration.Event` | `begin(saved:)`, `setWidth`, `setHeight`, `setOffset`, `step(field, up or down)`, `reset`, `done`, `cancel`, `surfaceGone(SurfaceLoss)` |
| `DrawnNotchCalibration.Effect` | `persist(DrawnNotchShape)`, `announce(String)` |
| `DrawnNotchCalibration.reduce(_:_:)` | `begin` from `idle` copies the sanitized saved shape into the draft; a second `begin` changes nothing. A set, step or reset outside `adjusting` is ignored with no effect. `done` returns to `idle` and emits `persist` only when the draft differs from the saved shape, then `announce`. `cancel` and `surfaceGone` return to `idle` with no `persist`; `surfaceGone` while `idle` does nothing |
| `DrawnNotchCalibration.shown(_:saved:)`, `showsGuide(_:)`, `allowsOpen(_:)` | The draft while adjusting, else the saved shape; the guide and the "do not open by pointer" rule hold only while adjusting |
| `DrawnNotchAvailability` | `ready` (the notch is shown on a display without a notch), `notShown` (such a display is connected but is not a target of "Show the notch on"), `noDisplay` (none is connected). `resolve(targetsWithoutNotch:connectedWithoutNotch:)`; negative counts read as 0 |
| `DrawnNotchControlling` | `@MainActor` protocol: `style`, `saved`, `state`, `availability`, `setStyle(_:)`, `send(_:)`. It lets D2 and D3 compile apart, as B0 does in the equaliser plan |

In `NotchFootprint.swift`: a third case `drawn(DrawnNotchShape)` (already fitted) with `layoutSize`, `idleSize` and
`wingBase` from its size; `resolve(_:style:shape:)` (hardware wins; then the pill for `pill` or a failed fit; then
`drawn`); `bodyRect(_:screenFrame:topOffset:wings:)`, the closed body exactly as `NotchView` draws it, so it widens
on the full `showsWings` answer; for `drawn`, `hoverZone` and `clickZone` are that rectangle and nothing above it,
so a lowered shape never claims the menu bar strip over it (the hardware notch and the pill keep D0's zones);
`takesMouse(_:closed:point:...)` is true only for `drawn`, closed, and a point in the body (the top edge counts and
the bottom does not, as in `GlanceTopBar.swift:169-174`).

### Tests first (`DrawnNotchTests.swift`, `DrawnNotchCalibrationTests.swift`, additions to `NotchFootprintTests.swift`)

Labels with an unknown value; sanitizing NaN, infinity, values off the step and outside each range; the fit on 1920,
1280, 1024 and 500 pt displays (the last gives nil) and a non-finite width; the offset clamp at both ends. Reducer:
begin, each set clamps, step up at the maximum stays, reset, done with and without a change, cancel, `surfaceGone`
for each of the nine losses (from `adjusting` and from `idle`), a set while `idle` is ignored, a second begin keeps
the draft, no path from `cancel` or `surfaceGone` emits `persist`. Availability for 0, 1 and 2 targets against 0, 1
and 2 connected. Footprint: hardware beats a `drawn` style; `pill` style and a failed fit give the pill; the body,
hover and click rectangles are equal for `drawn` in every wings state (a lit light with no wing kind included) and
at top offsets 0 and 24; the motion key is the same for two drawn shapes of different sizes and for the pill and a
drawn shape under the same wing facts; `takesMouse` on both sides of each edge and false for the pill, the hardware
notch and any state but closed. Every user-facing string in ZeusCore is free of U+2014 and U+2013.
`docs/STATE-MACHINES.md` gains the calibration entry.

## D2. The drawn shape on the notch

### Behaviour

- With Shape set to Notch, each display without a hardware notch that shows the notch (`notch.displays`) draws the
  shape in place of the pill. A notched display is untouched. Choosing Pill restores today's pill at once.
- Changes are live and never rebuild a window: the view reads the shape from an observed model, as it already reads
  the top bar position (`NotchView.swift:78-81`).
- The hover zone and the click zone are the drawn body, wings included. No separate 160 by 29 zone. While closed,
  the window takes the mouse over that body only, so what is hidden under the shape is not pressed (best effort:
  see the security table). Beside and below it clicks reach the app underneath, as today.
- A click on the closed shape presses nothing drawn in it: the closed wings are drawn with hit testing off, for
  every footprint, so Stop on the Recordly wing and the tab taps stay as unreachable as they are today. In Hover the
  click is taken and does nothing more; in Click the local monitor opens the panel (`NotchController.swift:71-74`)
  and the same event then reaches the still-closed view tree, where nothing accepts it.
- While calibrating: the shape tracks the draft without animation, a guide shows on the closed notch, and neither
  hover nor a click opens the panel. What opens the notch without a pointer dwell or click still works: the
  shortcut, agent cards, cues, and a file dragged to the notch, which opens the Shelf as today (`:445-461`).
  Calibration stays `adjusting` under an open panel and the guide is back when it closes.
- Calibration ends without saving on every loss D1 lists; hover and click then open the notch again at once.
- The vertical drop stays the existing "Top bar position" (0 to 24 pt, `TopBarPosition.swift:14-16`), unchanged.

### Design

- Guide: a 1 pt light outline on the drawn body, because a black shape on a dark menu bar cannot be seen. No text:
  the sliders in Settings show and speak the size. Hidden from accessibility.
- No new motion. The only spring on the closed width is keyed on D0's `motionKey`, which no footprint change can
  alter, so a width or height step and a Pill to Notch switch change the frame in a transaction with no animation,
  Reduce Motion on or off. Wings and cues spring as today. The sideways position (D4) has no animation modifier.
- The guide and the shape are in the notch panel, so the capture rule applies with no new registration.

### App side

| Where | Change |
| --- | --- |
| new `Sources/Zeus/Notch/DrawnNotchModel.swift` | `@MainActor @Observable`, conforms to `DrawnNotchControlling`. Reads the rows through `SettingsStore` (already observed by the notch, `NotchLights.swift:59-61`), holds one calibration state and carries out the two effects: `persist` writes the rows, `announce` posts a VoiceOver announcement as `NotchController.swift:297-300` does. `footprint(for:)` is `resolve` with the shown shape |
| same file, the surface | It sends `surfaceGone` itself and holds no flag for it. `displaysChanged(targetsWithoutNotch:connectedWithoutNotch:)` sets `availability` and sends `noDisplay` when no target is left. Four observers registered in its `start()`, each hopping with `MainActor.assumeIsolated` on `.main`, send the other losses: `com.apple.screenIsLocked`, `NSWorkspace.willSleepNotification`, `NSWorkspace.sessionDidResignActiveNotification`, `NSApplication.didHideNotification`. The notification centres are injected; snapshots and tests never call `start()` and never read the store |
| `NotchController.swift` | `build` ends by calling `displaysChanged`, so screen changes (`:78-82`) and the pointer-display rebuild (`:537`) both reach the model. The footprint is computed from the active screen on use, not cached. One helper answers "does the closed window ignore the mouse here" from the pure rule and is called from `mouseMoved`, `show`, `alertsChanged` and `build`, so a close or a cleared alert under a resting pointer leaves the right state. The calibration guard goes after the anchored hover gate in `mouseMoved` and between the two anchored lines in `openOnClick`; `mouseDragged` is not guarded; `start()` is not edited |
| `NotchView.swift` | Takes display facts and asks the model, with an override for snapshots as `topOffsetOverride` is (`:74`). `ClosedWings` at `:308` gains `.allowsHitTesting(false)`. The guide is one stroked outline over the closed body |
| `SnapshotRenderer.swift`, `AppDelegate.swift` | `NotchStage` passes the override; three fixtures (the drawn shape idle, with music wings, with the guide). `AppDelegate` starts the model and sets it on the Settings context (`:820`) |

### Tests first

`Tests/ZeusAppTests/DrawnNotchModelTests.swift` (`@MainActor`, a fake store, fake notification centres): done writes
the size rows once; cancel writes nothing; the footprint for a display without a notch follows the draft; a notched
display ignores the style; `displaysChanged` with no target left ends calibration and writes nothing; each of the
four notifications does the same; `availability` follows the two counts; snapshots read no store.
`qa/closed-loop/tests/test_drawn_notch_lint.py`, each with a fail-first sample: the seven anchors still hold and
`start()` holds no new observer; the calibration guard sits after the hover gate and before `show(.panel)`; every
closed-state `setIgnoresMouse` goes through the helper; `build` reports the displays to the model;
`ClosedWings(topBar: topBar)` carries `.allowsHitTesting(false)`; `closedWidthKey` does not read `size(for`; no
`NSPanel(` or `NSWindow(` in the model or the guide; no U+2013 or U+2014 in new app files. A native-fixture entry.

## D3. Settings card

### Behaviour and design

- Appearance, a new card "Displays without a notch" directly after the "Top bar" card
  (`GlanceSettingsPages.swift:235-260`), in its own file so the page file gains one line.
- Row 1, "Shape": a segmented control, Pill or Notch.
- Row 2, only for Notch: the saved size as a value ("185 by 32 pt") and a "Calibrate" button. Pressing it sends
  `begin` and the row becomes three: "Width" and "Height" sliders, each with its value in points, then "Reset",
  "Cancel" and "Done".
- Row 2 follows `availability`. `ready`: as above. `notShown`: the status "Not shown on that display" with the
  symbol `display.trianglebadge.exclamationmark` and a button "Show the notch on" that opens General, where that
  row is (`GSNavigation.section`, `GlanceSettingsWindow.swift:98`). `noDisplay`: the status "No display without a
  notch", same symbol, no button, since nothing in Settings can change it. A word with a symbol, never colour alone.
- No helper text on any new row. The sentence under "Show the notch on" (`GlanceSettingsPages.swift:91`) and two
  generator notes stop being true and are corrected: the pill claim at `gen-settings-catalog.py:18`, and "or the
  pill, grown 12 pt each side" at `:51`, which gains the drawn shape's own rectangle.
- Sliders: a new `GSPointSlider` in the card file, focusable, one step per arrow key, speaking "Width, 185 points".
  `OBTickSlider` speaks "percent" and takes no keyboard focus (`OnboardingSteps.swift:619-660`); it is not edited.
- Who ends calibration from Settings: the card sends `surfaceGone(.pageLeft)` from `onDisappear` (a page change)
  and `.pillChosen` when Pill is chosen; `GlanceSettingsWindowController`, already the window delegate, gains
  `windowWillClose` and `windowDidMiniaturize` and sends `.settingsClosed` and `.settingsMinimised` through
  `context.drawnNotch`. So Command-W and the red and yellow buttons are covered without `onDisappear`.
- Import: `SettingsStore.importWouldSelectDrawnNotch(id:value:)` is true for `notch.shapeWithoutNotch` with the
  value "Notch"; the import loop skips that row beside `:314`. Pill and the size rows import as any row.
- Reduce Motion: the row swap happens without animation. Done is announced by the model's `announce` effect.

### Tests first

`Tests/ZeusAppTests/DrawnNotchCardTests.swift` against a `@MainActor` fake `DrawnNotchControlling`: Calibrate sends
`begin`; a slider sends a clamped set; Done, Cancel and Reset send their events; each availability shows its row,
and the `notShown` button sets the section to General; the two delegate methods send their losses; with a nil
`context.drawnNotch` the card is absent and the delegate methods do nothing; an import holding "Notch" leaves Pill
in place, one holding "Pill" over Notch is applied, sizes are applied; the snapshot never touches the model.
`qa/closed-loop/tests/test_drawn_notch_card_lint.py`: the card sends `surfaceGone` from `onDisappear`; `begin`, the
sets, `step`, `reset`, `done` and `cancel` are sent from the card file only, and `surfaceGone` only from the card
file, `GlanceSettingsWindow.swift` and `DrawnNotchModel.swift`; the card is placed on a page
(`test_source_lint.py:313`); no U+2013 or U+2014 in the card file.

## D4. Place

### Behaviour

- A third slider, "Position", in the calibration row: 0 is the centre, the value reads "Centre", "40 pt left" or
  "40 pt right". It applies to the drawn shape only; the hardware notch and the pill stay centred.
- The whole notch moves: closed body, wings, lights, alert line, peek and the open panel, which stays fully on
  screen because the fit clamps the offset.
- The screen-edge glow and edge wave keep starting at the screen's top centre, as they already ignore the vertical
  drop (`TopBarPosition.swift:37-43`). Cards that sit under the notch of another display are unaffected.

### Rules and app side

`NotchAnchor.frame(screenFrame:footprint:)` in `NotchFootprint.swift`: the screen frame moved sideways by the fitted
offset for `drawn`, unchanged otherwise. Every pure zone rule already centres on the frame it is given, so the
controller passes the anchor frame at the eight sideways sites (`NotchController.swift:354`, `:356`, `:357`, `:407`,
`:441`, `:457`, `:483`, `:686`) and keeps the real frame for the display pick (`:530`) and the window (`:551`).

The view applies one sideways offset as the outermost modifier of `NotchView.body`, after the alert overlay and its
animation (`NotchView.swift:209-217`). At the top alignment (`:203-204`) it would move the body and leave the
alerts centred, since `offset` moves drawing and not layout, while the controller's alert rectangle (`:686`) moved
with the anchor. The edge wave and the screen glow are separate windows (`EdgeWave.swift:47`,
`ScreenEdgeGlowController.swift:71`), so they stay put.

### Tests first

Additions to `NotchFootprintTests.swift`: the anchor for each footprint; the body, hover and click rectangles and
`takesMouse` all move by the offset; at the clamp the open panel's outer edge stays 8 pt inside the screen on 1280,
1920 and 3440 pt displays; a negative-origin display. Lints: no `screen.frame.midX` is left in `NotchController`;
in `NotchView.body` the `.offset(x:` comes after `value: model.alerts.isEmpty)`. One snapshot fixture: an alert
under a drawn shape placed 200 pt right, the capsule centred under the shape.

## P1. Pause hold rules (pure)

### Behaviour

- Setting "Collapse when music pauses": At once (default, today's behaviour), After 10 s, After 1 min, Never.
- A pause holds the wings only if the music wings were on screen at that moment. An item first seen paused never
  opens them. A pause while the wings switch is off, or while another wing covers the music (a recording, a focus
  timer, a cue), holds nothing, so wings that were never shown cannot appear paused later. A hold that began on
  screen and is then covered keeps running underneath.
- During a hold, playing again ends the hold and keeps the wings. The item going away (the player quits) or the
  wings switch going off collapses at once. A track change while paused does not restart the clock.
- Changing the setting during a hold shortens or lengthens that hold from the moment of the pause. It never brings
  back wings that already collapsed.
- A clock set back so that "now" is before the pause collapses at once, as `MusicAwakeRule` treats a future play
  time (`MusicAwake.swift:33-35`).
- The open panel is not affected; it closes as it does today.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/MusicWingsHold.swift`:

| Name | Rule |
| --- | --- |
| `PauseCollapse` | `atOnce`, `after(seconds)`, `never`; `init(label:)`: an unknown label is `atOnce`; a non-finite or non-positive delay is `atOnce` |
| `MusicWingsHold.Playback` | `none`, `playing`, `paused` |
| `MusicWingsHold.State` | `hidden`, `playing`, `held(since:until:)` with `until` nil for Never |
| `MusicWingsHold.Event` | `playback(Playback, wingsOnScreen: Bool, now:)`, `wingsSwitchedOff`, `policy(PauseCollapse, now:)`, `deadline(now:)`. `wingsOnScreen` is read only on the edge from `playing` to `paused` |
| `MusicWingsHold.Effect` | `wake(at:)`, `cancelWake` |
| `reduce(_:_:policy:)` | The behaviour above. A pause with `wingsOnScreen` false goes to `hidden`. `wingsSwitchedOff` during a hold goes to `hidden` with `cancelWake`. A `deadline` before `until` changes nothing and emits `wake(at: until)` again, so an early or stale wake can never collapse a hold |
| `showsWings(_:)`, `isPaused(_:)` | True for `playing` and `held`; true for `held` |

### Tests first (`Tests/ZeusCoreTests/MusicWingsHoldTests.swift`)

Labels; each policy on a pause from `playing`; first seen paused stays `hidden`; a pause with the wings off screen
stays `hidden` under every policy, and playing again shows them; the switch going off during a hold hides and
cancels the wake, and going on again brings nothing back; play during a hold; gone during a hold; a second pause
event keeps `since`; `deadline` at, before and after `until`; `deadline` under Never; each policy change during a
hold, including one whose new deadline has already passed; a policy change while `hidden` or `playing` changes
nothing; "now" before `since` collapses; 1000 alternating edges leave at most one `wake` not yet cancelled.
`docs/STATE-MACHINES.md` gains the hold entry.

## P2. Pause hold on the notch

### Behaviour and design

- The closed wings stay for the chosen time after a pause, then collapse with the spring they already use.
- While held, the right wing shows a `pause.fill` symbol where the level bars were, and the wing's accessibility
  value is "Paused". State is never shown by stillness alone. The notch light wave still stops with the sound
  (`NotchLights.swift:66`, unchanged).
- Settings row "Collapse when music pauses" directly under "Light wave while music plays"
  (`GlanceSettingsPages.swift:354`), a menu, no helper text, subdued while the wings switch is off.

### App side

- `TopBarModel` gains the hold state, the policy, and one derived Bool, `showsMusicWings` (wings switch on and
  `MusicWingsHold.showsWings`). `ClosedWings.kind` (`TopBarViews.swift:1362`) and `hasLiveActivity`
  (`TopBarModel.swift:345`) both read it, so for music the body width, the wings and the hover zone follow one value.
- The model runs the reducer itself, synchronously: the `nowPlaying` `didSet` (`:128-134`, after its edge guard)
  sends `playback`, with `wingsOnScreen` read before the change as "the switch is on and `ClosedWings.kind` is
  `.music`"; the `liveMusicWings` `didSet` (`:116-117`) sends `wingsSwitchedOff`. Effects go to one closure,
  `onMusicHoldEffects`, which does nothing by default. So a fixture that assigns `nowPlaying` to a fresh model
  (`SnapshotRenderer.swift:589`, `:826`) still gets `playing` and its wings with no controller, and never sleeps.
- New `MusicWingsHoldController` (`@MainActor`): holds no state. It sets that closure, carries out `wake` and
  `cancelWake` through an injected scheduler, sends `deadline` with the real time when a wake fires (so sleep of
  the Mac during a hold needs no special case), and sends `policy` from one new case in `wireSettingsCatalog`
  (`AppDelegate.swift:885-897`). The default scheduler is one cancellable `Task.sleep` in the controller file,
  re-armed and never polled: the injection shape of `MusicAwakeHold.swift:38-57`, not its `Timer` default.
- Known edge: a pause that lands while a short cue covers the music wings (a volume step) collapses at once when
  the cue ends, as today. Accepted over tracking what a cover hides.
- The sources plan's hub writes the same `nowPlaying` slot; only the merge order of the shared files matters.

### Tests first

`Tests/ZeusAppTests/MusicWingsHoldControllerTests.swift` with an injected clock and scheduler: pause then the
deadline hides the wings; play before it keeps them and cancels the sleep; quit during a hold hides at once; a
setting change re-arms one sleep; a pause under a focus timer holds nothing; the switch going off during a hold
hides at once; a fresh model with no controller shows wings for a playing item; `kind` and `hasLiveActivity` agree
on music in every state. `qa/closed-loop/tests/test_music_wings_lint.py`: the bodies of `ClosedWings.kind` and
`hasLiveActivity`, and only those, hold no `nowPlaying?.isPlaying` (the play button at `TopBarViews.swift:517` and
the `didSet` at `TopBarModel.swift:130-132` keep theirs); `MusicWingsHoldController.swift` holds exactly one
`Task.sleep` and no `Timer`; no U+2013 or U+2014 in the ticket's new app strings.

## Settings rows

| Id | Where | Control | Default | Ticket |
| --- | --- | --- | --- | --- |
| `notch.shapeWithoutNotch` | Appearance, new card "Displays without a notch" | Segmented: Pill, Notch. "Shape" | Pill | D3 |
| `notch.drawnWidth` | Same card, while calibrating | Slider 140 to 280, step 5. "Width" | 185 | D3 |
| `notch.drawnHeight` | Same card, while calibrating | Slider 30 to 44, step 1. "Height" | 32 | D3 |
| `notch.drawnOffset` | Same card, while calibrating | Slider minus 400 to 400, step 5. "Position" | 0 | D4 |
| `music.collapseOnPause` | Appearance, lights card, Music group | Menu: At once, After 10 s, After 1 min, Never. "Collapse when music pauses" | At once | P2 |
| `notch.displays` | General, "Your defaults" | Unchanged control; the pill sentence is removed | Unchanged | D3 |

Rows go in `scripts/gen-settings-catalog.py`, section `appearance`, state `live`; the catalog note of each row is
inventory text and is not drawn. Regenerate, never hand-edit; `scripts/check-settings-catalog.sh` passes. A negative
slider minimum works: the generator writes the three numbers as given into `SettingOption.Range(min:max:step:)`
(`gen-settings-catalog.py:262`), whose fields are `Double` (`SettingsStore.swift:16`), and import compares against
them (`:281-282`). `notch.shapeWithoutNotch` is the one row an import may not set to its non-default value.

## Repo hazards that apply

- Lint anchors: the table above; the closed-loop lints run on every ticket that touches `NotchController`.
- Swift 6: every monitor and observer in `NotchController` hops with `MainActor.assumeIsolated` on `.main`
  (`:52-93`); new callbacks follow that shape. Detached work captures `Sendable` values only. Sandboxes have not
  compiled Swift, so budget a Mac build before any ticket is called done.
- The notch hosting view has `sizingOptions = []` (`NotchController.swift:569`): the panel frame never follows the
  content, so a live size change must stay inside the fixed 470 pt window. The largest closed body here fits.
- No window is added and none moves between Spaces, so `ZeusWindowSharing.refresh` needs no new line.
- The wings spring has no Reduce Motion check (`NotchView.swift:201`, `:300`), unlike the top offset (`:208`). D0
  re-keys it so the footprint never triggers it; the hold adds only a later start. The gap is noted, not fixed.
- The top bar position slider already speaks "percent" for points (`GlanceSettingsPages.swift:240-243`). Not fixed
  here; `GSPointSlider` could replace it later. The onboarding files are not edited.
- The em dash lint checks U+2014 only and `Sources/Zeus` only (`test_source_lint.py:126-131`), so each ticket's own
  lint or test also checks U+2013 in its new strings.
- `NotchClosedBodyLayout.bodyWidth` keeps its signature: `SystemHUDWingMotion.swift:39` and `:45` call it.

## Decisions the owner owes

1. The drawn shape takes clicks over its own body (planned, best effort) or stays click-through like the pill (S1's
   wording for every shape). macOS does not lay the menu bar out around a drawn shape, so an app menu or a status
   item under it is covered either way: taking clicks makes it unreachable by mouse until the shape is moved,
   resized or set back to Pill; click-through keeps it reachable but pressed blind.
2. A drawn shape over a full-screen app: stays, as the pill does today (planned), or hides. Cost of staying: the
   shape covers, and with decision 1 as planned blocks, the tabs or toolbar under it, where the pill is small and
   click-through. Hiding is its own ticket on the existing `FullScreenDetector` (`AgentCardsUI.swift:133-150`).
3. One shape for every display without a notch (planned) or one per display, which needs a stable display key.
4. The hold choices: 10 s and 1 min (planned) or other values.
5. A settings import can never select Notch, because it changes click handling (planned), or may (D3 drops its guard).
6. Minimum height 30 pt (planned) or a 24 pt bar flush with a menu bar, which needs the closed wings laid out again.
7. Settings behind another app keeps calibration running (planned) or ends it, losing the draft on any click away.

## Out of scope

- A shape per display, shapes other than the notch silhouette, colour or material choices for the shape.
- Hiding on full-screen Spaces; the edge wave and glow following a placed notch; cards under the notch following it.
- Changing the pill, its zones or its glow, or the hardware notch path. The Reduce Motion gap in the wings spring.
- A hold for wings other than music. A hold for the open panel. Any change to the display hold while music plays.

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the ticket's new names).
2. `swift build --build-tests`, then `swift test --filter` for `NotchFootprintTests`, `DrawnNotchTests`,
   `DrawnNotchCalibrationTests`, `MusicWingsHoldTests`, `DrawnNotchModelTests`, `DrawnNotchCardTests`,
   `MusicWingsHoldControllerTests`, and the pinned `NotchOpenTriggerTests`, `GlanceTopBarTests`,
   `NotchClosedBodyLayoutTests`, `DisplaySelectionTests`, `ScreenCornersTests`, `PolyglotPinTests`,
   `AgentStatusTests`. The filter matches suite and test names, never file names (`AgentHubTests.swift` holds seven
   suites, `:8-290`, and its name matches nothing), so a filtered run that reports zero tests does not count.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared, with known failures recounted.
4. `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py'`, the settings generator and its check,
   `./tools/check.sh` development mode from a worktree under `<models-dir>`.
5. D0 alone: snapshots rendered on the base and on the branch are compared and identical.
6. An independent review of each diff, reading the anchored functions and the mouse-taking rule line by line.
7. Still owed on a real Mac, by a person, per ticket:

| Ticket | Only at the Mac |
| --- | --- |
| D0 | The closed notch on a notched laptop and the pill on an external display look and open exactly as before, in Hover and Click; wings and cues spring as before; a lit light with no wing does not widen the hover zone |
| D2 | The shape on an external display and on an older laptop; hover and click open exactly on the drawing and not beside it; a menu item under the shape is not pressed after a slow approach and one beside it is; clicking the shape while Recordly records, in Hover and in Click, never stops the recording, and a Click-mode click presses nothing in the panel it opens; a width slider dragged end to end shows no spring, Reduce Motion on and off; the shape absent from a screenshot with sharing off; the guide visible on a dark and a light menu bar; "All displays" with a notched laptop and an external display; while calibrating, each of unplugging the display, locking, sleeping, fast user switching and hiding Zeus restores the saved shape and pointer opening; a file dragged to the notch during calibration opens the Shelf; idle CPU with a drawn shape |
| D3 | The whole flow by pointer, by keyboard and with VoiceOver; values spoken in points; leaving the page, Command-W, the red button and the yellow button each end calibration and restore the saved shape; with the window behind another app calibration goes on and the guide shows; the "Show the notch on" button lands on General; an imported file cannot switch Notch on; a long drag stays smooth |
| D4 | The panel opening from an off-centre shape at both extremes; the Approve button point under it; an alert under an off-centre shape sits centred under it and takes hover and click where it is drawn; a file drag to the moved notch; the edge wave still starting at the centre |
| P2 | Each choice with Music and with Spotify; a pause from the notch, from the player and from the keyboard; a pause under a focus timer and with the wings switch off, then the timer ending and the switch going on; quitting the player during a hold; a hold across sleep and wake; the pause symbol read by VoiceOver; the hover zone matching the held wings; idle CPU during a Never hold (`scripts/check-perf-budget.sh` with `PID=`) |

Not verified in this session: the clock of `Task.sleep(for:)` across system sleep (the wake sends the real time,
so nothing depends on it); whether a full-screen Space hides the menu bar strip the shape would cover; whether
`onDisappear` fires when the retained Settings window closes (nothing relies on it).

## Review notes

Changed after review: closed wings drawn with hit testing off, so a click on the drawn shape cannot stop a
recording; `surfaceGone` carries its cause, with an owner for every sender and the lint narrowed to match; a file
drag named as still opening the Shelf; the width spring re-keyed in D0 so no footprint change animates; the
sideways offset moved outermost so alerts follow the shape; wing facts kept apart so the notch and pill hover
zones stay as today; `DisplaySelectionTests` in the filter and zero-test runs refused; merge orders for four shared
files; `hardwareSize` stated as stricter than `ScreenCorners.hasNotch`; the built-in target change under REG-560;
the hold reducer run by the model so fixtures keep their wings, its sleep and lint scoped to the controller file,
a pause held only when the music wings were on screen; no import can select Notch; click protection called best
effort, with its costs in decisions 1 and 2; two unverified items now cited facts; a guide without text; no
dead-end status. The Mac checks moved into one table under Verification.

- Ending calibration when Settings sits behind another app: rejected. The owner clicks other windows to judge the
  shape, and the guide outline shows the state. Left to the owner (decision 7).
- A nil-animation transaction for draft changes: not used. `.animation(_:value:)` installs its spring whenever its
  value changes, so the key is changed instead, which a ZeusCore test can pin without a live view.
- Lock, sleep and session observers in `NotchController`: placed in `DrawnNotchModel`, so the lint-anchored
  `start()` is not edited. Same effect.
- P2's row in its own view file: not done. It would still add a line to the page file; a merge order covers it.
- U+2013 checks for app strings in the D1 tests: ZeusCore tests cannot read the app target; each ticket's lint does.
- One status with a button to General: split in two, since the button cannot help when no such display is connected.
