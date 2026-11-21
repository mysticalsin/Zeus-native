# Notch lock screen: plan and design

Written 14 November 2026 against `codex/island-20261113` (HEAD `9f2ffe4`). Fourth wave after
`docs/NOTCH-MUSIC-PLAN.md`, `docs/NOTCH-SURFACE-PLAN.md`, `docs/NOTCH-SOURCES-PLAN.md` and
`docs/NOTCH-EQUALISER-PLAN.md`. The music wave is in this tree (`TopBarModel.musicModes`, `TopBarModel.swift:137`;
`MusicAwakeHold`, `AppDelegate.swift:172-175`). The sources wave is not (no `NowPlayingHub` anywhere under `Sources`),
so this plan reads music through one small seam and does not wait for it. Same rules: pure rules in ZeusCore with tests
first, `docs/DESIGN-DIRECTION.md` for anything visible, nothing accepted until the named tests run on macOS and the
behaviour is seen on a Mac. Line numbers below were read on `9f2ffe4`. Nothing was built, compiled or launched.

This is the first Zeus feature that calls private window-server space functions. The owner approved the route. It is
off by default, loads its symbols at run time, checks every one, and stays off when anything is missing.

**Refactor first: yes.** Three places watch lock notifications today, each on its own: the notch re-raises its
windows and keeps no lock state (`NotchController.swift:90-94`), the morning brief shows on unlock
(`ProactiveController.swift:41-46`), and the wake word holds the only lock flag (`WakeWordController.swift:62-74`,
flag at `:37`, `:90-93`, `:119`). None of them asks the session whether it is locked, and the wake word treats
"the display woke" as "unlocked" (`WakeWordController.swift:69-70`): lock the Mac, let the display sleep,
touch a key, and `screenLocked` is false while the Mac is still locked, so "Hey Zeus" listens on a locked Mac. Read
from the code, not reproduced on a Mac. A lock screen surface cannot sit on a fourth copy of that. Ticket L0 gives
Zeus one session model first, and moves the wake word onto it.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| L0 | One session model (refactor) | Three sets of lock observers, one of them wrong after a display wake | One pure presence value that also decides when to read again, one monitor that reads the session; the wake word uses it |
| L1 | What a locked Mac may show | No rule | A pure content policy: full card, quiet card or nothing; text cleaned; three commands and no more |
| L2 | Surface lifecycle | None | One reducer (State, Event, Effect): a fresh window and space per lock, closed on every way out, a problem marker |
| L3 | Private space host | None | One file that loads seven symbols at run time, checks each symbol and each result, and is the only place they are named; lints |
| L4 | Card and clock row | None | Two small views that draw a `LockScene` value and nothing else |
| L5 | Controller and wiring | None | A main-actor controller that runs L2's effects, a window that cannot take the keyboard, the music seam, the meeting hook |
| L6 | Settings | None | A "Lock screen" card: four switches, and a status word only when something is wrong; an import can never loosen it |

Worktrees and order:

