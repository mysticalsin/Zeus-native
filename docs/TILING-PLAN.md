# Tiling: plan and design

Written 14 November 2026 on `codex/island-20261113`. This is the spec, design note and task list for the first
slice of a keyboard-driven tiling window manager built into Zeus as its own section at the top of the app. It follows
`docs/DESIGN-DIRECTION.md` and the pure-rules-in-ZeusCore pattern used by `KeepAwakeRules`, `PermissionSweep` and the
notch plans. Nothing here is accepted until the named tests run on macOS and the behaviour is seen on a real Mac.

## What the owner asked for

A keyboard-driven tiling manager, as its own top-of-row section. You hold one modifier and tap a key: windows snap
into a gapped grid, and keys move focus, swap windows, flip a split and float a window. The first slice tiles the
windows of the current Space on each connected display. It uses public interfaces Zeus already relies on.

| Ticket | Scope | After |
| --- | --- | --- |
| T1 | Pure tiling engine (ZeusCore) | A Sendable split tree, frame math with gaps, a deterministic layout for N windows, insert, remove, swap, focus-move and ratio-adjust, plus the action and keybind model and the config value type, all unit tested with no window |
| T2 | Accessibility window driver (app) | Enumerate on-screen windows, apply the engine's frames through Accessibility, with an admission filter and a fail-closed path when Accessibility is denied |
| T3 | Key layer (app) | One modifier and the default binds, through an event tap that follows the SystemHUDEventTap isolation pattern, mapping a bound key to a pure action the engine resolves and the driver applies |
| T4 | Tiling section and overlay (app) | A top-of-row section with an on/off switch, the Accessibility state, the current layout and a keybind cheat sheet, plus a focus-border overlay |
| T5 | Settings (generator plus live window) | Enable tiling, the modifier choice, inner and outer gaps, and the core binds, through the settings catalog generator |

Deferred to the Spaces slice (a named later plan, because it needs private SkyLight or is large): workspaces and
moving windows between macOS Spaces, the scratchpad surface, tiled drag and swap with the mouse, maximise to the
padded area, saved layouts, a per-app window-rule system, and cross-display window send. The first slice names each
of those as out of scope and leaves them for that plan.

## Built from scratch

Binary space partition tiling is a public technique. Several keyboard window managers arrange windows this way: keep
a tree of splits, turn it into frames, split the focused slot for each new window, and move focus or swap by
direction. The engine, the frame math, the keymap and the controller in this plan are written from that public
algorithm, described in plain terms in the ticket bodies below. No other program's source, names, comments, test
cases, configuration format or wording is read while writing them, copied, ported or adapted. The Swift here is
original. Because nothing is copied, no attribution, licence notice or `NOTICES.md` entry is added or needed. This
matches Zeus's own rule: behaviour only, never another app's code, assets or names. No third-party product name
appears anywhere in Zeus source, settings, UI copy, tests or this plan.

## Privacy and consent

- Tiling is off until `tiling.enabled` is on. It defaults off because it reads other apps' window frames and moves
  their windows.
- The permission the first slice plans on is Accessibility, which Zeus already requests and tracks. No new permission,
  entitlement or capture is added on the current plan. One assumption, that a keyDown-consuming tap works on
  Accessibility alone, is proven on a real Mac first (see Permissions and the verification list); if it is wrong, a
  permission is added before shipping. No window title or content is read, stored or sent. No network.
- The Tiling section never raises a permission prompt. Prompts stay in the one place that already owns them. When
  Accessibility is off the section shows the off state and a button that opens the existing permission flow.

## Shared names and the coordinate rule

ZeusCore works in one abstract space: a top-left origin with y increasing downward, the same as Accessibility reports.
A small value rect type, `TileRect` (origin x, y, width, height as `Double`), keeps ZeusCore free of AppKit. The app
converts to and from AppKit coordinates once, at its own edge, using each display's visible frame so the menu bar,
Dock and notch are already excluded. ZeusCore never sees an `NSScreen`, a `CGRect` or an `AXUIElement`.

---

## T1. Pure tiling engine (ZeusCore)

Buildable alone, first. Every other ticket depends on these names, so T1 lands before T2, T3, T4 and T5 start.
No app file is touched. Files live under `Sources/ZeusCore/Tiling/`.

### Behaviour

- One window fills the display's usable area minus the outer gap on all four sides.
- Two windows split it, with the inner gap between them. A third window splits the newest slot, so tiles dwindle
  toward the right and bottom.
- Each split cuts the longer side of its slot, so wide slots become columns and tall slots become rows.
- A new window splits the focused slot, or the last-added slot when nothing is focused, and takes the second side.
- When a window leaves, its sibling takes the parent's whole slot and the tree collapses one level. The others keep
  their positions, so the layout does not reshuffle.
- A maximum depth (3 by default, so up to 8 tiles) and a minimum tile size stop unusable slivers. A window that does
  not fit is refused, and the caller leaves it floating.
- Focus-move by direction picks the nearest tiled window on that side from the computed frames, not from tree order.
- Swap by direction exchanges two slots and keeps focus on the moved window.
- Flip toggles the focused slot's parent split between side-by-side and stacked, and pins that axis.
- Ratio-adjust nudges the nearest matching split by a step, clamped.

