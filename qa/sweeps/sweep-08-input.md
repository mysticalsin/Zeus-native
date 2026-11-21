# Sweep 08 — input, hotkeys, and gestures

Lens: modifier keys, global hotkeys, event taps, and top-bar pointer gestures.

Read first: bug ledger `specs/bugs/ledger.md` on `zeus-bot/bug-ledger` at `255e52aba94234e2b194fd81b2cf4b93e628cc93` (PR #54). ZB-001 through ZB-035 were checked. One row below is the same defect as ZB-003. The rest are not in that ledger.

Required behaviour this sweep held the code to:

- Right Command starts Murmur.
- Holding Right Option talks to Zeus.
- The top bar distinguishes a click, a double-click, a triple-click, and a right swipe.
- Existing hold menus stay available.

Heads read, not merged:

| Head | SHA | Role |
| --- | --- | --- |
| `codex/integration-20261111` | `2722dcb7497d5415fbc1fcb1f65c49629966a281` | Talk key, dictation key, event taps, permissions |
| `zeus-bot/fix-topbar-core` (PR #57) | `3cde0156a0cf02cc928b6cbd8382a416713bcd81` | `NotchGestureAdapter` |
| `zeus-bot/murmur-mic-first` (PR #21) | `6a57313b5b53f8452b56e2059961b311475371f9` | Mic opens on Right Command down |
| `zeus-bot/right-command-toggle` (PR #81) | `817c4219cf7c3630634544340e42b53ff0f0452d` | Right Command tap, unused `TalkHold` |
| `zeus-bot/settings-weather` (PR #42) | `d0a9000861a61850e8ae396c01b142cce6343748` | `TopBarGestureRouter` (click, double-click, triple-click, right swipe, hold menu) |

This file is notes from those trees. The sketches were not executed here. Linux cannot open the macOS event stream. A sketch marked static can fail in `swift test` on the named types with no window server. A sketch marked device needs a Mac with Accessibility granted, then revoked, or more than one display.

Shelf hold menus (`contextMenu` in `Sources/Zeus/TopBar/TopBarViews.swift`) are still present on integration. The new `holdMenu` route has no caller. That gap is S08-01.

## Findings

| ID | Severity | Branch / SHA | File:line | Owning PR or area | Ledger |
| --- | --- | --- | --- | --- | --- |
| S08-01 | P1 | #57 `3cde0156`; #42 `d0a90008` | `NotchController.swift:71`; `WeatherSettingsSection.swift:74` | #57 and #42, top bar | duplicate of ZB-003 |
| S08-02 | P1 | #57 `3cde0156` | `NotchController.swift:105` | #57, top bar | |
| S08-03 | P1 | #57 `3cde0156` | `NotchController.swift:531` | #57, top bar | |
| S08-04 | P1 | #57 `3cde0156` | `NotchGestureAdapter.swift:98` | #57, top bar | |
| S08-05 | P1 | #57 `3cde0156` | `NotchGestureAdapter.swift:154` | #57, top bar | |
| S08-06 | P1 | #57 `3cde0156`; #42 `d0a90008` | `NotchController.swift:117`; `TopBarGestureRouter.swift:143` | #57 and #42, top bar | |
| S08-07 | P2 | #57 `3cde0156`; integration `2722dcb7` | `NotchController.swift:553`; `NotchOpenTrigger.swift:38` | #57, top bar | |
| S08-08 | P0 | #81 `817c4219`; integration `2722dcb7` | `AppDelegate.swift:328`; `VoiceKeyMachine.swift:435` | #81, Murmur and talk | |
| S08-09 | P1 | #81 `817c4219` | `HotkeyMonitor.swift:299` | #81, Right Command | |
| S08-10 | P1 | integration `2722dcb7`; #81 `817c4219` | `VoiceKeyMachine.swift:327`; `HotkeyMonitor.swift:297` | Talk, Murmur, #81 | |
| S08-11 | P2 | integration `2722dcb7` | `Shortcut.swift:346` | Talk and Murmur | |
| S08-12 | P1 | integration `2722dcb7` | `SystemHUDEventTap.swift:40` | Top bar media keys; tiling | |
| S08-13 | P1 | integration `2722dcb7` | `HotkeyMonitor.swift:41`; `PermissionsModel.swift:631` | Permissions and hotkeys | |
| S08-14 | P2 | integration `2722dcb7` | `Shortcut.swift:225`; `VoiceKey.swift:72` | Shortcuts | |
| S08-15 | P2 | #21 `6a57313b` | `InsertTargetDecision.swift:46` | #21, Murmur | |
| S08-16 | P2 | #81 `817c4219` | `TalkHold.swift:12`; `HotkeyMonitor.swift:81` | #81, Right Option | |
| S08-17 | P3 | #57 `3cde0156` | `NotchGestureAdapter.swift:90` | #57, top bar | |

### S08-01 — samples never become a route

Severity: P1. Duplicate of ZB-003.

`zeus-bot/fix-topbar-core` `3cde0156`, `Sources/Zeus/Notch/NotchController.swift:71` and `:563`. `onNotchGesture` is `{ _ in }`. No other file on that head assigns it. `performGesture` emits `down`, `up`, `hold`, `settle`, and `swipeRight` into that closure.

`zeus-bot/settings-weather` `d0a90008`, `Sources/Zeus/Settings/GlassShell/Sections/WeatherSettingsSection.swift:74`. The settings preview sends only `.trackpad`. ZB-003 already records that click, hold, and right swipe are never handed to `TopBarGestureRouter`.

The two types also disagree. `NotchPointerSample.swipeRight` carries a distance (`NotchGestureAdapter.swift:35`). `TopBarPointerSample.swipeRight` does not (`TopBarGestureRouter.swift:31`). The adapter emits no `.move` and no `.trackpad`. The router’s hold slop and its face change both need those.

Owning area: PR #57 for the adapter, PR #42 for the router. ZB-003 asked for this wiring.

Sketch, static: construct `NotchGestureAdapter`, reduce down, up, and a settle tick, and assert the app’s route list stays empty because `onNotchGesture` is still the default. On #42, assert the only `TopBarPointerSample` built under `Sources/Zeus` is `.trackpad` (the check `tests/bug-repros/TopBarGesturesUnwired.sh` on the ledger branch already exits 1 for that).

### S08-02 — the panel opens on mouse-down, before hold or multi-click

Severity: P1.

`3cde0156`, `Sources/Zeus/Notch/NotchController.swift:105` and `:113`. The global and local left-mouse-down monitors call `ingestMouseDown` and then `openOnClick` in the same turn. `openOnClick` (`:582`) opens the panel when the trigger is Click and the point is in the zone. The adapter’s hold is 0.5 s and its settle is 0.35 s (`NotchGestureAdapter.swift:47-48`). Those timers have not run yet.

A hold that should keep a menu, and a double-click or triple-click, all begin by opening the panel on the first down.

Owning area: PR #57, top bar.

Sketch, static, on the controller with a fake clock and Click as the trigger: one `leftMouseDown` in the zone leaves `presentation == .panel` before any settle sample. A second and third down cannot be the gesture that opens.

### S08-03 — tap and hold are classified by dequeue time

Severity: P1.

`3cde0156`, `Sources/Zeus/Notch/NotchController.swift:531`, `:543`, and `:570`. Down, move, up, and the timer tick are stamped with `Date()` at the moment the main actor handles them. `NSEvent.timestamp` is unused. The timer sleeps `wake.timeIntervalSinceNow` (`:566`).

The voice monitors do the other thing: `HotkeyMonitor.feed` on integration stamps the machine with the event time (`HotkeyMonitor.swift:196` at `2722dcb7`).

If down is handled and the up event waits behind more than 0.5 s of main-actor work, the hold timer fires and the release is a hold. If down and up are both already queued and run back to back after a stall, both stamps are nearly the same and a long physical hold becomes a click.

Owning area: PR #57, top bar. Race between a tap and a hold.

Sketch, static: feed the adapter through the controller’s reduce calls using `Date()` taken after a 0.6 s gap between down and up. Expect `.hold`. The same two events stamped with `event.timestamp` 0.1 s apart expect `.up` and then `.settle`, and no `.hold`.

### S08-04 — a missed mouse-up sticks the gesture

Severity: P1.

`3cde0156`, `Sources/ZeusCore/TopBar/NotchGestureAdapter.swift:98`. A down that arrives while `phase` is `.pressed` returns no effects and does not change phase. The matching up is the only way out, apart from `.cancel`.

`NotchController.refreshDisplays` (`:742`) rebuilds panels on a display change and orders them forward on space, wake, and lock (`:137`, `:143`, `:148`). None of those call `notchGestures.reduce(.cancel)`. A global mouse-up that the monitor never sees (Accessibility dropped, space switch, the run loop stalled) leaves the adapter pressed. Every later down is ignored, so click, double-click, triple-click, and right swipe stop.

Owning area: PR #57, top bar. Stuck pointer state.

Sketch, static: `down`, then `down` again, then `up`. The second `down` emits nothing. After the first `up`, a further `down` works. `refreshDisplays` during `.pressed` leaves `.pressed`.

### S08-05 — double-click and triple-click depend on the event’s click count

Severity: P1.

`3cde0156`, `Sources/ZeusCore/TopBar/NotchGestureAdapter.swift:153-158`. `begin` stores `max(clickCount, 1)` from the event. A down during `.settling` (`:96`) calls `begin` again and does not add one to the click count already stored. The closed notch is click-through (`ignoresMouseEvents = true` in `build`, `:789` on this head). The window under the pointer, often the menu bar, owns AppKit’s click count. A stream of `clickCount == 1` settles as one click.

`TopBarGestureRouter.route` on `d0a90008` (`TopBarGestureRouter.swift:132-136`) maps 2 to double-click and 3 or more to triple-click. It never sees a 2 if the adapter only emits 1.

Owning area: PR #57, top bar. The router on PR #42 is the consumer once S08-01 is wired.

Sketch, static: down/up with `clickCount` 1, down/up with `clickCount` 1 inside 0.35 s, then the settle tick. The settle sample’s count is 1. The same sequence with the adapter counting downs during `.settling` yields 2. Device: click the closed pill twice on a notch-less display and record `NSEvent.clickCount` on the global monitor.

### S08-06 — a trackpad swipe and a mouse drag are different gestures

Severity: P1.

`3cde0156`, `Sources/Zeus/Notch/NotchController.swift:117-125`. The gesture monitors subscribe to `leftMouseDragged` only. There is no `scrollWheel` and no `swipe` monitor. A two-finger trackpad swipe never becomes `move`, so `NotchGestureAdapter` (`:105-108`) never emits `swipeRight` for it. A mouse drag of 36 pt to the right does.

`d0a90008`, `Sources/ZeusCore/Settings/Sections/Weather/TopBarGestureRouter.swift:140-145`. `finishTrackpad` returns `showWeather` when `dx < 0` on the player face, and `showPlayer` when `dx > 0` on the weather face. A rightward trackpad delta on the player returns nil. It does not return `.rightSwipe`. `.rightSwipe` is only the unit sample `.swipeRight` (`:78`). The settings preview (`WeatherSettingsSection.swift:74`) sends the trackpad sample only.

Owning area: PR #57 and PR #42, top bar.

Sketch, static: router receives `.trackpad(deltaX: 40, deltaY: 0, ended: true)` on the player face and the route is nil. The same distance as `.swipeRight` is `.rightSwipe`. Adapter: a `move` with `dx >= 36` emits `swipeRight`; no API accepts a scroll delta.

### S08-07 — the zone is one display, and the notch-less pill sits on the menu bar

Severity: P2.

`3cde0156`, `Sources/Zeus/Notch/NotchController.swift:553-556`. `pointerIsOnNotch` tests the active `screen` only. `ingestMouseDown` does not call `followPointer` first. `followPointer` (`:752-756`) updates the active display only while the panel is closed. `build` (`:802-803`) sets `screen` to `panels.first` after every rebuild.

Integration `2722dcb7`, `Sources/ZeusCore/TopBar/NotchOpenTrigger.swift:38-40`. A display without a notch gets a click zone 120 pt wide (`slimPillSize.width` 96 plus 12 pt each side) and 14 pt tall, hung from the top edge. The closed panel does not take the click, so the menu bar in that rectangle takes it too. A right swipe that starts there is also a drag across menu-bar items.

A click on the other display, or on the notch-less display while `screen` is still the first panel, fails `pointerIsOnNotch` and cancels the gesture (S08-04 and S08-17).

Owning area: PR #57 together with the footprint on integration.

Sketch, device: two displays, panel open on display A, click the pill on display B. Expect no `down` sample. Notch-less display: click the centre of the menu bar, 10 pt below the top. Expect a notch `down` and the menu bar action together. Static: `clickZone` for a zero notch size is 120 by 14 at `screenFrame.maxY`.

### S08-08 — Right Command starts Murmur and also toggles talk

Severity: P0.

Integration `2722dcb7`, `Sources/ZeusCore/Shortcut.swift:213` defaults dictation to `.rightCommand`. `Sources/ZeusCore/VoiceKeyMachine.swift:435-437`: a hold key with confirm 0 enters `.holding` and emits `.start` on the key-down. Dictation’s monitor uses that path (`DictationController.start`, role `.dictation`). Confirm stays 0 unless the tiling tap asks for longer.

`zeus-bot/right-command-toggle` `817c4219`, `Sources/Zeus/App/AppDelegate.swift:328-329`. `onRightCommandStart` calls `talkKeyPressed`. `Sources/ZeusCore/Voice/RightCommandTap.swift:16` treats a release within 0.30 s as a toggle. `HotkeyMonitor.applyRightCommand` (`HotkeyMonitor.swift:318` on that head) plays the talk cue and starts the talk turn.

The talk monitor and the dictation monitor each have their own `HotkeyMonitor`. One physical tap is delivered to both. Key-down starts Murmur. Key-up within 0.30 s starts a talk turn.

PR #21 (`6a57313b`, `DictationController.swift:654`) opens the microphone before the focused field is read, so Murmur is already capturing when the tap’s up starts talk.

Owning area: PR #81 against the dictation key on integration. PR #21 makes the overlap audible sooner.

Sketch, static: one `ShortcutState` stream, Right Command code 54 down at t=0 and up at t=0.12, fed to a dictation `VoiceKeyMachine` (hold, confirm 0, key `.rightCommand`) and to `driveRightCommand` with `onRightCommandStart` set. Expect `.start` from the dictation machine and a talk toggle from the tap. Device: tap Right Command once with both features on and count sessions.

### S08-09 — Left Command does not spoil a Right Command tap

Severity: P1.

`817c4219`, `Sources/Zeus/Voice/HotkeyMonitor.swift:287-301`. On Right Command down, `other` is true when an ordinary key is down or a modifier other than Command is down. `.subtracting(.command)` drops both physical Command keys. `leftDown` (`RightCommandTap.swift:78-80`) returns no signals and does not set `spoiled`.

`RightCommandTapTests.chordedOrLongHeldOrLeftCommandDoesNothing` presses Left Command with no Right Command. It never holds Left Command across a Right Command tap.

Owning area: PR #81, Right Command. Left versus right.

Sketch, static: flags key 55 (Left Command) down, flags key 54 down, flags key 54 up at +0.12 s, through `driveRightCommand`. Expect a toggle today. Expect no toggle once Left Command counts as another key.

### S08-10 — a missed modifier key-up stays down

Severity: P1.

Integration `2722dcb7`, `Sources/Zeus/Voice/HotkeyMonitor.swift:242-247`. Sleep and wake call `interrupt`. Resigning active, a focus change, and secure input do not. `liveModifiers` (`:112`) reads `NSEvent.modifierFlags`, which has no left or right. `VoiceKeyMachine.readLive` (`VoiceKeyMachine.swift:327`) treats the chord as released only when the live set no longer contains the modifier. Left Option still down means Right Option’s missed key-up (code 61) never looks released. `ordinaryKeysDownInTheSystem` polls the hardware for ordinary keys only. Modifier codes 54, 55, 58, and 61 are not polled. The tiling tap is the one reader of `IsSecureEventInputEnabled` (`TilingKeyTap.swift:244`); the voice monitors are not.

`817c4219`, `HotkeyMonitor.swift:139` and `:297-302`. `rightCommandDown` is local state. `interrupt` does not clear it. `RightCommandTap` has no tick. A Right Command key-up lost in a password field or while the app is inactive leaves `rightCommandDown` true. The next real down is ignored. The following up sees a `downSince` older than 0.30 s, so it does not toggle. That press does nothing.

Owning area: talk and Murmur on integration, and the tap on PR #81.

Sketch, static: Right Option hold reaches `.holding`, then a tick whose live modifiers are still `.option` while `deviceKeys` has lost code 61. Expect the turn to stay `.holding` (current `readLive`). For the tap: `rightDown` at t=0, no `rightUp`, then flags that never clear `rightCommandDown`, then a new down/up pair. Expect the pair to produce no toggle.

### S08-11 — a repeated flags event releases the right key when the left key is down

Severity: P2.

Integration `2722dcb7`, `Sources/ZeusCore/Shortcut.swift:341-347`. A repeated `flagsChanged` for a modifier whose flag is still set removes that key code when the other side is also in `deviceKeys`. The lone-key case is guarded: `ShortcutTests.repeatedFlagsChangedWhileHeldDoesNotReadAsARelease` expects a second Right Command down to stay held. `rightCommandIsNotLeftCommand` expects the both-sides form of the same event to mean the right key came up.

A resend while both Command keys are physically down, the same class of event the lone-key fix describes, clears Right Command. The same table entries (`ShortcutModifiers.keyCodes`, `:14-15`) do it for Right Option (61 beside 58).

Owning area: talk and Murmur, integration. Key repeat and left versus right.

Sketch, static, and it fails on purpose today:

```swift
var state = ShortcutState()
state.apply(.flags(keyCode: 55, modifiers: .command))
state.apply(.flags(keyCode: 54, modifiers: .command))
state.apply(.flags(keyCode: 54, modifiers: .command))
#expect(state.isHeld(.rightCommand))
```

The third event is identical to the second. A real release of the right key while the left stays down has the same shape, so a fix has to use the hardware key state (`CGEventSource.keyState`) for code 54.

### S08-12 — a disabled event tap stays off

Severity: P1.

Integration `2722dcb7`, `Sources/Zeus/TopBar/SystemHUDEventTap.swift:40-41`. The callback returns nil unless the event type’s raw value is 14. `tapDisabledByTimeout` and `tapDisabledByUserInput` take that path. Nothing calls `CGEvent.tapEnable`. `SystemHUDMonitor.refreshEventTap` runs from start and from the one-shot trust callback, not from the tap. After the system disables the tap, volume and brightness keys stop being taken.

`Sources/Zeus/Tiling/TilingKeyTap.swift:269-281` re-enables until `TileTapHealth` (`TileKeyMatcher.swift:141-152`) sees 3 disables inside 10 s, then disables the tap and reports failure. `TilingKeyLayer.tapKeepsFailing` (`TilingKeyLayer.swift:127-131`) sets `failed` and will not create another tap until tiling is turned off and on. A burst of timeouts, or secure-input disables, leaves window-move hotkeys off for the rest of the session.

`Sources/Zeus/Pointing/PointingEventTap.swift:63-66` re-enables and does not resync. Key-ups that arrived while the tap was disabled are gone. The pointing hold then depends on S08-10’s flag check.

Owning area: top-bar media keys, tiling, pointing. All on integration.

Sketch, static: invoke the HUD callback with `.tapDisabledByTimeout` and assert `CGEvent.tapEnable(..., enable: true)` was not called (the closure returns before any enable). For tiling, `TileTapHealth().recordDisable` three times inside the window returns `.giveUp`, and a fourth call stays `.giveUp` with no reset from the layer.

### S08-13 — revoking Accessibility is invisible

Severity: P1.

Integration `2722dcb7`, `Sources/Zeus/Voice/HotkeyMonitor.swift:34-45`. `KeyListenAccess.whenGranted` polls every 3 s until the grant, then invalidates the timer and starts the global monitors once. `Sources/Zeus/App/PermissionsModel.swift:623-633`: `AccessibilityGate` does the same and stops polling on `.becameTrusted`.

Nothing in either type notices a later revoke. Global monitors are left installed. `startGlobal` is not run again if the grant returns. The closed notch’s click, drag, and mouse-up monitors are global (`NotchController.start` on #57). A revoke drops the mouse-up that S08-04 needs, and drops the modifier key-up that S08-10 needs. No `.cancel` and no `interrupt` run at the revoke.

Tiling removes its tap only when `apply` happens to run while untrusted (`TilingKeyLayer.swift:88-94`). A revoke with no settings change leaves that tap installed until the system disables it (S08-12).

Owning area: permissions, on integration. The notch monitors on PR #57 depend on it.

Sketch, device: grant Accessibility, press Right Option, revoke Accessibility, release the key, grant it again, tap Right Command. Expect the talk hold to end on release and the later tap to register. Static: after `whenGranted` has fired, a `trusted == false` reading has no waiting closure and no timer.

### S08-14 — system and other-app hotkeys are a short hardcoded list

Severity: P2.

Integration `2722dcb7`, `Sources/ZeusCore/Shortcut.swift:225-244`. `ShortcutConflicts.system` is a fixed list of chords with a key code. `warnings` matches exact equality (`:253`). Right Command and Right Option are modifier-only and are absent, so the shipped keys never warn. The list is not the user’s symbolic hotkey table, and it is not other processes’ registered global hotkeys.

`Sources/ZeusCore/VoiceKey.swift:72-74`. A Right Option hold is dropped entirely when one of Zeus’s own Carbon shortcuts is Option plus some other key. `TalkChordRouting.holders` is Chat, the agent picker, and Quick to-do. A bare Right Option hold is a different chord from Option-Space. The yield still removes “hold Right Option to talk” for the whole session. Hotkeys registered by other apps are not in `holders()`.

The talk chord does consult VoiceOver and those three Carbon shortcuts. Right Command dictation and the Right Option hold do not get that check.

Owning area: shortcuts, integration. Conflicts with system shortcuts and other apps’ global hotkeys.

Sketch, static: `ShortcutConflicts.warnings(for: .rightCommand, other: .controlOption, otherName: "Talk")` is empty. `secondTalkKey` with a carbon holder `(name: "Chat", shortcut: Option-Space)` returns `(nil, "Chat")` for chosen `.rightOption`. A holder that is an external process never appears because `holders()` only returns the three Zeus shortcuts.

### S08-15 — an app switch during Murmur can still paste

Severity: P2.

`6a57313b`, `Sources/ZeusCore/Dictation/InsertTargetDecision.swift:46-47`. `captured` is true only when the key-down pid is non-zero and the bundle id is non-empty. A frontmost app that has a pid and a nil bundle id takes the uncaptured branch. `plan` (`:67`) then pastes into `postOpen`, or into the live frontmost app when that is missing. Switching apps before release inserts into the app that is in front at delivery.

`DictationFocusRule.swift:13-16`. `sameApp` returns true when the bundle ids match, even if the pids differ. A switch to another process of the same bundle still chooses `.postOpenField`.

`DictationController.swift:642` stores the frontmost app before the microphone opens. The focused field is read in `afterOpen` (`:656-659`), after the cue and the mic. A focus change in that gap is a different field from `keyDownApp`.

Owning area: PR #21, Murmur. Focus and app changes.

Sketch, static: `route(keyDown: identity(pid: 10, bundle: nil), postOpen: nil, frontmost: identity(pid: 20, bundle: "other"), ownPid: 1)` is `.paste`. `DictationFocusRule.choose` for the same bundle id and pids 10 and 20 is `.postOpenField`.

### S08-16 — the new hold machine is not Right Option, and it is not called

Severity: P2.

`817c4219`, `Sources/ZeusCore/Voice/TalkHold.swift:12` and `:103-108`. `TalkHold` matches an unsided Control+Option pair. It has no right-side bit. Option alone returns the hold to idle, which is how a Right Option hold would have to be expressed, and this type does not do that.

`Sources/Zeus/Voice/HotkeyMonitor.swift:81-82` declares `onTalkBegin` and `onTalkEnd`. No call site on the head reads them. `TalkHold` is constructed by `TalkRehearsal` and by tests. The running talk path is still `VoiceKeyMachine` plus `secondKeyProvider` (Right Option on integration, `AppDelegate.swift:340` on this head).

Owning area: PR #81. Required behaviour is a Right Option hold that talks to Zeus. The second-key path on integration is the one that can do that. This PR’s hold type does not drive it.

Sketch, static: search the head for `onTalkBegin?(` and `TalkHold()`. The closures are never invoked. `TalkHold().flags(.option, at: 0)` stays idle. `TalkHold().flags([.control, .option], at: 0)` arms, including when the Option key is the left one.

### S08-17 — a click outside before settle throws away the click

Severity: P3.

`3cde0156`, `Sources/ZeusCore/TopBar/NotchGestureAdapter.swift` cancel arm (`reduce` on `.cancel` returns `[.disarm]` and sets `.idle`). `NotchController.ingestMouseDown` (`:527-528`) sends `.cancel` when the down is outside the zone, including a down that arrives during `.settling`. No `.settle` is emitted, so a finished click that was waiting out the 0.35 s multi-click window disappears.

`NotchGestureAdapterTests.cancelDropsAPressThatIsStillWaiting` covers a cancel while the button is still down. It does not cover cancel during `.settling`.

Owning area: PR #57, top bar.

Sketch, static: down, up inside the slop at +0.1 s (phase `.settling`), then `.cancel`, then a tick at +0.5 s. Expect no `.settle`. A click on the pill and a click just outside it within 0.35 s produces no click route.

## Hunt list

| Hunt | Where it landed |
| --- | --- |
| Modifier key-up lost when focus or the app changes | S08-10, S08-15 |
| Stuck-key states | S08-04, S08-10, S08-11 |
| Left versus right modifier confusion | S08-09, S08-10, S08-11 |
| Key repeat | S08-11 |
| Conflicts with system shortcuts and other apps’ global hotkeys | S08-14, S08-08 |
| Event tap disabled by timeout and never re-enabled | S08-12 |
| Secure-input mode | S08-10, S08-12 |
| Several monitors, and a display with no notch | S08-07 |
| Trackpad versus mouse | S08-06 |
| Accessibility permission revoked at runtime | S08-13, S08-04 |
| Race between a tap and a hold | S08-02, S08-03, S08-08 |

## Counts

| Severity | Rows | Of which duplicates |
| --- | ---: | ---: |
| P0 | 1 | 0 |
| P1 | 10 | 1 (S08-01, ZB-003) |
| P2 | 5 | 0 |
| P3 | 1 | 0 |
| Total | 17 | 1 |

New rows, excluding the ledger duplicate: 16.