| Ticket | Files it owns | Runs |
| --- | --- | --- |
| L0 | new `Sources/ZeusCore/Lifecycle/SessionPresence.swift`, new `Sources/Zeus/App/SessionPresenceMonitor.swift`, `Sources/Zeus/Voice/WakeWordController.swift`, new `Tests/ZeusCoreTests/SessionPresenceTests.swift`, new `Tests/ZeusAppTests/SessionPresenceMonitorTests.swift`, `qa/closed-loop/tests/test_source_lint.py` (two checks), `docs/STATE-MACHINES.md` (one row) | First, alone |
| L1 | new `Sources/ZeusCore/LockScreen/LockContent.swift`, new `Tests/ZeusCoreTests/LockContentTests.swift` | At once, parallel with L0 (it uses no L0 type) |
| L2 | new `Sources/ZeusCore/LockScreen/LockSurface.swift`, `LockLayout.swift`, `LockScreenTypes.swift`, new `Tests/ZeusCoreTests/LockSurfaceTests.swift`, `LockLayoutTests.swift`, `docs/STATE-MACHINES.md` (one row, after L0's) | After L0 and L1 |
| L3 | new `Sources/Zeus/LockScreen/LockSpace.swift`, `qa/closed-loop/tests/test_source_lint.py`, `Sources/ZeusCore/Compliance/AtticusCleanRoom.swift` (comment only), new `Tests/ZeusAppTests/LockSpaceTests.swift` | After L0 (same lint file) and step zero; parallel with L2, L4, L6 |
| L4 | new `Sources/Zeus/LockScreen/LockSceneView.swift`, `Sources/Zeus/App/SnapshotRenderer.swift` (new fixtures), new `Tests/ZeusAppTests/LockSceneViewTests.swift` | After L1; parallel with L2, L3, L6 |
| L5 | new `Sources/Zeus/LockScreen/LockSurfaceController.swift`, `LockWindow.swift`, `LockMedia.swift`, `Sources/Zeus/App/AppDelegate.swift` (start, catalog cases, meeting hook, terminate), new `Tests/ZeusAppTests/LockSurfaceControllerTests.swift` | Last, after L2, L3, L4 and L6 (it sets L6's bridge and wires L6's catalog ids) |
| L6 | `scripts/gen-settings-catalog.py` and its generated outputs, `Sources/Zeus/App/SettingsStore.swift` (import rules, one status case, `MeetingState.onChange`), new `Sources/Zeus/Settings/GSLockScreenCard.swift`, one line in `GlanceSettingsPages.swift`, new `Tests/ZeusAppTests/LockScreenCardTests.swift`, `Tests/ZeusAppTests/SettingsCatalogTests.swift` | After L2; parallel with L3, L4 |

No two tickets that run together share a source file. Two QA files are shared by design: every ticket appends to
`qa/regressions.json`, and every ticket that adds a `ZeusAppTests` suite (L0, L3, L4, L5, L6) adds that suite's own
`native-<Suite>` check to `qa/feature-map.json`, because a suite with no check is compiled and never run
(`SettingsCatalogTests` has none today, so L6 adds it). Merge order L0, L3, L4, L6, L5; each later branch rebases its
one entry, as `docs/NOTCH-EQUALISER-PLAN.md:371-372` does. `AppDelegate.swift`, the settings generator and
`test_source_lint.py` are also edited by the sources and equaliser waves: rebase on whichever merged first, never
hand-merge `SettingsCatalog.swift` or the inventory. REG-490 to REG-509 are reserved and all used: L0 490 to 493, L1
494 to 497, L2 498 to 501, L3 502 and 503, L4 504, L5 505 to 508, L6 509; clashes go through
`<models-dir>/zeus-merge-reg.py`. Feature `F13`. Builds go in `<models-dir>/<name>-build`, never in OneDrive.

## Step zero, on a Mac, before L3 and L5 are scheduled

L0, L1, L2, L4 and L6 are safe to build at once: none of them makes a private call. L3 and L5 wait for a throwaway
probe (outside the repo, in `<models-dir>/zeus-lock-probe`, never merged) that the owner runs on macOS 27.2 and on
one macOS 26 Mac. It answers, with a note per line:

1. The seven symbols in L3 resolve, and whether a window removal function is needed at all (question 5).
2. A panel with L5's style and collection behaviour, moved into a space at level 400, shows above the lock screen.
3. A button in the panel fires its action on the first click. Typing, Tab, Space and Return do not reach it.
4. After unlock, with the window closed and the space destroyed, clicks land on the desktop everywhere, and the
   window census in L5 finds nothing. Twenty lock and unlock cycles, a new space each time, leave no fault.
5. Closing the window is enough to take it out of the space, with no leftover on screen.
6. The order and delay of the lock and unlock notifications against the session dictionary, on lock, unlock, fast
   user switching out and back (is an unlock notification sent on the way back), screensaver start and stop, display
   sleep and wake. This confirms or changes `settleDelays` and `watchSeconds` in L0.
7. With two displays: which one carries the sign-in controls, and the height of the system clock band and of the
   sign-in band on a built-in and an external display (L2's two layout numbers).
8. Music and Spotify change notifications arrive while locked, and a scripted play, pause and next act.
9. A window with `sharingType = .none` in that space: is it missing from a screen recording.
10. VoiceOver reaches the window's buttons on the lock screen, and Touch ID and the password field work beside it.
11. With Music playing and a notification waiting while locked: whether macOS draws media controls of its own, and
    where they and its notification stack sit on each display. Unverified here, which is why it is asked.
12. Force Quit by keyboard and `killall Zeus` while the card is up: the window and the space go with the process.
    `kern.bootsessionuuid` reads, and changes across a restart.

A "no" on 2, 3 or 4 stops the wave and goes back to the owner. The answers to 5, 6, 7 and 11 set constants in L0,
L2 and L3 (L0 ships with the default delays; a change is one line), and 11 also feeds decision 9.

## Open source checked first

Licences are as recorded in the private study of 13 November 2026, which read each licence file. They were not
re-read for this plan; re-read before any reuse. Each project is named here only.

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| Create a space, set its level, show it, move a window in | Lakr233/SkyLightWindow | MIT | Technique only. Its routine has no nil checks and force-unwraps; Zeus writes its own with every symbol checked |
| Function shapes, 64-bit space ids | koekeishiya/yabai | MIT | Technique only: argument and return shapes |
| The same calls under their older prefix; the create flag must be 1 | avaidyam/Parrot (`CGSSpace.swift`) | MPL-2.0 | Not used. Read as a cross-check of the flag only |
| A lock screen music card with working controls; lock polling; lifetime of the window | Ebullioscopic/Atoll | GPL-3.0 | Technique only. No code is read into Zeus |
| Report that windows kept in the space swallow desktop clicks after unlock | TheBoredTeam/boring.notch | GPL-3.0 | Technique only: the reason for a fresh window per lock with no transparent margin |

No code is copied, no file is bundled and no dependency is added, so no notice is owed. If a builder ever adapts the
MIT routine instead of writing fresh, its notice goes in both `NOTICES.md` and `Resources/NOTICES.txt`.

## System interfaces this plan relies on

| Interface | Kind | Checked against |
| --- | --- | --- |
| `CGSessionCopyCurrentDictionary()` and `kCGSessionOnConsoleKey` | Public | macOS 27.2 SDK, `CGSession.h:23` and `:46` |
| The key `CGSSessionScreenIsLocked` in that dictionary | Undocumented | The study (used by open-source lock detection). Not in the SDK header. Step zero, question 6 |
| `com.apple.screenIsLocked`, `com.apple.screenIsUnlocked` | Undocumented | The study: the vendor's support engineers call them implementation details. Already used at `NotchController.swift:90` |
| `com.apple.screensaver.didstart`, `.didstop` | Undocumented | The study. Unverified on 27.2. Step zero, question 6 |
| `NSWorkspace` session, sleep, wake and screen notifications | Public | Already used at `WakeWordController.swift:69-70`, `NotchController.swift:85` |
| Seven space functions in the window-server framework | Private | The study's symbol probe on macOS 27.2 build 26B118: all seven resolve. Resolving does not prove the call works |
| Level 400 above the lock screen (300); create flag 1; move selector 7 | Private, undocumented | The study, from the MIT source. Meanings unknown. Step zero, questions 2 and 5 |
| A window removal function | Private | Not in the study's probe. Unverified. The design does not need it (question 5) |
| `NSWindow.sharingType` | Public | `ZeusWindowSharing.swift:20-32`. The study reports `.none` ignored by one capture API since macOS 15.4 |
| `CGDisplayIsAsleep` | Public | macOS 27.2 SDK, `CGDisplayConfiguration.h:288` |
| `CGWindowListCopyWindowInfo`, `kCGWindowLayer`, `kCGWindowOwnerPID` | Public | SDK `CGWindow.h:170`, `:63`, `:91`; already used at `PrompterWindow.swift:866` |
| `NSView.acceptsFirstMouse(for:)` | Public | SDK `NSView.h:225`; precedent `NotchController.swift:735-738` |
| The sysctl name `kern.bootsessionuuid` | Public name, not in an SDK header | Unverified here (the sandbox refused the read). Step zero, question 12 |
| `dlopen`, `dlsym` on an absolute system path | Public | Precedent: `FastActions.swift:475-481`, `SystemHUDHardware.swift:10-14` |

## Privacy and consent

- No new OS permission, entitlement or usage string. Nothing prompts. `Resources/Zeus.entitlements` is unchanged.
- Off until the owner turns on `lockScreen.enabled`. It joins `SettingsStore.neverEnabledByImport`
  (`SettingsStore.swift:255-258`, enforced at `:314`) with `lockScreen.showTrackDetails` and `lockScreen.lyrics`, and
  the generator's `opt_in` tuple (`gen-settings-catalog.py:243-246`). An import can turn these off, never on.
- An import can never loosen what the lock screen hides, either. Two existing switches also hide track details
  there and an imported file may set both today: `privacy.details` (default on, `gen-settings-catalog.py:156`) and
  `general.meetingMode` (default on, `:23`). L6 puts the first in `neverEnabledByImport` and the second in a new
  `neverDisabledByImport`. That changes import for both everywhere in Zeus (decision 10).
- With the switch off no symbol is looked up, no space call is made and no window is created.
- A locked Mac shows its screen to people who have not signed in, and a capture of the screen can include it. So
  the surface holds two kinds of content only: what a desktop player is playing, and the time. Nothing else Zeus
  knows is drawn there: not what an agent is doing or asking, no message or alert of any kind, nothing from the
  owner's day, files, copied text or devices, and no place to type or to change a setting.
- Nothing shown on the lock screen reaches a model, voice, chat or agent context. Logs carry state and step names,
  never a title, artist or lyric.
- No new network use. A lyric lookup for a new track while locked is the request `privacy.lyrics` already allows
  (`LyricsViews.swift:43`, `:107-114`), and only when `lockScreen.lyrics` is also on and details are shown.
- Tests never open the framework, make a space, lock the Mac or post a lock notification (lints, L0 and L3).
- When the system vendor closes the route (a symbol is gone, or a macOS version Zeus has not checked): the card simply
  does not appear on lock. The notch and desktop are untouched, nothing is retried in a loop, and the Lock screen card
  in Settings reads "Not available on this macOS" with a warning symbol. macOS 14.2 to 15, which Zeus still supports
  (`Package.swift:6`), read the same. After a crash or a failed call while the card was up it reads "Stopped after a
  problem" with a "Turn on again" button, and stays stopped, across launches, until the owner presses it.

## What a locked Mac may show

| Case | Shown |
| --- | --- |
| Details shown, a running desktop player (Music or Spotify) has a track | Full card: artwork, title, artist, progress with elapsed and remaining (read only), previous, play or pause, next; the current lyric line when both lyric switches are on and a synced line exists |
| The owner hides track details: `lockScreen.showTrackDetails` off, or `privacy.details` off, or meeting mode on (`MeetingState.hideDetails`, `SettingsStore.swift:351`, which includes a mirrored display) | Quiet card: the word "Playing" or "Paused", and previous, play or pause, next. No artwork and no album colour (`NowPlaying.hue` is derived from the album name, `NowPlaying.swift:119-122`), no title, artist, album or player name, no lyric, no progress, no times (a length and position can identify a track). It changes at once when any of the three flips while the card is up |
| The player is running but Zeus is not already allowed to script it | The full card with no controls; with details hidden, no card. A press can never raise a consent prompt behind the lock screen (`Automation.allowed`, `PermissionsModel.swift:343`) |
| The player is not running | No card. A track notification with no player behind it draws nothing (`updateMusic` accepts one today, `TopBarServices.swift:169-186`) |
| Nothing is playing or paused | No card |
| The track comes from a browser tab (sources wave) | No card. A web page never puts text or a picture on the lock screen, and a locked Mac never controls a tab |
| `lockScreen.clock` on | A clock row: time and date. Alone when there is no card |
| No card and no clock | No window is made and no private call runs |

Commands a locked Mac can send: play or pause, next, previous. Never seek, Open (today it launches an app,
`TopBarServices.swift:231-236`), shuffle, repeat, output device or volume.

## How the surface behaves

The window exists only while it can be seen on a locked session. Every way out closes it; every way in makes a new one.

| Moment | Signal | Result |
| --- | --- | --- |
| Lock | Any notification asks for a read. If the dictionary does not say locked yet, the session model reads again on its settle schedule (L0) until it does or the run ends | A fresh space and window, shown; no card when no read ever says locked |
| Zeus starts while locked | The first read at start | As the read says |
| Unlock | The unlock notification, or the one-second watch the session model keeps while locked and lit | Window closed, space destroyed; at most one watch period late |
| Display sleeps while locked | `screensDidSleep` | Closed; no timer left running |
| Display wakes, still locked | `screensDidWake`, then a read | A fresh window |
| System sleep, lid closed | `willSleep` | Closed before sleep |
| Wake | `didWake`, then a read | As the read says |
| Screensaver | Its start and stop notifications | Closed while it runs |
| Fast user switch away | `sessionDidResignActive` clears "on console" at once | Closed; the other user never sees it |
| Switch back | `sessionDidBecomeActive`, then a read | As the read says |
| Sign-in window after a restart | Zeus is not running | Nothing; out of scope |
| A display is added, removed, rearranged, mirrored or changes size | `didChangeScreenParameters` | Meeting state is refreshed and the scene rebuilt first, then the window is moved to the primary screen's band; closed when no layout fits |
| Meeting mode starts or ends; a hide switch changes | `MeetingState.onChange` (new, L6); the settings hook | Redrawn at once as the quiet or the full card |
| Track change, pause, new lyric line | A new `LockScene` | Redrawn; no private call |
| Progress each second, the clock each minute | The view's own tick (L4) | Redrawn; stops with the window |
| The player quits | The scene empties | Closed, or the clock row alone |
| Zeus quits | `applicationWillTerminate` (`AppDelegate.swift:88-97`) | Closed, space destroyed, marker removed |
| Zeus dies while the window is up | The marker file stays | Next launch: "Stopped after a problem" until the owner turns it on again |
| The Mac restarts or loses power while the window is up | The marker carries another boot's id | Next launch: "Stopped after a restart", the same button |

## L0. One session model (refactor first)

### Behaviour

- Zeus keeps one value that says whether this login session is locked, on the console, awake and showing a display.
  Notifications never set "locked" by themselves: each one asks for a read of the session dictionary, and the read
  decides. A forged or late notification therefore cannot show the card on an unlocked desktop.
- The same reducer decides when to read again, so a notification that runs ahead of the dictionary, or never comes,
  cannot leave the value wrong.
- The wake word pauses whenever the owner is not present, and a display wake no longer clears the pause. A return
  by fast user switching, and an unlock only a read sees, both end it, so nothing today's code gets right is lost
  (`sessionDidBecomeActive` clears the flag at `WakeWordController.swift:69`).
- The notch and the morning brief keep their own observers: they hold no lock state, so they are not moved here.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Lifecycle/SessionPresence.swift`:

| Name | Rule |
| --- | --- |
| Values | `SessionFacts` (`screenLocked`, `onConsole`): what one read returns. `SessionReading`: `locked`, `unlocked`, `unknown`. `LockHint`: `none`, `locked`, `unlocked` (the last lock or unlock notification) |
| `SessionPresence` | Equatable, Sendable: `reading`, `hint`, `onConsole`, `displaysAwake`, `screensaver`, `systemAsleep`, `settleLeft`. `init(displaysAwake:)` starts `unknown`, hint `none`, not on console, no screensaver, not asleep: nothing is showable and nobody is present until the first read |
| `Event`, `Effect` | `lockNotified`, `unlockNotified`, `sessionBecameActive`, `sessionResigned`, `displaysSlept`, `displaysWoke`, `screensaverStarted`, `screensaverStopped`, `willSleep`, `didWake`, `refreshRequested`, `sessionRead(SessionFacts?)`. One effect: `readSession(after: TimeInterval)` |
| `reduce(_:) -> [Effect]` | Every event but `sessionRead` updates its own field, refills `settleLeft` and returns `[.readSession(after: 0)]`. `sessionResigned` clears `onConsole` before the read. `sessionBecameActive` clears a `locked` hint. Only `sessionRead` changes `reading`: nil gives `unknown` and not on console; unlocked clears `screensaver` and, when it follows a `locked` reading, the hint too, because the read saw the unlock itself |
| Reading again | Decided inside `sessionRead`. Reading `locked`, a display awake, the system not asleep: `readSession(after: watchSeconds)`. Otherwise, hint `locked`, reading not, `settleLeft > 0`: the next of `settleDelays`. Otherwise nothing. `settleDelays` (0.5, 1 and 2 s) and `watchSeconds` (1 s) are named constants (step zero, question 6). Zeus has no other timer for lock state |
| `lockSurfaceMayShow` | `reading == .locked`, on console, displays awake, no screensaver, not asleep |
| `ownerPresent` | `reading == .unlocked`, `hint != .locked`, on console, not asleep. Both sources must agree before a microphone feature runs; either one saying "locked" pauses it |

App side: new `SessionPresenceMonitor` (main actor, `@Observable`, `shared`). Its initialiser takes the reader, the
two notification centres (typed `NotificationCenter`, which the distributed centre subclasses), a display probe and
a scheduler; tests pass a private centre and fakes, so no test posts into the login session, where every other app
would act on it. `start()` is idempotent and does nothing when `TopBarStyle.isSnapshot`. It seeds `displaysAwake`
from `CGDisplayIsAsleep(CGMainDisplayID()) == 0`, adds the observers (`queue: .main` plus
`MainActor.assumeIsolated`, as `NotchController.swift:79-94`) and sends `refreshRequested` at once, so a Zeus
launched unlocked has a present owner after one read and a Zeus launched locked can show its card.
`WakeWordController.start` calls it (L0 owns that file; `AppDelegate.swift:317` runs it under `on(.wakeWord)`); L5
calls it again. The live reader calls `CGSessionCopyCurrentDictionary()` and maps a missing lock key to "not
locked" and a nil dictionary to nil. `readSession(after:)` is one cancellable one-shot; a newer one replaces it.
`WakeWordController` drops its six observers (`:62-74`) and `setLocked` (`:90-93`); `currentGate()` sets
`gate.screenLocked = !presence.ownerPresent || !presence.displaysAwake` (`:119`; `WakeGate.screenLocked`,
`WakePhrase.swift:82`, is unchanged) and re-evaluates when the monitor's value changes.

Fail closed: an unreadable session is neither showable nor present. If the vendor drops the lock key, every read says
"not locked": the settle run ends after three reads, the card never shows, and the wake word falls back to the
notification hint, as today. The watch costs one dictionary read a second, only while locked with a display lit.

### Tests first

- `Tests/ZeusCoreTests/SessionPresenceTests.swift`: a lock notification alone never makes the surface showable; a
  lock notification, a read that says unlocked, then a settle read that says locked does; the settle run stops
  after three reads; a display wake while the reading says locked keeps the owner absent (REG-490, the wake word
  defect); so does an unlock notification (REG-491); the owner is present again with no unlock notification, by a
  watch read after a locked one and by `sessionBecameActive` (REG-492, two arguments); a first read that says
  unlocked and on console gives a present owner; the watch runs only while locked, lit and awake; an unreadable
  session is neither; resigning the console hides before any read; sleep and wake; screensaver.
- `Tests/ZeusAppTests/SessionPresenceMonitorTests.swift` (fake reader, private centres, fake scheduler): `start()`
  reads once before any notification; one immediate read per notification; a newer scheduled read replaces a
  pending one; the published value changes only when the presence differs; snapshots start nothing.
- Lints in `test_source_lint.py`, each with a fail-first sample: `WakeWordController.swift` no longer names
  `screenIsLocked` or `screensDidWakeNotification` (REG-493); nothing under `Tests/` names `com.apple.screenIs`,
  `com.apple.screensaver` or `DistributedNotificationCenter` (none does today).

Only at the Mac: lock, let the display sleep, wake it, say the wake phrase: Zeus stays quiet. Unlock: it listens
again. Launch Zeus on an unlocked Mac: it listens with no lock first. Switch user away and back: it listens again.

## L1. What a locked Mac may show

### Behaviour

The table under "What a locked Mac may show" is the behaviour. This ticket turns it into one pure function, so no
view or controller ever decides what is revealed.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/LockScreen/LockContent.swift`. It does not import the app's music types, so the sources
wave can change `NowPlaying` (`NowPlaying.swift:5`) without touching it, and no L0 type, so it builds beside L0.

| Name | Rule |
| --- | --- |
| `LockTrack`, `LockOptions` | Track: `kind` (`player`, `other`), `playerRunning`, `title`, `artist`, `hue`, `isPlaying`, `duration`, `position`, `positionAt`, `canControl`. Options: `showTrackDetails`, `hideDetails`, `lyrics`, `lyricsPrivacy`, `clock` |
| `LockControls`, `LockCard` | Controls (OptionSet): `previous`, `playPause`, `next`. Card: `.full(title:artist:hue:isPlaying:progress:lyric:controls:)` or `.quiet(isPlaying:controls:)`, so the view has the play or pause glyph and the tile colour without reading anything else |
| `LockScene`, `LockContentPolicy.scene(track:options:lyricLine:)` | Scene: `card`, `showsClock`, `isEmpty`. The policy applies the table above: no card when the player is not running, no quiet card without controls. Any input it does not recognise gives the quiet card or nothing, never more |
| `LockText.clean(_:limit:)` | Removes control characters, line breaks, zero-width and direction-override characters, collapses spaces, and cuts at the limit: title 80, artist 60, lyric 120 characters. Empty after cleaning is absent |
| `LockLyric.line(_:elapsed:)` | The current synced line (`currentIndex(at:)`, `Lyrics.swift:77`), cleaned; plain or unsynced lyrics give nil. No word lighting on the lock screen |
| `LockCommand`, `LockCommandPolicy.allows(_:scene:mayShow:)` | `playPause`, `next`, `previous`: there is no other case, so nothing else can be sent. Allowed when the control is in the drawn card and `mayShow` is true. `mayShow` is a plain Bool; L5 passes `presence.lockSurfaceMayShow` |
| Strings | `LockClock.time(_:calendar:locale:)`, `LockClock.day(_:calendar:locale:)`, `LockProgress.times(elapsed:duration:)`, `LockSpoken.card(_:)` ("Playing", or "Title, Artist, paused": never a player's name) |

### Tests first (`Tests/ZeusCoreTests/LockContentTests.swift`)

The full card for a running player's track, with `isPlaying` and `hue`; each of the three hide switches gives the
quiet card with no title, artist, hue, lyric or progress anywhere in the value (REG-494); a browser track, and a
track whose player is not running, give no card (REG-495, two arguments); no track gives no card; no controls
without `canControl`, and then no quiet card; a lyric needs both switches and a synced line; the clock row alone;
cleaning removes a line break, a direction override and a zero-width joiner and cuts at the limit (REG-496); `allows`
refuses a command whose control is not drawn, and every command when `mayShow` is false (REG-497); clock strings for
12 and 24 hour locales; no string carries U+2014 or U+2013.

## L2. Surface lifecycle

### Behaviour

The table under "How the surface behaves" is the behaviour. One reducer owns it; the controller in L5 only runs the
effects it returns and reports what happened.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/LockScreen/LockSurface.swift`:

| Name | Rule |
| --- | --- |
| `State` | A struct, so the rule has what it needs in one place: `phase`, `enabled`, `osMajor`, `bootID`, `lastPresence`, `lastScene`, `lastDisplay`, and `nextGeneration`, which only rises and is never reset by a close or by switching off. `Phase`: `off`, `unavailable(LockUnavailable)` (`missingSymbols([String])`, `untestedSystem(Int)`), `stopped(LockStop)` (`problemLastTime`, `restartLastTime`, `callFailed(step)`), `ready`, `opening(Int)`, `open(Int)`, `closing(Int)` |
| `Event` | `launched(enabled:marker:osMajor:bootID:)`, `enabled(Bool)`, `symbolsLoaded(missing: [String])`, `presence(SessionPresence)`, `scene(LockScene)`, `display(LockDisplay?)`, `opened(Int, failedStep: String?)`, `closed(Int, failedStep: String?)`, `turnOnAgain`, `willQuit` |
| `Effect` | `loadSymbols`, `writeMarker(LockMarker)`, `clearMarker`, `open(generation:frame:scene:)`, `redraw(LockScene)`, `move(CGRect)`, `close(generation:)`. A close always takes the space with it; reading the session again belongs to L0 |
| `reduce(_:_:) -> (State, [Effect])` | `presence`, `scene` and `display` are stored first. The surface is wanted when enabled, the phase is `ready` or later, `lastPresence.lockSurfaceMayShow`, `lastScene` is not empty and `LockLayout.frame` is not nil. Wanted and `ready`: `writeMarker`, then `open` with `nextGeneration`, which then rises. Not wanted and `opening` or `open`: `close`, phase `closing`. A new scene while open: `redraw`, plus `move` when the frame changed |
| Generation | `opened(n)` or `closed(n)` with any number but the phase's own changes nothing. `closed(n)` while `closing(n)`: `clearMarker`, then `ready` (and a new `open` at once when the surface is wanted again) or `off` when switched off. `opened(n)` while `closing(n)` changes nothing: the close is already on its way |
| Version first | `enabled(true)`, `launched(enabled: true)` or `turnOnAgain` on a major version outside `LockSupport.checkedMajors` (26 and 27 once step zero passes on each): `unavailable(untestedSystem)` and no `loadSymbols`. macOS 14.2 to 15 therefore never look up a symbol. Otherwise `loadSymbols`; `symbolsLoaded` with nothing missing gives `ready`, else `unavailable(missingSymbols)` |
| `enabled(false)` | With a window: `close`, and `off` when `closed` arrives (which emits `clearMarker`). Without one: `off` at once. `off` ignores everything but `enabled(true)` |
| Marker | `LockMarker`: the boot id, the macOS build, and a failed step when there is one. At launch: a marker with a failed step gives `stopped(callFailed)`; one with this boot's id, or with no readable id, gives `stopped(problemLastTime)`; one with another boot's id gives `stopped(restartLastTime)`, because the Mac itself went down and Zeus cannot tell why. None loads a symbol. Only `turnOnAgain` leaves: `clearMarker`, then the version check |
| A failed step | `opened` or `closed` with a step: `close` when a window may exist, `writeMarker` carrying the step (kept, not cleared), `stopped(callFailed)`. No retry on the next lock or the next launch |
| New file `LockLayout.swift` | `LockDisplay` (id, frame, scale). `LockLayout.frame(display:scene:)`: 360 points wide, height from the rows the scene has, centred horizontally, inside the band between the system clock and the sign-in controls (`clockBand` and `signInBand`, fractions of the screen height measured in step zero), less any area where macOS draws media controls or notifications of its own (`systemBands`, step zero question 11; empty until measured). Nil when the band is shorter than the card. The window is exactly this frame: no transparent margin exists to catch a click |
| New file `LockScreenTypes.swift` | `LockStatus` (`word`, `symbol`, `canTurnOnAgain`). `LockStatusText.status(for:)` gives nil for off and ready (the switch already says so), "Not available on this macOS", "Stopped after a problem", "Stopped after a restart". `@MainActor public protocol LockScreenControlling: AnyObject` (`status`, `turnOnAgain()`), so L6 compiles without L5 |
| Fail closed | `unknown` presence, an empty scene, a nil frame, a missing symbol, an unchecked macOS version, a present marker or a failed step each end with no window. `willQuit` emits `close`, then `clearMarker` |

### Tests first (`LockSurfaceTests.swift`, `LockLayoutTests.swift`)

Off does nothing for any event and never emits `loadSymbols` (REG-498); a marker at launch stops before any symbol
load, with the right reason for the same boot, another boot and a failed step, and only `turnOnAgain` leaves
(REG-499); a missing symbol is `unavailable`; major versions 14, 15 and 28 are `unavailable` with no `loadSymbols`;
lock with a scene emits `writeMarker` before `open`; a second lock event while open emits nothing; unlock, display
sleep, system sleep, screensaver, console resign and an empty scene each emit `close` (REG-500); lock, unlock, lock
gives two different generations, and a late `closed` or `opened` from the first window changes nothing about the
second (REG-501); a failed open or close step stops, keeps the marker and does not retry; a scene change redraws
without `open`; a display change moves, and closes when the frame is nil; switching off with a window open emits
`close`, then `clearMarker` on `closed`, and ends `off`; quit order. Layout: centred; inside the band on a small
built-in and a large external frame; clear of a system band; nil when the band is too short; clock-only and full
heights differ; every status word is free of U+2014 and U+2013.

## L3. Private space host

### Behaviour

`Sources/Zeus/LockScreen/LockSpace.swift` is the only file in the repo that names the space functions. A
`LockSpaceHosting` protocol (`missingSymbols()`, then `makeSpace()`, `attach(windowNumber:)`, `show()`, `hide()` and
`destroy()`, each returning Bool) lets L5 and every test use a fake. `LiveLockSpace`:

| Part | Rule |
| --- | --- |
| Loading | Opens the window-server framework by its absolute system path (never a bare name) with `RTLD_NOW`, only when asked by the `loadSymbols` effect. Looks up seven names: `SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSHideSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`, `SLSSpaceDestroy`. The typed function table has a failable initialiser that needs all seven; with one missing no function pointer is kept and `missingSymbols()` lists the names |
| Shapes | From public open-source declarations per the study; unverified against 27.2 until step zero. The connection is a 32-bit integer; a space id is 64-bit and never narrowed; create takes the connection, the flag 1 and no options; the level call takes 400; show, hide and the move take arrays; the move selector is 7 |
| One space per lock | The space lives only while a window does. `makeSpace` runs on every open: it creates the space, sets its level and keeps the id; a zero id or an error is `false`. `attach` moves one window by number. `hide` then `destroy` run on every close and drop the id, so no space of Zeus's exists, shown or hidden, while the Mac is unlocked. A `false` from any of the five is a failed step (L2), never ignored. If step zero question 4 shows that a new space per lock misbehaves, one space per launch is the fallback, and that is a change to this plan, not a builder's choice |
| Not done | No removal function is called: L5 closes the window (step zero, question 5). No force-unwrap, no `try!`, no cached pointer when the table is incomplete, nothing on a background thread |
| Clean-room list | `AtticusCleanRoom.forbiddenSourceTokens` (`AtticusCleanRoom.swift:6-13`) keeps banning event posting. Its comment gains one line: space placement in `LockSpace.swift` is the single approved exception. `docs/TILING-PLAN.md:188-189` reads the rule as a ban on all window-server space calls; that stays true for every other file, by lint |

Lints in `test_source_lint.py`, each with a fail-first sample:

- `test_space_functions_are_named_in_one_file`: the tokens `SLSSpace`, `SLSMainConnectionID`, `SLSShowSpaces`,
  `SLSHideSpaces`, `CGSSpace` and `SkyLight.framework` appear under `Sources/` only in
  `Sources/Zeus/LockScreen/LockSpace.swift` (REG-502).
- `test_lock_screen_folder_has_no_way_in`: no file under `Sources/Zeus/LockScreen/` names `TextField`, `TextEditor`,
  `SecureField`, `NSTextField`, `NSTextView`, `keyboardShortcut`, `onDrop`, `registerForDraggedTypes`, `openURL`,
  `Link(`, `NSWorkspace.shared.open`, `NotchModel`, `AgentHub`, `ChatPage`, `NotificationsController`,
  `ClipboardHistory`, `OutputDevices`, `seek(`, `MusicCommand.open` or `musicCommand(.open` (REG-503). It also
  covers the files L4 and L5 add later.
- `test_tests_never_touch_the_lock_space`: nothing under `Tests/` names `LiveLockSpace(` or `dlopen(`.

### Tests first (`Tests/ZeusAppTests/LockSpaceTests.swift`)

With an injected lookup that returns nil for one name, the table is nil, `missingSymbols()` names it and each of
the five calls returns `false`; with all present (dummy pointers, never called) the table exists. No test calls a
real symbol.

Only at the Mac: step zero, then the L5 matrix.

## L4. Card and clock row

### Design

One surface, 360 points wide, corner radius and type from the existing tokens (`TopBarStyle.label`, `Theme`), dark
fill at fixed opacity with no blur (blur over the lock wallpaper is unverified), opaque under Reduce Transparency.

| Part | Design |
| --- | --- |
| Clock row, when on | The time at the left in the display face with tabular numerals, the day and date at the right |
| Full card | Artwork tile at the left (a tile in the card's `hue` when there is no image); title, then artist, each one line, truncated at the tail. Under them the progress line with elapsed at the left and remaining at the right, tabular numerals. It is drawn, never a control: no drag, no click, no adjust. Then previous, play or pause (the glyph from the card's `isPlaying`), next, centred. Then the lyric line, one line, centred, when present |
| Quiet card | One row. The word "Playing" or "Paused", then the three buttons. The play or pause button beside the word is its symbol; no second status symbol is drawn |
| What is left out | Controls that are not allowed are not drawn; nothing is dimmed or disabled. No taglines, helper text, labels, player name, menus, tooltips or links. State is always a word with a symbol, never colour alone |
| Text | Drawn with `Text(verbatim:)`, so nothing from a player or a lyric is parsed as markup |
| Motion | The surface appears and leaves with no animation. A lyric change crossfades over `Motion.crossfadeDuration` and changes at once under Reduce Motion (`Motion.reduced`, `Preferences.swift:66-68`). No spectrum, halo or glow. Progress each second while playing and the clock each minute use `TickingView`, not `TimelineView` (`TickingView.swift:38-43`), so they stop with the window |
| VoiceOver | The card is a container (`.accessibilityElement(children: .contain)`) labelled by `LockSpoken.card`, so each button stays its own element: "Previous", "Play" or "Pause", "Next". The progress line reads its two times. The clock row reads the time and date |

`LockSceneView(scene:artwork:send:)` takes a `LockScene`, an optional image and a `(LockCommand) -> Void`. It reads no
store, model or setting. New `SnapshotRenderer` fixtures beside the music ones (`SnapshotRenderer.swift:589`, `:826`):
full card, full card with a lyric, quiet card playing and paused, card with no controls, clock alone, clock with card.

### Tests first

`Tests/ZeusAppTests/LockSceneViewTests.swift` (REG-504), hosting the view offscreen: a press on each drawn button
sends exactly its command; each button is its own accessibility element; the quiet card's accessibility tree holds
no title or artist; a scene without a control has no such button; nothing on the progress line sends a command.
Offscreen rendering proves layout only, not the lock screen.

Only at the Mac: legibility over light and dark wallpapers; long titles; large text; both accessibility settings.

## L5. Controller, window and wiring

### Behaviour

`LockSurfaceController` (main actor, `@Observable`, conforms to `LockScreenControlling`) holds one `LockSurface.State`
and runs its effects. It has no flags of its own. Its initialiser takes the space host, the media seam, the marker
store, the window factory, the window census and `refreshMeeting`; live ones come only from `AppDelegate`.

| Part | Rule |
| --- | --- |
| Start and stop | Under `on(.topBarServices)` (`StartupPolicy.swift:9-10`), so never in a QA start, and never when `TopBarStyle.isSnapshot`. `applicationWillTerminate` (`AppDelegate.swift:88-97`) sends `willQuit` |
| Inputs | `SessionPresenceMonitor` (L0) for presence; `didChangeScreenParametersNotification` for the display, which is `NSScreen.screens.first`, the primary screen; the media seam for the track; `MeetingState.hideDetails` and the switches for `LockOptions`, read when the scene is built |
| Rebuilding the scene | On every input that can change what is revealed, not only a track change. `MeetingState.active` is a plain static that the feed loop refreshes every 2 s (`AppDelegate.swift:966-969`) and nothing observes it, so `AppDelegate` points L6's new `MeetingState.onChange` at the controller. New cases in `wireSettingsCatalog` (`AppDelegate.swift:882-896`): `lockScreen.enabled` sends `enabled(_:)`; `lockScreen.showTrackDetails`, `lockScreen.lyrics`, `lockScreen.clock`, `privacy.details`, `privacy.lyrics` and `general.meetingMode` rebuild the scene, the last after a meeting refresh |
| Display event | First the injected `refreshMeeting()` (in `AppDelegate`: `MeetingState.refresh` with the argument used at `:969`), then a new scene, then `display(_:)`. A projector plugged into a locked Mac turns the full card quiet before anything moves, not at the next track change |
| `open` | Build a fresh `LockWindow` at the frame; a window number of 0 or less is the failed step `windowNumber`, with no private call made. Then make the space, apply the capture rule, move the window in, show the space, order it front, and report `opened` on the next main-queue turn. Any `false` reports that step. The marker is written only by the `writeMarker` effect, which the reducer emits before `open` |
| `close` | Order out, drop the content view, close the window, hide the space, destroy it, then a census: `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` must list no window of this process at or above `CGShieldingWindowLevel()` (Zeus's other high windows sit at `.screenSaver`, far below: `MarkOverlay.swift:43`, `PointingTextEntry.swift:64`, `PrompterWindow.swift:268`). A `false`, or a window still listed (step `leftover`), goes into `closed(_, failedStep:)` and stops the feature |
| Marker | `lockscreen.open` in Zeus's support folder (`ZeusPaths.swift:10-17`, which honours `ZEUS_SUPPORT_DIR`): the boot id (`kern.bootsessionuuid`, empty when unreadable), the macOS build, a failed step |
| The way out | If the desktop ever stops taking clicks: Force Quit by keyboard, or `killall Zeus`. Ending the process ends its window-server connection and with it the window and the space (step zero, question 12). Zeus has no quit key or CLI quit today (`AppDelegate.swift:773` has no key equivalent; `ZeusCommand.swift:7` has no quit) |
| `LockWindow` | `NSPanel`, style `[.borderless, .nonactivatingPanel]`, `backing: .buffered`, `defer: false` so it has a window-server number before it is moved. `canBecomeKey` and `canBecomeMain` false (unlike `NotchPanel`, `NotchController.swift:741-747`), no shadow, clear background, `hidesOnDeactivate` false, `isReleasedWhenClosed` false, `ignoresMouseEvents = false`, no dragged types, level `CGShieldingWindowLevel()`, collection behaviour `[.stationary, .ignoresCycle, .fullScreenAuxiliary]` (the notch's set at `NotchController.swift:561` without `.canJoinAllSpaces`, because this window sits in one space only; unverified, step zero question 2) |
| First click | The content is a `LockHostingView` whose `acceptsFirstMouse(for:)` returns true, as `NotchHostingView` does (`NotchController.swift:735-738`): the panel is never key, so every click is a first click and must press the button under it |
| Capture rule | `ZeusWindowSharing.apply(to:visibleInShare:surface: .zeusStandard)` at creation with the current policy, as `NotchController.swift:564`. `ZeusWindowSharing.refresh` already walks `NSApp.windows` (`ZeusWindowSharing.swift:45-51`), so a policy change reaches the window and that file needs no edit |

`LockMedia.swift`: `@MainActor protocol LockMediaProviding` (`track: LockTrack?`, `artwork: NSImage?`,
`lyricLine(at:) -> String?`, `send(_ command: LockCommand)`, `onChange`). `TopBarLockMedia` adapts today's model:
`TopBarModel.nowPlaying` (`TopBarModel.swift:128`) through `withObservationTracking`; `playerRunning` is the check
at `TopBarServices.swift:271-273`, read again when a player app launches or quits (the workspace's launch and
terminate notifications fire `onChange`); `canControl` is running and `Automation.allowed`; `send` maps to
`musicCommand` (`:212`) only after `LockCommandPolicy.allows`; artwork is `ArtworkStore.shared.image(for:)`
(`ArtworkStore.swift:40`) and is nil for the quiet card; the lyric comes from `LyricsStore.shared.state(for:)`
(`LyricsViews.swift:46`). It calls `viewerAppeared`, `load(for:)` and `viewerLeft` (`LyricsViews.swift:53-56`) only
while a full card with lyrics is up. When the sources wave lands, only this adapter changes: it reads the hub and
maps a browser source to `kind: .other`.

Fail closed: a command that fails while locked changes nothing visible; today's optimistic toggle is corrected by the
read-back at `TopBarServices.swift:258-265`. A notch hint raised by a refused command (`:196-199`) cannot occur,
because controls are not drawn without consent. A failed step leaves the feature stopped and the notch as it was.

### Tests first (`Tests/ZeusAppTests/LockSurfaceControllerTests.swift`, `@MainActor @Suite(.serialized)`)

With a fake host, fake media, a fake census, a temporary marker folder and a fake window factory: a locked presence
with a track makes exactly one window, one space and one `attach` (REG-505); unlock closes the window, destroys the
space and removes the marker; lock, unlock, lock makes two different windows and two spaces (REG-506); a `false` from
`attach`, `hide` or `destroy`, a window number of 0 and a leftover in the census each leave no window, the status
"Stopped after a problem" and a kept marker, and a second controller on the same folder starts stopped; a marker
present at start makes no host call at all (REG-507); meeting mode turning on while the full card is open redraws
the quiet card, with no title or artist in the hosted tree (REG-508); a display event refreshes meeting state
before the scene and the move; each of the six content settings rebuilds the scene; the switch off makes no host
call; a command is forwarded only through `LockCommandPolicy`; `willQuit` destroys the space. The suite's
`native-LockSurfaceControllerTests` check goes into `qa/feature-map.json` with it.

## L6. Settings

| Id | Where | Control | Default | Notes |
| --- | --- | --- | --- | --- |
| `lockScreen.enabled` | Appearance, new card "Lock screen" after "Screen" (`GlanceSettingsPages.swift:380`) | Toggle "Show" (the card's title says where) | Off | `opt_in`; never enabled by import |
| `lockScreen.showTrackDetails` | Same card | Toggle "Song and artist" | On | Never enabled by import |
| `lockScreen.lyrics` | Same card | Toggle "Lyric line" | Off | Never enabled by import; not drawn unless `privacy.lyrics` and "Song and artist" are on |
| `lockScreen.clock` | Same card | Toggle "Time" | Off | macOS draws its own clock; kept because the brief names a clock row (decision 11) |
| `lockScreen.status` | Same card, last row, only when there is a problem | Status: word with warning symbol; "Turn on again" when stopped | n/a | `SettingStatus` case (`SettingsStore.swift:438`) fed by `LockScreenControlling.status`; no row for off or ready |

Rows go in `scripts/gen-settings-catalog.py` under `S='appearance'` (`:30`), group "Lock screen", after the screen
rows (`:86`); regenerate, never hand-edit; `scripts/check-settings-catalog.sh` passes. The generator's description
column is filled for the inventory, but `GSLockScreenCard` passes no `text:` to `GSToggleRow`
(`GlanceSettingsStyle.swift:116-120`, where it is optional): titles and at most one status word, no helper text.
The three lower rows are not drawn while the first is off. The card reads the live status through a weak
`LockScreenBridge.controller` (declared in the card file, set by L5 in `AppDelegate`, as `NotchControllerBridge` is
declared at `AgentTroubleCard.swift:7` and set at `NotchController.swift:50`). Snapshots never start the controller.

In `SettingsStore.swift`: `neverEnabledByImport` gains the three `lockScreen` switches and `privacy.details`; a new
`neverDisabledByImport` holds `general.meetingMode`, checked beside the rule at `:314` (a "false" for a listed id is
skipped). `MeetingState.refresh` sets `active` through one private setter (both assignments, `:342` and `:347`)
that calls a new `static var onChange: (() -> Void)?` only when the value flips.

Tests first (`LockScreenCardTests.swift`, a fake `LockScreenControlling`): the button calls `turnOnAgain` and shows
only when `canTurnOnAgain`; no status row for off or ready; the lower rows hide with the switch off.
`SettingsCatalogTests` gains one test with five arguments: an import never turns on `lockScreen.enabled`,
`lockScreen.showTrackDetails`, `lockScreen.lyrics` or `privacy.details`, and never turns `general.meetingMode` off
(REG-509); and, unnumbered, `lockScreen.enabled` has a false default and `validate_table` lists it. Both suites get
their `native-` check in `qa/feature-map.json` here. The flip-only hook is seen at the Mac.

## Security: how this could be abused, and how each way is closed

| Abuse | Closed by |
| --- | --- |
| Another program of the same user posts a fake lock notification to put a window above every app | Notifications only ask for a read; the window opens only when the session dictionary says locked and on console (L0) |
| A fake unlock or screensaver notification | It can only close the window. A fake unlock is overruled by the next read; a fake screensaver start hides the card until the next stop or unlock |
| A forged player notification puts chosen text on the lock screen (the players' notifications are open to any process, `TopBarServices.swift:100-111`, and `updateMusic` takes one with no player running, `:169-186`) | No card unless the player is running (L1). Then plain text only, cleaned and capped (L1), drawn verbatim (L4), in a fixed media layout with no field, avatar or system wording. Residual: while a player runs, such a program picks up to 80 characters of title, and the picture in the next row |
| A chosen or hostile image | Artwork follows the notification: `ArtworkStore` looks it up on the network from the track id or from title and artist (`ArtworkStore.swift:134-150`), so a forged notification also picks the picture. The lock card adds no fetch or decode of its own and shows no picture on the quiet card or with no player running |
| Hostile lyric text from the lyrics service | Same cleaning, 120 characters, one line, and only with both lyric switches on |
| A web page's title or image on the lock screen | Browser sources give no card (L1) |
| A hostile device name | No output device is listed or switched from the lock screen |
| Someone at the locked Mac does more than transport | `LockCommand` has three cases; seek, Open, modes, volume and outputs do not exist there; the folder lint bans text entry, links, drops and agent types (L3) |
| Typing into the window | It cannot become key or main and holds no text view. Keyboard reach is still checked in step zero |
| A dropped file | No dragged types are registered |
| A settings file that turns the surface or details on, or switches off what hides them | `neverEnabledByImport`, now with `privacy.details`, and `neverDisabledByImport` for meeting mode (L6) |
| A meeting or a projector starts while the full card is up | The meeting hook and the display event rebuild the scene at once (L5) |
| A space or window left above the desktop that takes its clicks | A new space per lock, destroyed on close; every result checked; a census after each close; any doubt stops the feature; Force Quit by keyboard as the way out (L3, L5) |
| A test run that makes other apps act as if the Mac had locked | Injected notification centres and a lint over `Tests/` (L0) |
| A same-user program flips the stored switch, or deletes the marker | Not closed: such a program can already script the players and write Zeus's settings. The marker only turns the feature off |
| A planted library | The framework is opened by absolute path on the sealed system volume, never by name |
| Another user after a fast switch sees the card | Not on console means closed (L0), before any read |
| Screen sharing or recording a locked Mac | The capture rule is applied like every Zeus window; details hide in meeting mode. Treat the surface as recordable all the same |
| A crash or a failing call on every lock | The marker stops the feature after the first one, across launches, until the owner turns it on again |

## Repo hazards that apply

- Swift 6: observers keep `queue: .main` plus `MainActor.assumeIsolated`; the timer callback hops the same way
  (`NotchController.swift:96-98`). Function pointers from `dlsym` are cast to `@convention(c)` types and stored in a
  `Sendable` struct of optionals, not in `nonisolated(unsafe)` statics. No semaphore or group waits.
- Sandboxes cannot compile Swift (TYPE-012): budget a Mac build before any ticket is called done.
- The em dash lint (`test_user_visible_swift_strings_have_no_em_dash`, `test_source_lint.py:126-132`) covers
  `Sources/Zeus` only (`:14`, `:46-47`); the Core tests check their own strings.
- `ZeusWindowSharing` applies to the new window (above). `NotchController` and its lint anchors are not touched.
- Settings generator, REG ids and shared files: see the order table. `docs/STATE-MACHINES.md` gains two rows.
- `MusicAwakeHold` has no lock rule (neither `MusicAwake.swift` nor `MusicAwakeHold.swift` reads lock or session
  state; the only matches for "lock" there are the word "clock"): with `keepAwake.whileMusic` on, a locked Mac that
  plays music keeps its display lit, and L0's watch then reads once a second. Not changed here; see decisions.

## Decisions the owner owes

1. "Song and artist" default. Plan: on once the surface is on. The other choice: off, so the first card is quiet.
2. `privacy.details` off also hides track details on the lock screen. Plan: yes. Today that switch is about commands.
3. Seek from a locked Mac. Plan: none; progress is read only. The other choice: a drag on the line, as a later ticket.
4. The version gate. Plan: the surface arms only on macOS major versions checked at a Mac (26 and 27), so a new major
   version shows "Not available on this macOS" until a Zeus update. The other choice: symbols alone decide.
5. The music display hold while locked. Plan: recommend it stands down while the session is locked; that is a change
   to the music wave's M4 and is not built here.
6. Card placement. Plan: one fixed band from step zero. The other choice: a Top, Middle, Bottom setting.
7. Distribution. Private symbols rule out the Mac App Store. Whether notarization accepts them is unverified here;
   the owner confirms on the next signed build (feature S06).
8. The written exception to the clean-room rule: space placement in one file, event posting still banned (L3).
9. If macOS draws media controls of its own on the lock screen (step zero question 11, unverified): a second card
   from Zeus beside them, or a card only where the system shows none.
10. Import. Plan: a file can no longer turn `privacy.details` on or `general.meetingMode` off, anywhere in Zeus. The
    other choice: leave import alone, and any import that loosens either also sets `lockScreen.showTrackDetails` off.
11. The clock row. Plan: keep it, off by default. The other choice: drop it, since macOS draws a clock.
12. A keyboard quit. Plan: Force Quit is the way out. The other choice: a `zeus quit` command, as its own ticket.

## Out of scope

- The sign-in window after a restart (Zeus is not running), full-screen artwork, any edit to the wallpaper store,
  widgets (weather, battery, headphones, Focus), lock and unlock sounds, animated artwork, word-lit lyrics.
- Browser media on the lock screen. Seek, shuffle, repeat, Open, volume and output choice from a locked Mac.
- Moving the notch and the morning brief onto `SessionPresence`. Hiding the card under the system voice assistant.

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the ticket's new names).
2. `swift build --build-tests`, then `swift test --filter` for `SessionPresenceTests`, `LockContentTests`,
   `LockSurfaceTests`, `LockLayoutTests`, `SessionPresenceMonitorTests`, `LockSpaceTests`, `LockSceneViewTests`,
   `LockSurfaceControllerTests`, `LockScreenCardTests`, and the pinned `SettingsCatalogTests`,
   `AtticusCleanRoomTests`, `NowPlayingTests`, `LyricsTests`.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared.
4. `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py'`, the settings generator and its check,
   `./tools/check.sh` development mode from a worktree under `<models-dir>`.
5. An independent review of each diff. For L3 and L5 the reviewer reads the symbol table, the open and close order
   and the marker line by line.
6. Still owed on a real Mac by the owner, on macOS 27.2 and one macOS 26 Mac:
   - Step zero, all twelve questions, before L3 and L5 start.
   - Lock with Music playing: the card sits inside the band, never over the clock, the sign-in controls or anything
     macOS draws there. Play, pause, next and previous act on the first click. The same with Spotify.
   - Unlock by password and by Touch ID: the card is gone at once, and clicks reach the desktop where it was and
     everywhere else. Repeat 20 times; a fresh window each time; no leftover.
   - Launch Zeus while locked with music playing: the card appears. Quit the player while locked: it goes.
   - A mirrored display plugged in, and a call started in another app, while the full card is up: the quiet card
     within two seconds. Each hide switch gives it too. With details hidden no title shows, VoiceOver included.
   - Lock, display sleep, wake: a card again. Lid closed and opened. Screensaver start and stop while locked.
   - Fast user switching out and back: the other user never sees the card; it returns only on this user's lock screen.
   - Two displays; unplug one while locked; clamshell with an external display; a resolution change.
   - The lyric line with both switches on; none with either off. The clock row alone, and across midnight.
   - Automation not granted for a player: no controls, and no prompt appears after unlock.
   - Kill Zeus, and Force Quit it by keyboard, while the card is up: nothing stays, the desktop takes clicks, and
     the next launch shows "Stopped after a problem" until "Turn on again". Restart the Mac instead: "Stopped after
     a restart". Rename one symbol in a debug build, or use a macOS 15 Mac: "Not available on this macOS", no card.
   - An imported file that sets `privacy.details` on and meeting mode off changes neither.
   - Typing, Tab, Space and Return on the lock screen never reach the card. A file dragged over it does nothing.
   - A screen recording of the locked Mac with "show in screen sharing" off and on: record what is captured.
   - Reduce Motion and Reduce Transparency. `TickingView` runs in the lock window and stops when it closes.
   - Idle cost: locked, music paused, card up, 60 s: `PID=<pid> SECONDS_IDLE=60 scripts/check-perf-budget.sh`.
   - The wake word after lock, display sleep and wake: silent until unlock; listening after a plain launch (L0).

## Review notes

Revised after an adversarial review of the first draft; each finding was checked against `9f2ffe4` and the study.
What changed. L0 now owns every re-read (a settle run and a watch), clears a stale lock hint on a session return or
on an unlock that a read sees, reads once at start, is started by the wake word, and takes injected notification
centres. L2's state is a struct whose counter never resets; the version is checked before any symbol lookup; a
crash and a failed step stay stopped across launches, a restart is told apart, and switching off clears the marker.
The space is made and destroyed per lock, each result is checked and a census follows each close. The scene is
rebuilt on a meeting flip, six settings and display events. A track with no running player draws nothing. Import
cannot loosen the two older hide switches. Seek left the lock screen. The window takes first clicks and has a
number before it is moved. L1 no longer needs L0, L5 follows L6, each app suite carries its own feature-map check,
five line references are corrected, and the labels, the status row and the privacy wording were cut back.
Unverified and marked so above: the screensaver notifications, the lock key and boot id on 27.2, function shapes,
pointer and keyboard reach, the collection behaviour, delivery and scripting while locked, the system's own media
controls, capture exclusion, VoiceOver reach, blur, notarization. Each has a step zero question or a Mac check.

Findings not taken as written:

- Drop the clock row: kept, because the brief for this area names one. Off by default; decision 11 can drop it.
- Clear the hint when the lock key is present and false: the key may be absent, not false, when unlocked (it is
  not in the header; unverified), so the hint clears when a read says unlocked right after one that said locked.
- Let the wake gate's timer poll the session: that puts lock polling in a second place, and L0's own schedule
  covers the case. That timer is also 1.5 s, not 2 s (`TickingView.swift:28`).
- Seek by a defined pointer gesture, or by VoiceOver only: neither. A control only some people can reach is worse
  than none, so seek is gone and decision 3 offers it later.
- Name the existing quit shortcut or CLI as the way out: neither exists (`AppDelegate.swift:773`,
  `ZeusCommand.swift:7`). Force Quit is named and decision 12 offers `zeus quit`.
- "macOS draws its own lock screen media controls" and "AppKit already loads the framework into every app" were
  not verified here. The first became step zero question 11 and decision 9; the second is left out of the wording.