### Rules (ZeusCore, pure)

`TileTree.swift`:

- `TileAxis`: `horizontal` (children side by side), `vertical` (children stacked).
- `TileNode`: an indirect enum, either `.leaf(window: TileWindowID)` or
  `.split(axis: TileAxis, ratio: Double, pinned: Bool, first: TileNode, second: TileNode)`. `Sendable`, `Equatable`.
- `TileWindowID`: a `Sendable`, `Hashable` value (pid plus a per-app window index the app assigns by element identity).
  ZeusCore treats it as opaque.
- `TileTree`: wraps an optional root `TileNode`, keyed to one display. `Sendable`, `Equatable`.
- `TileRatio.clamp(_:)`: clamps to `0.15 ... 0.85`; the default ratio is `0.5`.

`TileFrames.swift`:

- `TileRect`: x, y, width, height as `Double`; `inset(by:)`, helpers for edges, `isEmpty`.
- `TileFrames.frames(_ node:in rect:innerGap:)`: returns `[TileWindowID: TileRect]`. A leaf returns one entry for the
  whole rect. A horizontal split removes the inner gap once from the width, gives the first child `width * ratio`, the
  second child the remainder, with the gap between them; vertical does the same on height; recurse. Rounds each edge
  to whole points at the end so shared edges stay exact and there is no overlap or drift.
- `TileFrames.usableRect(display:outerGap:)`: the display rect inset by the outer gap on all four sides, clamped so
  it never inverts.

`TileOps.swift`:

- `TileOps.insert(_ window:into tree:focused:config:)`: picks the focused leaf, else the last leaf in insertion order;
  reads its frame; chooses the axis from the longer side; replaces the leaf with a split, old window first, new window
  second, at `config.defaultRatio` (the clamped split ratio, `0.5` unless the user changed it). Before accepting, checks
  depth against `config.maxDepth` and that both children meet
  `config.minTileSize`. On failure it tries the other leaves from last to first; if none fits it returns
  `.refused`, and the caller floats the window. An empty tree takes the window as the root leaf.
- `TileOps.remove(_ window:from tree:)`: replaces the parent split with the sibling subtree; a root leaf empties the
  tree. No other ratios change.
- `TileOps.swap(_ a:_ b:in tree:)`: swaps the two leaves' window ids and the two ids in the tree's order, so the newest
  slot stays the newest. Nothing else changes.
- `TileOps.flip(at window:in tree:)`: toggles the focused leaf's parent split axis and sets its pinned flag.
- `TileOps.nudgeRatio(at window:direction:step:in tree:)`: finds the nearest ancestor split whose axis matches the
  direction and in which the window lies on the matching side, adds or subtracts the step, clamps.
- `TileOps.neighbour(of window:direction:frames:)`: pure over the frame map. Candidates are windows whose frame lies
  fully beyond the focused frame's edge in that direction; score by cross-axis overlap (highest wins), then by edge
  distance (lowest), then by caller-supplied recency. Returns nil when nothing is that way. Works over the union of
  several displays' frames, so a later cross-display move reuses it.
- `TileOps.reconcile(tree:eligible:order:)`: removes ids no longer eligible, inserts new ids in discovery order,
  leaves the rest, and returns the new tree plus the ids it refused.

`TileAction.swift`:

- `TileDirection`: `left`, `right`, `up`, `down`.
- `TileAction`: `focus(TileDirection)`, `swap(TileDirection)`, `flipSplit`, `toggleFloat`, `togglePause`, `retile`,
  `nudge(TileDirection)`, `showKeys`. `maximizeToggle` is declared but documented as a later slice.

`TileKeybind.swift` (reuses `Sources/ZeusCore/Shortcut.swift`: `Shortcut` and `ShortcutModifiers`, so no parallel
chord type is added):

- `TileModifierBase`: `controlOption`, `optionCommand`, `controlOptionCommand`; `init(label:)` maps the stored strings,
  anything unknown falls back to `controlOption`; `modifiers` returns the `ShortcutModifiers` set.
- `TileKeymap`: maps a `Shortcut` to a `TileAction`. `defaults(base:)` is the one function that builds the default
  table. `action(for:)` is a lookup over an immutable copy. It rejects duplicate chords and rejects a chord that
  `Shortcut` reports invalid (a bare letter with no modifier), and any key chord without Control, Option or Command
  (Shift or Fn plus a key, a bare F key), because the tap consumes what the keymap binds. `action(for:)` ignores the
  fn flag that macOS adds to arrow and function keys, unless the chord was bound with it. `encode`/`decode` use a
  stable `Codable` form and skip unknown actions, so a newer file does not break an older build. `conflicts(with:)` returns the chords that collide
  with a supplied set of reserved shortcuts.

Default binds, base `B` (the chosen modifier set): `B` plus Left, Right, Up, Down is focus; `B` plus Shift plus an
arrow is swap; `B` plus J is flip; `B` plus T is float or tile; `B` plus P is pause or resume; `B` plus R is retile;
`B` plus Shift plus `[` and `B` plus Shift plus `]` are the ratio nudges, chosen so they do not clash with the arrows;
`B` plus K shows the keybind list. Number keys are left unbound for the Spaces slice.

`TileConfig.swift`:

- `TileConfig`: `enabled: Bool`, `paused: Bool`, `innerGap: Double`, `outerGap: Double`, `maxDepth: Int`,
  `minTileSize: Double`, `defaultRatio: Double`, `base: TileModifierBase`, `floating: Set<TileWindowID>`,
  `excludedBundleIDs: Set<String>`. An initializer clamps each gap to `0 ... 64`, `maxDepth` to `1 ... 4`,
  `minTileSize` to `120 ... 600`, and `defaultRatio` through `TileRatio.clamp` (`0.15 ... 0.85`, default `0.5`).
  Out-of-range or unknown stored values fall back to the default. `Sendable`, `Equatable`.

### Fail-closed paths

- A refused insert returns `.refused`; nothing is forced into a sliver.
- Focus-move with no neighbour returns nil; the caller does nothing (no wrap in this slice).
- A tiny display rect clamps the usable rect and the ratios so no frame inverts.
- Unknown or out-of-range config values fall back to the clamped default.

### Tests first (`Tests/ZeusCoreTests/TileEngineTests.swift`)

1. Frame math: N windows from 1 to 8 built by inserting in order over a wide rect; the frames cover the usable rect
   minus gaps exactly, do not overlap, and sit exactly one inner gap apart. The N=2, N=3 and N=4 shapes match the
   stated columns-and-rows result.
2. Determinism: the same ordered ids and the same rect always give the same frames.
3. Insert dwindle: the axis follows the longer side; a wide slot splits into columns, a tall slot into rows.
4. Depth and min size: an insert that would break depth or the minimum is refused, and the caller floats it.
5. Remove promotes the sibling into the parent slot and collapses one level; other windows keep their frames.
6. Swap exchanges two slots and leaves the tree shape and ratios unchanged.
7. Flip toggles the parent axis and pins it so a later insert does not undo it.
8. Ratio clamp at `0.15` and `0.85`; nudge finds the right split and clamps.
9. Focus-move direction from frames, including the overlap and distance tie-breaks, and nil when nothing is that way.
10. Reconcile removes gone ids, inserts new ids in order, keeps the rest, and reports refusals.
11. Keymap: every default chord is unique, every action has one default, a bare letter is rejected, a duplicate is
    rejected, decode skips an unknown action, and conflicts are reported against a reserved set.
12. Config: gaps, depth, min size and default ratio clamp; unknown values fall back.

---

## T2. Accessibility window driver (app)

New files under `Sources/Zeus/Tiling/`. No overlap with the top-bar or settings files, so T2 runs in its own worktree
in parallel with T3 and T5 after T1 lands.

### Behaviour

- A main-actor driver lists the standard windows of regular apps through the existing Accessibility helpers, keeps only
  the ones on the current Space, and applies the engine's frames. Accessibility reports an app's windows across every
  Space and has no reliable current-Space signal, and the one call that does, `CGSCopySpacesForWindows`, is private
  SkyLight and banned by the clean-room rule. So the driver restricts to the current Space with a public call: it keeps
  only the windows that appear in `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
  kCGNullWindowID)`, matched by owning pid and frame. Zeus already uses that call in `PrompterWindow`,
  `ExplanationScreenContext` and `AgentCardsUI`, so no new surface is added.
- It writes size, then position, then size again, for apps that clamp when moving between displays, and reads the
  frame back. A frame that already matches within one or two points is skipped, so the user does not see a cascade.
- A window that refuses to land is marked floating for this session and the layout rebuilds without it. There is no
  retry loop.
- The driver exposes a protocol so tests use a fake. The Accessibility version is the only real one.

### Rules and shape

- `TilingWindowDriver` protocol (shipped in `Sources/ZeusCore/Tiling/TileWindowDriver.swift`): `isTrusted`,
  `windows(config:) -> [TileWindowRef]`, `unreadPIDs`, `setFrame(_:for:) -> Bool`, `focus(_:)`,
  `displays() -> [TileDisplay]`. `TileWindowRef` carries the `TileWindowID` (the pid and a per-app number that is the
  element identity as far as ZeusCore goes), the bundle id and the frame in engine coordinates. `TileDisplay` carries
  the display id, its AppKit frames and its engine frame. `windows(config:)` reads every window fresh in the call: a
  window it could not read in time is left out, never reported from an earlier call, and its app's process id is in `unreadPIDs`.
  `setFrame` and `focus` act only on a window the last `windows(config:)` returned.
- `AXTilingWindowDriver` is the real one, main actor like `AXSnapshotter` and `AXFinder`, with a per-pass time budget.
  It builds `AXUIElementCreateApplication(pid)` per regular app, calls `AXUIElementSetMessagingTimeout(app, 0.25)` as
  `AXSnapshotter` does, reads `kAXWindowsAttribute`, and reads role, subrole, minimized, full-screen, position and
  size in one round trip with `AXUIElementCopyMultipleAttributeValues`. The pass budget is checked before every app
  and every window, and a hidden app is skipped. It writes with `AXUIElementSetAttributeValue`
  on `kAXPositionAttribute` then `kAXSizeAttribute` using `AXValueCreate`, and focuses by setting `kAXMainAttribute`
  and `kAXFocusedAttribute` and performing `kAXRaiseAction`. It reuses `AXFinder.frame(of:)`,
  `AXSnapshotter.quartzRect`, and `AXFinder.string`, `number` and `isSettable`. As shipped it reads and writes frames
  in engine coordinates directly with type-checked values and uses only `AXFinder.isSettable`.
- Coordinate conversion lives here. The engine's `TileRect` (top-left, y down) converts to the AppKit frame per
  display using that display's own height, not the main screen's, so a display above or left of the main one with a
  negative origin converts correctly.

### Admission filter (fail closed, enforced here and again in the engine inputs)

A window is tiled only when every property reads cleanly and all hold: the app's activation policy is regular and it
is not Zeus; role is `AXWindow` and subrole is `AXStandardWindow`; not minimized; not full-screen (`AXFullScreen`
false); resizable (`kAXSizeAttribute` settable); present in the on-screen window list (`CGWindowListCopyWindowInfo` with
`.optionOnScreenOnly` and `.excludeDesktopElements`, matched by pid and frame), which keeps the set to the current Space
without a private call; larger than the minimum size; and the bundle id is not in the user exclusion set. Everything else is ignored and never moved. System processes (Dock,
Control Center, Notification Center, Spotlight, loginwindow, SystemUIServer) are excluded by owner, role and subrole.
When any property is unreadable the window is left alone. Window identity is by pid plus `CFEqual` on the
`AXUIElement`; the private element-to-window-id bridge is not used. A gone-and-back element is treated as remove then
insert.

### Fail-closed paths

- Accessibility denied: the driver reports not trusted and does nothing. No frame is written.
- A window that refuses to move: after the write the frame is read back; a difference beyond the tolerance marks the
  window floating for the session and asks the controller to rebuild without it. Never retried in a loop.
- A hung app: the 0.25 s messaging timeout and the per-pass budget bound the cost. An app that does not answer in
  time is left out of the listing and its process id is in `unreadPIDs`; the controller keeps the slots of windows
  that belong to an unread app (`TilePlanner.slotsToKeep`) and writes to none of them. A window missing from an app that
  was read is gone, so one slow app never pins the slots of windows that closed in other apps.
- Two windows of one app at the same frame, one on another Space: the window list cannot tell them apart, so when more
  candidates share a frame than the list has entries for it, none of them is admitted.
- A stale element after an app quits: dropped on the next read.
- The driver's own writes fire move notifications: writes carry the intended frame, and the controller ignores a
  change that matches it, so the layout does not react to itself.

### Tests first (`Tests/ZeusCoreTests/TilingDriverTests.swift`, with `Tests/ZeusAppTests/TilingDriverTests.swift`)

As shipped, the pure rules are in ZeusCoreTests under the parent suite `TilingDriverTests`, so
`swift test --filter TilingDriverTests` runs them. The app target keeps only the trust and no-element tests of the real
driver (`.serialized`), also named `TilingDriverTests`. The list below is the intent.

Coordinate conversion round-trips for an ordinary display, a display at a negative origin, and a second display to
the right and above; the admission filter drops Zeus's own window, a system window, a sheet, a minimized window, a
full-screen window and a window absent from the supplied on-screen list (its other-Space stand-in), and accepts a plain
standard window that is in the list; a write that reads back wrong marks the window floating; a matching frame is
skipped. The filter takes the on-screen list as an injected input so the fake can feed it, and the real Accessibility
and `CGWindowListCopyWindowInfo` path is proven on a Mac, not in this suite.

---

## T3. Key layer (app)

New files under `Sources/Zeus/Tiling/`, plus one edit to the source lint. T3 runs in parallel with T2 and T5 after T1.
It must not touch the top-bar or settings files.

### Behaviour

- One chosen modifier is held, then a key is tapped. A bound key runs its pure `TileAction`; an unbound key passes
  through untouched. Zeus never launches an app and never consumes a key the user did not bind.
- The tap consumes the matched chord and the matching key-up, and passes everything else through.

### Rules and shape (follows `Sources/Zeus/TopBar/SystemHUDEventTap.swift` and `Sources/Zeus/Pointing/PointingEventTap.swift`)

- `TilingKeyTap` is a `final class ... : @unchecked Sendable` with an `NSLock`. The callback is a file-private global
  C function that reaches the owner through `userInfo` with `Unmanaged`. The tap and the callback are never inside a
  `@MainActor` type, because Swift 6 inserts an executor check and Zeus traps at run time on the first call.
- `start()` and `stop()` are `nonisolated` and are the only places that call `CGEvent.tapCreate`
  (`.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`, because the tap must consume the chord). They add and
  remove the source on `CFRunLoopGetMain()` in `.commonModes`; `stop()` disables the tap, removes the source and calls
  `CFMachPortInvalidate`. The tap is created only when `AccessibilityGate.trusted`, re-armed through
  `AccessibilityGate.whenTrusted(key: "tiling")`, and never left installed when tiling is off.
- The callback stays tiny: it builds a `ShortcutEvent` (`Sources/ZeusCore/Shortcut.swift`), masks modifiers as
  `PointingEventTap` does, looks the chord up in an immutable, lock-protected keymap snapshot, returns nil to consume
  or passes the event through, and hands the matched action to the main actor (assume isolation when already on main,
  else dispatch to main). All Accessibility work runs after the callback returns.
- It re-enables itself on `.tapDisabledByTimeout` and `.tapDisabledByUserInput`. It ignores autorepeat for the toggle
  actions and allows it for focus and ratio. It passes through every event that carries Zeus's own input tag
  (`DriveInputAttribution.eventTag`). It consumes the key-up for every consumed key-down, tracked in a small set.
- There is no fallback global monitor: a global monitor cannot consume, so on failure the tap reports unavailable and
  the section shows a cue, as `PointingHotkeyMonitor.onUnavailable` does. Live window-change observers are not added in
  this slice; the controller re-reads after each action and on app activate, launch and terminate.

### Source lint

Extend `qa/closed-loop/tests/test_source_lint.py` so the nonisolated-callback check that scans `Sources/Zeus/Pointing`
also scans `Sources/Zeus/Tiling`, and add `AXObserverCreate` to its watched callback APIs for the later observer
upgrade. Add a fail-first sample as the file already does for the pointing case. This is the only shared file T3
touches, and no other ticket edits it.

### Fail-closed paths

- Accessibility denied: no tap is installed.
- The tap is disabled by the system: it is re-enabled; if it keeps failing the controller pauses tiling and the
  section shows the state.
- Tiling paused or off, or a secure input field active: every event passes through.
- A slow callback would get the tap disabled, so no Accessibility work happens inside it.

### Tests first (`Tests/ZeusCoreTests/TileKeymapTests.swift` plus a lint fail-first sample)

The keymap tests are the pure ones already listed under T1 (unique defaults, invalid and duplicate chords rejected,
conflicts reported). The lint sample proves a `CGEvent.tapCreate` in a non-`nonisolated` func under
`Sources/Zeus/Tiling` fails the check.

---

## T4. Tiling section and overlay (app)

T4 edits the top-bar files and `AppDelegate`, and it wires together the controller (T2, T3), the config readers (T5)
and the permission state. It runs last, after T1, T2, T3 and T5, and it is the only ticket that edits
`TopBarLayout.swift`, `TopBarModel.swift`, `TopBarViews.swift`, `StartupPolicy.swift`, `AppDelegate.swift` and the
row-capacity tests, so nothing conflicts with it.

### Behaviour

- A new section sits at the top of the row (index 1, right after Home). It shows an on/off switch, a pause state, the
  Accessibility permission state, the inner and outer gap, the modifier choice and a read-only keybind list.
- A focus-border overlay marks the focused tiled window. It is click-through, joins every Space, never takes focus,
  and is hidden from screen sharing unless the user turned sharing on.

### Rules and wiring

- `TopBarTab` (`Sources/ZeusCore/TopBar/TopBarLayout.swift`): append `case tiling` after `waves`. Two switches are
  exhaustive and force a new case at compile time: `title` returns "Tiling" and `symbol` returns
  `rectangle.split.2x2.fill` (confirmed on macOS). The `help` switch ends in `default: title`, so a `tiling` case there
  is optional copy, not compiler-forced; add one anyway, "Tiling: arrange your windows from the keyboard", so the
  tooltip reads well. Put it at index 1 by editing `defaultRow` so it
  reads `[.home, .tiling, .agents] + glanceSeven.dropFirst() + [...]`; `standard` follows. Add
  `upgradedToTilingRow()` modelled on `upgradedToAgentsRow`.
- `TopBarModel.swift`: add the one-time upgrade with flag `topBar.row14.v1`, set only when not a snapshot and not QA,
  applied with `upgradedToTilingRow()`, and added to the save condition, so the row is not lost on relaunch.
- `TodoSync.swift`: add `.tiling` to `TopBarLayoutRepair.upgradeTabs` and bump its version so a launch that saved the
  flag but not the row is repaired.
- `TopBarViews.swift`: add `case .tiling: TilingPage(topBar: topBar, tiling: .shared)` to the exhaustive
  `TopBarPage.body` switch. `TilingPage` lives in `Sources/Zeus/TopBar/TilingPage.swift`. It must render with no
  Accessibility or overlay call when `TopBarStyle.isSnapshot` is true, because the snapshot renderer loops over every
  tab.
- `StartupPolicy.swift`: add `case tiling` to `StartupService`; QA startup denies it like the rest.
- `AppDelegate`: start the controller in one gated block beside the pointing block, `if on(.tiling) {
  TilingController.shared.start() }`, with a `syncTiling()` that observes `UserDefaults.didChangeNotification` as
  `syncPointing` does, and register the overlay in the capture-visibility boost list beside the other overlays.
- `TilingController` (main actor, `Sources/Zeus/Tiling/TilingController.swift`): owns one `TileTree` per display,
  the `TileConfig` read from settings, the driver and the key tap. It builds `TileConfig` from the `FeatureSettings`
  readers, turning the `tilingSplitRatio` percentage (30 to 70) into `defaultRatio` (0.30 to 0.70) so the "Default
  split" setting actually moves the split, with `TileConfig`'s clamp as the backstop. An action edits the pure tree,
  then one apply step
  diffs old and new frames and writes only the changed windows. On `didChangeScreenParameters`,
  `activeSpaceDidChange`, `willSleep` and `didWake` it cancels any in-flight apply with a generation counter, rebuilds
  the trees from what is visible, and retiles once. A frontmost full-screen app pauses applying until it ends.

### Row capacity (owner decision)

`GlanceTopBar.maxTabs` is 13 and `defaultRow` is already 13, so a 14th default tab pushes one tab off the visible row.
Two clean options, for the owner to pick:

- (a) Raise `maxTabs` to 14 and drop `tabSpacing` from 12 to about 8, which keeps the worst-case width under the row
  room.
- (b) Keep 13 and demote one current default tab (for example Record) to one click away in Settings.

Either way the row-count and index tests in `Tests/ZeusCoreTests/TopBarLayoutUpgradeTests.swift` and
`GlanceTopBarTests.swift` are updated to match. This is a decision, not a default this plan makes.

### Design

- `TilingPage` follows the other `*Page` structs: an enable toggle, a pause control, a permission row that reuses
  `PermissionSweep` and `PermissionsModel` and opens the existing flow, the two gap values, the modifier picker, and a
  read-only keybind list fed from the ZeusCore keymap so it never drifts from what the tap matches. Status is shown by
  shape and word, never by colour alone. Uses Zeus tokens (`Theme.accent`, `Theme.bolt`).
- `TilingFocusBorder` (`Sources/Zeus/Tiling/TilingFocusBorder.swift`, main actor) follows `EdgeWaveController` and
  `ScreenEdgeGlowController`: one `NSPanel` per display or a single reused panel, borderless and non-activating,
  `isOpaque` false, clear background, no shadow, ignores the mouse, never key or main, not released when closed,
  collection behaviour `canJoinAllSpaces`, `stationary`, `fullScreenAuxiliary`, `ignoresCycle`. It uses level
  `.floating`, not `.statusBar`, so it does not draw over the notch window. It draws a rounded stroke in a SwiftUI
  `Canvas`. It is event-driven: shown on a focus or move change, repositioned on a frame change, ordered out when
  tiling is off, when the focused window is excluded, minimized or full-screen, and under snapshots. It respects
  Reduce Motion and Reduce Transparency, and it registers with `ZeusWindowSharing.apply` and `refresh` with surface
  `.zeusStandard`, as the other overlays do.
- A keybind cheat sheet panel is shown on `TileAction.showKeys` and hidden on the next key or a short timer, at
  `.statusBar` level, built from the same ZeusCore keybind table, dismissible by Escape through the tap. Write a
  `DESIGN.md` for the section and overlays before building, per the standing rule and `docs/DESIGN-DIRECTION.md`.

### As shipped (T4)

- Row capacity, option (a): `GlanceTopBar.maxTabs` is 14 and `tabSpacing` is 8, so the worst case (the widest label and
  three 3-digit counts) is 796.75 of the 803 point row room. Tiling is second in `defaultRow`. `TopBarLayout.toggle`
  keeps Tiling at its place after Home (a private canonical order), so a tab switched back on never lands in front of
  it. The flag is `topBar.row14.v1`, saved with the row; `TopBarLayoutRepair.version` is 2.
- Pure rules in ZeusCore (`Sources/ZeusCore/Tiling/`): `TilingPhase`, `TileGeneration`, `TileResolver` with
  `TileLayoutState` and `TileEffect`, `TilingPicture`, `TileKeyList`, `TileConfig.fromSettings`, `TileFrontmost`, and
  `TileModifierBase.label` and `glyphs`. They are tested by `TilingSectionTests`.
- The driver protocol gained one requirement with a default (nothing in front): `frontmost() -> TileFrontmost`, the
  focused admitted window and whether the front app is full screen. `AXTilingWindowDriver` reads it with two
  Accessibility reads. The controller needs it to know which window the keys act on and to pause over a full-screen app.
- `TilingController` takes its parts as `Services` (driver, key layer, config reader, scheduler, notification centres,
  overlay closures, settings writer), so the controller suite runs against a fake driver that uses the real admission
  filter. Seven system notifications are observed, only while Accessibility is on: screen parameters, Space, sleep,
  wake, and app activate, launch and terminate. A display, Space, sleep or wake change advances the generation counter.
- No Accessibility move observers and no `TileSelfWrites`: this slice re-reads on those seven events and after each
  action, so the controller does not react to its own writes. The pre-tiling frames are kept for a later undo and are
  never restored.
- The key sheet hides on a six second timer, on the next tiling key, and when tiling stops. It does not take Escape:
  the tap sees only chords the owner bound, and the rule that Zeus never consumes an unbound key is kept.
- Key clash, closed in the review pass: `TileBaseConflicts.notes` compares the tiling keys with the keys the other
  monitors really use. The talk key is the effective one (`VoiceKey.effectiveTalkKey`), which moves off Control-Option
  while VoiceOver runs; a modifier-only talk, pointing or dictation key with the same modifiers as the chosen pair is a
  clash (a larger pair is clear); every bound tiling chord (base plus key) is compared with every keyed talk, pointing
  and dictation shortcut, with the fn flag handled as the tap handles it; a chat chord the keymap binds is a clash; and
  the Control-Option pair is refused while VoiceOver runs. The controller checks it on every settings write, before
  any tap exists, and refuses a clash: no tap, no observer, the phase is Key clash, and the page and Settings show the
  note. VoiceOver writes no setting, so the controller watches it (key value observing on the workspace) from the
  first start with the switch on until the switch goes off, including while a clash holds tiling back, and checks the
  clash again when VoiceOver starts or stops. The tap consumes a chord before the other keys' monitors can see it
  spoil a hold, so refusing is the only fail-closed option. The default pair is Control-Option-Command: no shipped key
  holds it (Talk to Zeus and pointing are Control-Option, dictation is Right Command, Talk to Zeus moves to
  Option-Command while VoiceOver runs), and `TileBaseConflictsTests` keeps it that way. An unknown stored pair reads
  as the default.
- Other review fixes: the pause and key sheet chords work over a full-screen app; swap, flip, nudge and float do nothing
  while an app tiling does not read has the keyboard; the ring follows its setting while running; a revoked
  Accessibility is noticed on a settings change; `frontmost()` skips Zeus itself and has no protocol default; the undo
  memory drops windows that are gone; an equal settings write does not notify the page; the key pair picker shows a
  check on the chosen pair; the permission row reads again when Zeus is activated; quitting stops tiling only when the
  startup service is allowed.
- Not done here, still open: the acceptance-map decision in `qa/feature-map.json`.

### Fail-closed paths

- Accessibility denied: the section shows the off state and the permission row; no controller start, no tap, no
  overlay.
- Snapshot render: the page and overlay draw fixed, with no Accessibility or overlay side effect.
- Turn off or pause: the controller stops writing frames and leaves windows where they are. It remembers the
  pre-tiling frames for a later "undo layout", but does not restore in this slice.
- Display or Space change mid-apply: the generation counter drops the stale apply and the trees rebuild.

### Tests first (`Tests/ZeusAppTests/TilingOverlayTests.swift` and `TilingControllerTests.swift`, `.serialized`)

The overlay suite follows `PointingOverlayTests`: never key or main, ignores the mouse, non-activating,
`sharingType == .none`, removed on hide, vacuous with no display. The controller suite uses the fake
`TilingWindowDriver` and checks every fail-closed path: Accessibility denied, a move refused, a display change, a
full-screen app frontmost, a minimized window, Zeus's own window and a system window all left alone. The refused-to-floating
step belongs to this suite: ids in `TileApplyOutcome.refused` are added to `TileConfig.floating` for the session and
the tree is rebuilt without them, while `deferred` ids are not floated. It also checks that a window missing from a
listing keeps its slot and is not written when its app is in `unreadPIDs`, and loses it when its app was read.

---

## T5. Settings (generator plus live window)

T5 edits the settings generator and the live settings window and readers. Its file set does not overlap T2 or T3, so
it runs in parallel with them after T1. T4 reads the ids T5 creates, so T5 lands before T4 integrates.

### Rows (added to the table in `scripts/gen-settings-catalog.py`)

- `tiling.enabled` (toggle, default `false`): "Arrange my windows from the keyboard".
- `tiling.keyBase` (choice, Control-Option, Option-Command, Control-Option-Command, default Control-Option-Command):
  "Tiling keys".
- `tiling.innerGap` and `tiling.outerGap` (sliders, 0 to 64, default 8): "Gap between windows" and "Gap to the screen
  edge".
- `tiling.splitRatio` (slider, 30 to 70 step 5, default 50): "Default split".
- `tiling.focusBorder` (toggle, default on): "Ring the focused window".
- `tiling.excludedApps` (text, bundle ids): "Apps Zeus never tiles".

Add a section key `tiling` to `SECTION_TITLES` with title "Tiling". Every note starts with "Zeus addition." and uses
`-` in the reference columns, since no third-party name may appear. Add `tiling.enabled` to the `opt_in` tuple in
`validate_table` so the generator refuses a true default, and add it to the key list in
`qa/closed-loop/tests/test_settings_catalog.py`. Regenerate both outputs with
`python3 scripts/gen-settings-catalog.py . docs/settings-inventory.md`, which writes `SettingsCatalog.swift` and the
inventory; never hand-edit either. `scripts/check-settings-catalog.sh` must pass.

### Readers and the live window

- `FeatureSettings.swift`: add `tilingEnabled`, `tilingInnerGap`, `tilingOuterGap`, `tilingSplitRatio`,
  `tilingFocusBorder`, `tilingKeyBase` and `tilingExcludedApps`, reading through `bool(_:default:)` and the number and
  string readers, with every default equal to the catalog default.
- `GlanceSettingsWindow.swift`: add `case tiling` to `GSSection`, its `group` (`.tools`), `title` and `symbol`.
- `GlanceSettingsPages.swift`: route `.tiling` to a new `TilingSettingsPage` in `Sources/Zeus/Settings/GSTilingPage.swift`,
  built from `GSPageHeading`, `GSCard`, `GSToggleRow`, `GSRow`, `GSPopup`, `GSInfo` and `store.boolBinding`, following
  `GSFeaturesPage`. The route satisfies the lint that every `*Page` and `*Card` under Settings is placed.

### Fail-closed paths

- `tiling.enabled` defaults off, so nothing moves a window until the user turns it on.
- An unknown stored gap, ratio or key base falls back to the catalog default through `TileConfig`'s clamp.

### Tests first

The catalog freshness check (`test_catalog_and_inventory_match_the_generator`) and the opt-in default test cover the
rows. The `TileConfig` engine tests assert the defaults of the values `TileConfig` actually carries against the catalog:
the two gaps, `maxDepth`, `minTileSize`, `base`, and `defaultRatio` (the catalog's 50 percent as `0.5`). The two
settings that no `TileConfig` field holds, `tiling.focusBorder` and `tiling.splitRatio` as the raw percentage the UI
shows, are covered by a plain `FeatureSettings`-versus-catalog default test instead, so no setting is left unchecked and
none is tied to a field it does not map to.

---

## Permissions

Accessibility is the one permission the first slice plans on, and Zeus already requests and tracks it:
`PermissionSweep.Item.accessibility` (ZeusCore) and `PermissionsModel.Kind.accessibility` (app), with
`AccessibilityGate` for the no-prompt retry. The plan is that the consuming key tap runs on the Accessibility trust the
app already holds, so no Input Monitoring is requested.

This rests on an assumption that must be proven on a real Mac before the slice ships, because Zeus has no existing
keyDown-consuming tap to lean on. `SystemHUDEventTap` consumes system-defined media events (CGEvent type 14), not
keyDown, and `PointingEventTap` is a `.listenOnly` tap whose own comment says `.listenOnly` needs Input Monitoring. So
the only safe claim now is that an active `.defaultTap` that consumes keyDown should work on Accessibility alone, not
that a Zeus precedent shows it. The real-Mac check in the verification list below confirms it: with Accessibility
granted and Input Monitoring denied, a bound chord is consumed and an unbound key passes through. If that run shows
Input Monitoring is in fact required for the keyDown `.defaultTap`, this section and the privacy section are revised to
add a permission (a new `PermissionSweep` item and `PermissionsModel.Kind`) before shipping, and the Tiling section
shows that second state.

On the current plan, with that check passing, no new `PermissionSweep` item, no new `PermissionsModel.Kind`, no
Info.plist usage string, and no prompt from the Tiling section are needed. The section shows the Accessibility state and
routes to the one existing place that prompts.

## Parallel build and sequencing

- T1 (ZeusCore engine) builds alone, first. Every other ticket depends on its names.
- T2 (driver), T3 (key tap plus the one lint edit) and T5 (settings) then build in separate worktrees in parallel.
  Their file sets do not overlap: T2 adds driver files under `Sources/Zeus/Tiling`, T3 adds tap files there plus edits
  `qa/closed-loop/tests/test_source_lint.py`, and T5 edits the generator, the live settings files and
  `FeatureSettings`.
- T4 (section and overlay) integrates last. It is the only ticket that edits `TopBarLayout.swift`,
  `TopBarModel.swift`, `TopBarViews.swift`, `TodoSync.swift`, `StartupPolicy.swift`, `AppDelegate.swift` and the
  row-capacity tests, and it wires the controller, tap, overlay, permission row and config readers from the earlier
  tickets together.

## Owner decisions before T4

- Row capacity: option (a) 14 tabs with tighter spacing, or (b) demote one default tab.
- Whether Tiling joins the finite acceptance map in `qa/feature-map.json`. That schema pins exactly 19 features and
  the contract checks the exact id set, so adding one means editing the schema, the id list and the contract, plus a
  feature entry with a portable or native check and an `unimplemented` device-proof entry for the real-Mac run that
  does not exist yet. If the owner prefers, bind the Tiling tests in `qa/regressions.json` instead and leave the
  acceptance map at 19.
- The default modifier base, decided in the review pass: Control-Option-Command, because Control-Option is already
  Talk to Zeus and pointing, VoiceOver uses it, and Control-Option-Space is the chat hotkey. The chosen base is
  validated by `TileBaseConflicts` against talk, pointing, dictation, chat and VoiceOver, a conflict note is shown, and
  the base stays user-selectable. Reverting to Control-Option is one commit if the owner prefers it.

## Verification for this slice

1. The named tests are committed before the code and shown failing on the base (the build fails on the missing names).
2. `swift build --build-tests`, then `swift test --filter` for each new suite: `TileEngineTests`, `TileKeymapTests`,
   `TilingDriverTests`, `TilingOverlayTests`, `TilingControllerTests`.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared, allowing for the known base failures in
   "Native host process boundaries".
4. The settings generator and `scripts/check-settings-catalog.sh`; the Python source lints, including the extended
   nonisolated-callback check over `Sources/Zeus/Tiling`, and `test_alerts_lint.py`.
5. `./tools/check.sh` development mode.
6. A grep of the whole diff for any third-party product name and for em or en dash characters, both of which must find
   nothing.
7. An independent review of each diff.
8. Still owed on a real Mac, not covered by the automated checks: the permission check first, with Accessibility
   granted and Input Monitoring denied, that a bound chord is consumed and an unbound key passes through, which decides
   whether the no-new-permission plan holds; then windows snapping into the layout with one and two displays and 1 to 5
   windows; focus, swap, flip, float and pause from the keyboard; a denied-Accessibility run showing the off state and
   no tap; a stubborn fixed-size window marked floating instead of fought; a display-unplug run rebuilding cleanly; and
   the focus border and cheat sheet seen in place and absent from a screen share.
