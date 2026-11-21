# Notch system-wide now-playing source: plan and design

Written 14 November 2026 against `codex/island-20261113` (HEAD `9f2ffe4`), read only. Fourth wave after
`docs/NOTCH-MUSIC-PLAN.md`, `docs/NOTCH-SURFACE-PLAN.md` and `docs/NOTCH-SOURCES-PLAN.md`. Same rules: pure rules in
ZeusCore with tests first, `docs/DESIGN-DIRECTION.md` for anything visible, nothing accepted until the named tests run
on macOS and the behaviour is seen on a Mac. Line numbers below were read on `9f2ffe4`; the two house plans cite
`47566d1`, so some of their numbers have moved. The owner approved the route (decision D1 of the private study).
Revised the same day after an adversarial review; what changed is in "Review notes".

**Refactor first.** Today's model cannot take a third kind of source: `NowPlaying.Player` is a closed two-case enum
and `NowPlaying.player` is a stored property (`Sources/ZeusCore/TopBar/NowPlaying.swift:6-34`); none of the A1 types
exist yet (no `NowPlayingSource.swift`, `NowPlayingArbiter.swift` or `NowPlayingHub.swift` in the tree). The refactor
is ticket A1 of `docs/NOTCH-SOURCES-PLAN.md`, already scoped there, plus ticket P1a here, which adds the third case.
P1e and P1f cannot start before both have merged. P1b, P1c and P1d touch no A1 type and may start once step zero
passes.

What it is: with one switch on, Zeus shows what any app on the Mac is playing (title, artist, album, artwork,
position, play state) and can send play, pause, next, previous and seek. On recent macOS the system now-playing
service answers only programs signed as part of the system, so the read runs inside the system's own Perl
interpreter, which loads a small library that Zeus ships. Off by default. Tested before use. Closed on any failure.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| P1.0 | Proof on the owner's Mac | Third-party accounts and one ambiguous local read | A recorded pass or fail in a signed build on macOS 27.2, and on each older release the feature is to support, before any builder starts |
| P1a | A third source case | A1 plans a player and a browser source only | `NowPlayingSource.system`, its capabilities, artwork held in memory, a command path in the hub |
| P1b | Life of the helper | Nothing | One pure reducer (State, Event, Effect), the line decoder, launch and orphan rules |
| P1c | The helper library | Nothing | Zeus's own library: loads the private framework at run time, checks every symbol, speaks one line protocol |
| P1d | Packaging and identity | Only `Contents/Helpers` is signed and verified | Library built, placed, signed, verified; a preflight that refuses any library that is not Zeus's own; lints |
| P1e | The feed | Nothing | A child owner, the self-test canary, and a feed into the A1 hub |
| P1f | Settings | Nothing | One switch, one status row, the import guard, one diagnostics row |

Worktrees and order:

| Ticket | Files it owns | Runs |
| --- | --- | --- |
| P1.0 | Nothing in the repo (throwaway, kept outside it) | First. Owner at the Mac |
| P1a | `NowPlayingSource.swift`, `NowPlayingArbiter.swift` (tie order, `hasPlayerSession`), `NowPlayingHub.swift` (`systemCommand`, inline artwork hand-off), `Artwork.swift`, `ArtworkStore.swift`, `NowPlayingDisplay.swift` if A4 has merged, their tests | After A1. If A1 has not started when this plan is approved, A1 absorbs P1a |
| P1b | New `ZeusCore/TopBar/SystemSourceMachine.swift`, `SystemSourceWire.swift`, `SystemSourceLaunch.swift`, three test files, `docs/STATE-MACHINES.md` (one entry) | After P1.0, parallel with P1c |
| P1c | New `Sources/ZeusNowPlayingHelper/**`, `Package.swift`, new `Tests/ZeusAppTests/SystemSourceHelperTests.swift`, its row in `qa/feature-map.json` | After P1.0, parallel with P1b |
| P1d | `scripts/bundle.sh`, `scripts/verify-release-signature.sh`, `qa/release-scripts/test_release_scripts.py`, `PeerSigning.swift` (three functions and their stubs), `AtticusCleanRoom.swift` (comment), `test_source_lint.py`, new `Tests/ZeusCoreTests/BundledLibraryRuleTests.swift` | After P1c. Uses no P1b type |
| P1e | New `Zeus/TopBar/SystemNowPlayingFeed.swift`, `SystemSourceChild.swift`, `SystemSourceCanary.swift`, new `ZeusCore/TopBar/SystemSourceRules.swift`, one line in `TopBarServices.start`, `AppDelegate.swift` (quit hook, catalog case, the "Check again" action), two test files, its row in `qa/feature-map.json` | After P1a, P1b, P1c, P1d |
| P1f | `scripts/gen-settings-catalog.py` and its outputs, `SettingsStore.swift`, `GlanceSettingsPages.swift`, `LiveDiagnostics.swift`, their tests | After P1e |

No file appears in two tickets of this plan, except the two append-only registers. Every branch appends to
`qa/regressions.json` (feature `F13`, as the sources plan uses). P1c and P1e each append one native-fixture row to
`qa/feature-map.json` for their ZeusAppTests suite, or CI compiles the suite and never runs it; the new ZeusCoreTests
suites need no row, because that module is bound whole (`qa/feature-map.json:398-402`). P1f shares
`SettingsStore.swift`, `GlanceSettingsPages.swift` and the generator with A3; whichever merges second rebases. This
plan reserves REG-470 to REG-489: P1a 470 to 472, P1b 473 to 478, P1c 479 and 480, P1d 481 to 483, P1e 484 to 487,
P1f 488 and 489. Clashes go through `<models-dir>/zeus-merge-reg.py`. The highest id in the tree today is REG-409.

## Open source checked first

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| The route itself: a library hosted in the system interpreter, and a self-test that publishes a short entry when nothing plays | ungive/mediaremote-adapter | BSD-3-Clause | Technique only. README read on 14 November 2026 for interface facts. Not bundled, not vendored, no code read into Zeus |
| A Swift wrapper around that route | ejbills/mediaremote-adapter | BSD-3-Clause | Not used |
| The gate, and the rule that commands reach the app that started playing last | servitola/nowplayingseek | AGPL-3.0 | Technique only |
| Signing observation for the hosted library | michael-berardi/ultra-media-remote | MIT | Technique only, single source |
| Launching the interpreter from an app | TheBoredTeam/boring.notch | GPL-3.0 | Technique only. No code read into Zeus |
| Bounded helper reads | justinmdickey/goplaying | MIT | Technique only: absolute paths, a time bound |
| Publishing an entry | MediaPlayer framework documentation (`MPNowPlayingInfoCenter`) | n/a | Public interface for the canary |
| Loader functions | The interpreter's own DynaLoader documentation | n/a | `dl_load_file`, `dl_find_symbol`, `dl_install_xsub` |

No code is copied and no dependency is added. Zeus writes its own helper library, its own one-line launch program and
its own line protocol; the design differs from the prior art on purpose (one resident child and a pipe in both
directions, not one process per command with parameters in the environment). Nothing here needs a notice in
`NOTICES.md`. If step zero shows that an own implementation cannot work, bundling becomes an owner decision (below).

## System interfaces relied on, and where each was checked

| Interface | Checked against | State |
| --- | --- | --- |
| Since macOS 15.4 the service answers now-playing reads only to callers whose signing identifier begins `com.apple.` or that hold a private entitlement; others get an empty answer and no error | Study section 3.1 (third-party accounts, no vendor statement). One local read on 27.2 returned empty with nothing playing, which cannot tell the gate from an idle Mac | Unverified in a Zeus build. P1.0 |
| `/usr/bin/perl` exists, identifier `com.apple.perl`, platform code, version 5.34.1, slices `x86_64`, `arm64e` and `arm64e.x1`, code directory flags none. `/usr/bin/perl5.34` is a second full copy, identifier `com.apple.perl5` | `codesign -dv`, `lipo -archs` and `ls -l` on this Mac, macOS 27.2, 14 November 2026 | Verified here, on 27.2 only |
| On older releases (the package floor is 14.2, `Package.swift:6`) the launch path may be a selector that re-executes a versioned copy chosen by a user-writable preference, so the running image would be `/usr/bin/perl5.x` | The reviewer's report. No such Mac in this session | Unverified. P1.0 item 10. The running-child check (P1e) holds either way |
| The loader is built into the interpreter: after `DynaLoader::boot_DynaLoader` the three loader functions exist with an empty environment and no module file read from disk (`%INC` empty) | Run on this Mac with `env -i /usr/bin/perl -f` | Verified here |
| The interpreter loads a plain `arm64`, ad hoc signed, third-party library | Run on this Mac against an unrelated library | Verified here for loading only. Whether the service answers such a library is P1.0 |
| The hosted library must carry a Developer ID signature or the service answers empty | Study claim, one integrator, macOS 26 | Unverified. P1.0 |
| Private symbols `MRMediaRemoteGetNowPlayingInfo` and `MRMediaRemoteSendCommand` resolve on 27.2 | Study, local probe | Verified by the study |
| The other symbols P1c needs (play state, client identity, change notifications, elapsed-time setter, the dictionary key constants) | Public header dumps of the framework | Unverified. P1.0 fixes the list |
| Command numbers: 0 play, 1 pause, 4 next, 5 previous | Prior-art README | Unverified on device. P1.0 |
| Commands reach only the app the system elected (the latest to start playing) | Study, third-party accounts on 26.6 and 27.0 | Unverified on 27.2. P1.0 |
| An app can publish an entry with `MPNowPlayingInfoCenter` (`nowPlayingInfo`, `playbackState`) without playing sound, and it disappears when cleared | Public framework; the prior art's self-test uses the same idea | Unverified. P1.0 |
| A file's signature checked against a requirement | Not in the tree: `Sources/ZeusCore/PeerSigning.swift:103` validates a file with no requirement, and the only requirement check (`:143-147`) is on a running process. The public Security calls take a compiled requirement for a file too | New code in P1d, public interface |
| Screen lock and unlock arrive as the distributed notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`; a console switch as the workspace session notifications | Already observed at `Sources/Zeus/Voice/WakeWordController.swift:62-69` and `Sources/Zeus/Notch/NotchController.swift:90`. The session pair is public; the lock pair has no vendor documentation | Verified in code only |
| What the service reports while a player app on this Mac drives playback on another device or a network speaker | Nothing found. The Spotify notification Zeus parses (`Sources/ZeusCore/TopBar/NowPlaying.swift:61`) has no known field that tells local from remote | Unverified. P1.0 item 9 |
| The interpreter may leave the default install in a later macOS | The vendor's macOS 10.15 release notes, from memory; the study found no dated statement | Unverified |

## Privacy and consent

- The route raises no system prompt, so the owner's switch is the only gate. `music.systemSource` is off by default,
  joins the `opt_in` tuple (`scripts/gen-settings-catalog.py:243-246`) and `SettingsStore.neverEnabledByImport`
  (`Sources/Zeus/App/SettingsStore.swift:255-258`), so a settings import can turn it off and never on (`:314`).
- With the switch off nothing of this feature runs: no child process, no library load, no private symbol, no canary,
  no MediaPlayer call. Never at launch, never from onboarding, never from the permission sweep, never from a test.
- No new permission, entitlement or usage string. The app is not sandboxed (`Resources/Zeus.entitlements`) and may
  start a system binary. The Zeus executable itself never names or loads the private framework.
- With the switch on, Zeus can see what every app plays, including video and browser media. Titles, artists, albums,
  bundle ids and artwork stay in memory. Nothing is written to disk or to a log, and nothing reaches a model, voice,
  chat or agent context. Diagnostics carry a state word and a reason code. The existing "Now playing" row, whose
  summary can be copied (`Sources/Zeus/Settings/GSLiveDiagnosticsCard.swift:113`), says "Another app" for a system
  item, never the app's name (P1f).
- Artwork arrives as bytes from the helper. Zeus fetches no URL on behalf of another app's metadata.
- No lyrics for a system item. It has no `lyrics` capability, so this switch never sends the title of a video, a
  podcast or private-window media to the lyrics service under a consent given for songs in Music and Spotify.
  Adding it later is owner decision 3.
- A native call app is never a source: an item whose bundle id is a known call app (`ScribeCallDetection.identify`,
  `Sources/ZeusCore/Scribe/ScribeLiveLogic.swift:446`) is dropped and gets no command. A call in a browser tab cannot
  be told from other browser media: that rule needs window titles (`:451`), and reading them needs a permission this
  feature never asks for. Owner decision 8.
- Screen sharing: no new window. The notch and Home already follow `ZeusWindowSharing.apply`
  (`Sources/Zeus/App/ZeusWindowSharing.swift:29`), and `general.showInScreenSharing` is off by default, so another
  app's title is not captured unless the owner chose that.
- The canary publishes the word "Zeus" and a random token through the public interface, for at most 3 s, only when
  the service reports nothing (with a player claiming to play, only after 5 s of that), and never while the screen
  is locked, the Mac is asleep or another user holds the console. So it never shows on the lock screen.
- Control comes only from the owner: a tap in the notch, or "pause media while dictating"
  (`Sources/Zeus/Dictation/DictationController.swift:608-610`). No model or voice action can send a system command
  (lint, P1d). Voice transport stays on the media keys, as the sources plan states.

## What the owner sees when the vendor closes the route

Items from other apps stop appearing in the notch, as if nothing were playing there. Music, Spotify and Chrome keep
working through their own feeds. In Settings the status row under the switch reads "Unavailable" beside a warning
triangle, with a "Check again" button. The switch stays on, so a later system update that reopens the route is picked
up by the next unlock, relaunch or press. No alert, no banner, no repeated retry. Diagnostics shows the reason code.
A Mac on a release below the feature's floor reads the same, with its own code.

## P1.0 Step zero, on the owner's Mac, before any builder starts

A throwaway probe kept outside the repo and never merged, in a build signed the way a release is signed. Record:

1. With a track playing in an app that has no scripting feed, the probe library inside the interpreter reports it.
2. The same read from an ordinary process, with the track still playing, is empty. This separates the gate from idle.
3. The same probe with an ad hoc signature and with the local development identity: answer or empty.
4. Which symbols resolve, which call gives the playing app's bundle id, and whether change notifications arrive inside
   the interpreter process. If they do not, P1c polls (1 s while an item exists, 5 s otherwise), the idle claims of
   this plan become "one timer, in the child", and the child's CPU is measured in that mode.
5. Whether an empty environment is enough for the service call, not only for loading.
6. The canary: a published entry without sound is seen by the probe, shows and clears in the system's own
   now-playing display within a second, and the app that was elected before keeps the media keys afterwards.
7. Play, pause, next, previous and seek reach the elected app.
8. The probe exits within a second of its parent being killed.
9. What is reported for media in a private browser window, for a call in a browser tab, for another device
   streaming to this Mac, and while Spotify or Music on this Mac plays on a phone, a speaker or a network speaker.
10. On each older release the feature is to support (one 14.x and one 15.x Mac at least): items 1 and 8, and the real
    path of the running interpreter. With no such Mac, the feature's floor is the release tested (owner decision 9).
11. The picture formats real players hand over, which fixes the list the helper decodes.

A fail on 1 stops the wave. A fail on 6 removes the canary (owner decision 2). Results go in the plan before P1b.

## P1a. The third source case

### Behaviour

- A system item is one more entry for the A1 arbiter. The service reports one item at a time, the app it elected.
  The arbiter keys entries by source, and this key holds the app's bundle id (`docs/NOTCH-SOURCES-PLAN.md:102-106`),
  so a change of app would leave the old entry behind: P1e's slot rule keeps at most one system entry. It is shown
  by A1's rule (the source that started playing last).
- A pin (`music.follow` set to Music or Spotify) shows only that player; the system source is not read at all.
- An item from Music or Spotify is not a system entry: their own feeds stay the source of truth, so with one player
  nothing changes from today. An item from Chrome is dropped while A3's browser feed is on and connected.
- Controls offered: play or pause, next, previous, seek when there is a duration. Never shuffle or repeat here.
- Open activates the running app with that bundle id. It never launches an app from a bundle id it was handed.

### Rules (ZeusCore, pure)

In A1's `Sources/ZeusCore/TopBar/NowPlayingSource.swift`:

- `SystemMediaKey` (`appBundleID`, `appName`; Hashable, Sendable). `NowPlayingSource` gains `.system(SystemMediaKey)`:
  `kindName` is the app name, or "This Mac" when empty; `baseCapabilities` are `playPause`, `next`, `previous` and
  `seek`, never `lyrics`; `scriptedPlayer` is nil; `persistsDerivedData` is false; `artworkStrategy` is a new case
  `inline`; `isSystem` is true for this case only.
- `NowPlaying.capabilities` for a system item: minus `seek` when `duration == 0`. Never `lyrics`, whatever the item.
- `NowPlayingArbiter`: `hasPlayerSession` ignores system entries, so voice "play" still resumes Spotify
  (`Sources/Zeus/Intent/FastActions.swift:81`); ties go Music, Spotify, system, then browser.
- A4's `NowPlayingDisplay`, when merged: the source line is the app name, the glyph `play.rectangle`, the open label
  "Open" plus the app name, and the accessibility label "Playing in" plus the app name and the title.

These are the A1 and A4 types this plan depends on, in full: `NowPlayingSource`, `SourceCapabilities`,
`MusicCommandKind` (with its explicit `play` and `pause`), `NowPlaying.source`, `.rate` and `.capabilities`,
`NowPlayingArbiter` (`Follow`, `Entry`, `update`, `remove(where:)`, `entry`, `shown(follow:)`, `commandTarget`,
`hasPlayerSession`), `NowPlayingHub` (entry updates, the follow setting, `pauseForDictation`,
`resumeAfterDictation`, `observeMusicPage`, the optional command closure pattern of `browserCommand`), the
`artworkStrategy` switch in `ArtworkStore`, `persistsDerivedData` in `LyricsStore`, and `NowPlayingDisplay`.

### App side

- `NowPlayingHub` gains `systemCommand: ((MusicCommandKind, Double?, SystemMediaKey) -> Void)?`; nil does nothing.
  The hub checks capabilities first, as for every source, and updates the entry at once after a command.
- `ArtworkStore.load`: the `inline` strategy returns the bytes the feed handed over, before the disk read
  (`Sources/Zeus/TopBar/ArtworkStore.swift:117`), and never saves (`:177`).

Fail closed: an unknown bundle id shows "This Mac". A command outside the capabilities, or with a nil closure, does
nothing. Inline artwork that does not decode leaves the hue tile.

### Tests first

`NowPlayingSourceTests` gains the system case (name, empty name, capabilities with and without a duration, no
`lyrics` capability even with an artist and a duration, `isSystem`, no disk);
`NowPlayingArbiterTests` gains the tie order and `hasPlayerSession` with only a system entry; `NowPlayingHubTests`
gains a refused out-of-capability command, a nil `systemCommand`, a dictation resume after the entry went (never
reaching Music), and inline artwork that leaves the artwork directory empty. Pinned suites pass unchanged.

## P1b. Supervisor, wire and launch rules

### Behaviour

- One helper process at most. Every start goes through the same test, so there is no test that runs once and goes
  stale: preflight, then a handshake that reports every symbol present, then proof that the service really answers.
- Proof is a real item, or the canary read back. An empty answer alone proves nothing, because a closed gate looks
  exactly like silence. Only a failed canary says the route is closed.
- A failure is a helper that exits, or a handshake, read, command or ping that goes unanswered. Each stops the
  helper, drops the entry and runs the whole test again after a back-off; the fifth in a row ends in "Unavailable".
- A doubt is Music or Spotify playing by its own feed while the helper has reported nothing for 5 s. A closed route
  looks like that, and so does a player app driving playback on a phone or a speaker. So a doubt decides nothing:
  it runs the canary once, and the canary decides. The price: with a closed route and a player really playing
  here, the canary may take the media keys for up to 3 s, once (step zero item 6 records whether they return).
- "Unavailable" shows nothing and retries nothing until the Mac is unlocked or wakes, Zeus relaunches, the switch
  is cycled or the owner presses "Check again".
- Nothing runs on the lock screen, asleep, or while another user holds the console: the helper is stopped and the
  canary is never published there. The test runs again at unlock.
- No repeating timer in Zeus. Every wait is a deadline the reducer asked for, tagged with the run it belongs to.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/SystemSourceMachine.swift`,
`SystemSourceMachine.reduce(_:_:now:) -> (State, [Effect])`. `now` is monotonic seconds handed in by the feed, and a
run's random token arrives with its preflight verdict, so the reducer makes neither time nor randomness. Everything
a transition branches on is a field of `State`; the feed keeps no fact of its own.

| Part | Values |
| --- | --- |
| `State` (struct) | `phase`; `gates`; `run` (rises with every new run and is never reset, not even by `off`); `failures` (kept through `proving` and `live`); `report` (`unknown`, `nothing`, `item`); `playerPlaying`; `doubtSpent`; `pending` (ack ids, at most four); `nextID`; `lastPingAt`; `token` |
| `Phase` | `off`; `held(Hold)` with `servicesStopped`, `sessionInactive`, `asleep`, `locked`, `pinned`; `starting`; `proving(Proof)` with `waiting`, `canary`; `live`; `backingOff`; `unavailable(Reason)` with `systemTooOld`, `interpreterMissing`, `helperInvalid`, `symbolsMissing`, `routeClosed`, `keepsFailing` |
| `Gates` (option set) | `switchOn`, `services`, `sessionActive`, `awake`, `unlocked`, `anyPlayer`. The first state has `sessionActive`, `awake` and `unlocked` set |
| `Event` | `settingChanged(on:)`, `followChanged(any:)`, `servicesStarted`, `willSleep`, `didWake`, `screenLocked`, `screenUnlocked`, `sessionResigned`, `sessionActive`, `quit`, `checkAgain`, `musicPageOpened`, `preflight(run, PreflightVerdict, token)`, `hello(run, version, missing, childIsVendor)`, `item(run, own:, token:)`, `nothing(run)`, `playerEvidence(playing:)`, `ack(run, id, ok)`, `pong(run, id)`, `deadline(run, Deadline)`, `exited(run, status)`, `badLine(run)`, `flood(run)`, `command(SystemSourceCommand)` |
| `Effect` | `sweepOrphans`, `preflight(run)`, `spawn(run)`, `stop(run)`, `arm(run, Deadline, seconds)`, `disarm(run)`, `publishCanary(token)`, `clearCanary`, `send(run, line)`, `dropEntry`, `publish(SystemSourceStatus)` |
| `Deadline` | `settle` 2 s, `hello` 5 s, `read` 3 s, `canaryRead` 1 s, `canary` 3 s, `doubt` 5 s, `ack(id)` 2 s, `pong(id)` 2 s, `backoff`, `stable` 300 s |

| Rule | When | Then |
| --- | --- | --- |
| 1 | Every gate holds | A run starts: `run += 1`, `sweepOrphans`, `preflight(run)`, phase `starting`. A missing gate gives `held` (the first missing one, in the order of the table) with `stop`, `clearCanary`, `dropEntry` and nothing else |
| 2 | Preflight not passed | `unavailable` with `systemTooOld`, `interpreterMissing` or `helperInvalid`. No spawn |
| 3 | Preflight passed | Keep the token, `spawn(run)`, `arm(hello, 5)`. A `hello` with version 1, nothing missing and a vendor child gives `proving(waiting)`, one `read` and `arm(read, 3)`. Anything missing gives `stop`, `unavailable(symbolsMissing)`; a child that is not the vendor's gives `stop`, `unavailable(interpreterMissing)` |
| 4 | `proving` | An item that is not Zeus's own gives `live` and `arm(stable, 300)`. `nothing` with no player playing starts the canary: `publishCanary(token)`, `arm(canaryRead, 1)` (one more `read`, so the proof does not wait on change notifications) and `arm(canary, 3)`. Zeus's own item carrying the token gives `clearCanary` and `live`. The `canary` deadline gives `clearCanary`, `stop`, `unavailable(routeClosed)`. Nothing else gives `routeClosed` |
| 5 | Doubt, in `proving` or `live`: `nothing` while `playerPlaying` | `arm(doubt, 5)`, once per player session (`doubtSpent`, cleared when the player stops or an item arrives). Still nothing at the deadline: the canary of rule 4, in the same run. It passes when the player plays on another device and fails when the route is closed |
| 6 | A failure: an `exited` Zeus did not ask for, a `hello`, `read`, `ack` or `pong` deadline, or rule 7 | `stop`, `dropEntry`, `failures += 1`, `backingOff` for 1, 2, 4 then 8 s, then a new run from preflight. The fifth failure gives `unavailable(keepsFailing)`. Only `stable` (300 s in `live`), a gate coming back, a switch cycle and `checkAgain` set `failures` to 0; reaching `proving` or `live` does not |
| 7 | Twenty undecodable lines in a row, or more than 20 lines a second for 5 s | A failure |
| 8 | Sleep, lock, session | `willSleep`, `screenLocked` and `sessionResigned` clear their gate (rule 1 holds the feature). `screenUnlocked` and `sessionActive` set theirs. `didWake` sets its gate after `settle`, so a lock notice that follows the wake lands first. When the last gate returns: a new run, also from `unavailable`. So the test runs at unlock |
| 9 | A pin | Clears `anyPlayer`: `held(pinned)`. Back to `Any player`: a new run |
| 10 | `musicPageOpened` in `live` | One `ping` with `arm(pong, 2)` when `now - lastPingAt` is 30 s or more. Nothing checks at idle |
| 11 | `command` | Only in `live` and with fewer than four ids in `pending`: `send`, the id joins `pending`, `arm(ack(id), 2)`. An `ack` removes its id. A fifth unanswered command is dropped |
| 12 | Switch off or quit, from any phase | `stop`, `clearCanary`, `dropEntry`, `off`. `run` is kept, so a late line from before a switch cycle never matches a later run. `checkAgain` acts only in `unavailable`: a new run |
| 13 | An event carrying a run other than `state.run` | Changes nothing |

`SystemSourceStatus.text(for:)` gives the word and symbol of the status row: "Off" `circle`, "Checking"
`arrow.triangle.2.circlepath`, "Ready" `checkmark.circle`, "Pinned" `pin`, "Restarting" `arrow.clockwise`,
"Unavailable" `exclamationmark.triangle`. The other holds read "Checking"; none of them can be on screen.
`reasonCode` gives `R1` to `R6` for diagnostics.

New file `Sources/ZeusCore/TopBar/SystemSourceWire.swift`. One JSON object per line, both ways, version 1:

| Line | Direction | Fields |
| --- | --- | --- |
| `hello` | helper to app | `v`, `missing` (count) |
| `item` | helper to app | `seq`, `app`, `parent`, `title`, `artist`, `album`, `duration`, `elapsed`, `at`, `rate`, `playing`, `key` |
| `none` | helper to app | `seq` |
| `art` | helper to app | `key`, `jpeg` (base64) |
| `ack` | helper to app | `id`, `ok`, `why` (`stale`, `failed`) |
| `pong` | helper to app | `id` |
| `read`, `ping` | app to helper | `id` |
| `cmd` | app to helper | `id`, `name` (`play`, `pause`, `next`, `previous`, `seek`), `seconds`, `app` (the bundle id expected) |

- Every line also carries `t`, the line's name from the first column.
- `SystemSourceLine.decode(_ line: Data)`: at most 1 MB a line; unknown `t` or a wrong type is `nil` (a bad line);
  numbers must be finite; `duration` missing or infinite is 0; negative values are 0.
- `SystemSourceText.clean(_:)`: at most 300 characters, control characters and direction-override scalars removed,
  line breaks to spaces. Bundle ids must match letters, digits, dot and hyphen, at most 155 characters, or the item
  is dropped. An item without a title is dropped.
- `SystemSourceCommand.line(id:)` encodes a command. End of input on the pipe is the quit signal; there is no quit
  line.

New file `Sources/ZeusCore/TopBar/SystemSourceLaunch.swift`:

| Rule | Result |
| --- | --- |
| `interpreter`, `program` | The constant `/usr/bin/perl`, and a constant program: it boots the built-in loader, loads the library named by its first argument, finds one entry symbol, binds it and calls it. The program text never contains a path |
| `arguments(libraryPath:)`, `environment` | `-f`, `-e`, the program, `--`, the path. The interpreter still reads switches after the program text (run here: a trailing `-x` was taken as a switch, and passed through after `--`). The environment is empty and the working directory is `/` |
| `isVendorInterpreter(path:)`, `minimumSystem` | True for `/usr/bin/perl` and for `/usr/bin/perl5.` followed by digits only. The floor is the lowest release on which step zero passed |
| `PreflightVerdict.decide(system:interpreterOK:libraryInsideBundle:libraryIsRegularFile:library:)` | Passes only on a supported release, when the interpreter is the vendor's signed program, the resolved library path stays inside the resolved app bundle, and `library` (the existing `CodeSignature`, `Sources/ZeusCore/PeerBinaryRule.swift:5`) is valid and meets the same identity requirement as the running app (`satisfiesIdentityRequirement`, `:19`; `PeerRequirement.text`, `:49`). An ad hoc build has no such requirement and never passes |
| `isOrphan(executable:arguments:parentPID:uid:ownLibraryPath:ownUID:)` | `executable` is the process's real image path, not its first argument. True only for a vendor interpreter path, parent 1, the same user, and a last argument equal to this bundle's own library path |

Fail closed: every unknown, late or malformed input moves toward `unavailable`, never toward `live`. A stale run is
ignored. `unavailable` shows nothing, sends nothing and starts nothing by itself.

### Tests first

- `Tests/ZeusCoreTests/SystemSourceMachineTests.swift`: nothing spawns with the switch off, under a pin, asleep,
  locked, with the session inactive or before services start; preflight failure never spawns; a missing symbol or
  a child that is not the vendor's never reaches `proving`; an unanswered first `read` is a failure, not an endless
  "Checking"; a real item proves; a canary proves and is cleared; a canary timeout clears and ends in
  `routeClosed`; a doubt publishes no canary before its deadline and never gives `unavailable` by itself; a player
  playing on another device (doubt, then the canary read back) stays `live`, in `proving` and in `live`; one doubt
  per player session; the back-off steps 1, 2, 4, 8 and the fifth-failure stop; `failures` survives `live` and is
  reset by `stable`; a lock clears the canary and stops the helper; no canary and no spawn between wake and
  unlock; unlock re-tests from `unavailable`; a lock inside the `settle` window starts nothing; the ping is rate
  limited by `now`; a command outside `live` sends nothing; five commands keep four and an `ack` frees a place;
  off from every phase gives `stop`, `clearCanary`, `dropEntry` first; a line of run 1 arriving after a switch
  cycle changes nothing; every status word has a symbol and none has U+2014 or U+2013.
- `Tests/ZeusCoreTests/SystemSourceWireTests.swift`: every line shape; a line over 1 MB; bad JSON; non-finite and
  negative numbers; infinite duration; text capped and cleaned (a right-to-left override, a line break); a bad
  bundle id; a missing title; command encoding for all five names.
- `Tests/ZeusCoreTests/SystemSourceLaunchTests.swift`: the argument list, with `--` before the path; the program
  text has no interpolation point and no path; an empty environment; every preflight refusal, a release below the
  floor among them; orphan matching (a `/usr/bin/perl5.30` image path matches; another user's process, a different
  library path, a live parent, another interpreter and `/usr/bin/perl5.30x` are all left alone).

## P1c. The helper library

### Behaviour

A new Objective-C target `ZeusNowPlayingHelper` (the tree already has one, `ZeusObjCGuard`, `Package.swift:25`),
built as a dynamic library product, depending on Foundation and ImageIO only. Objective-C keeps it small, keeps the
Swift runtime and ZeusCore out of the interpreter process, and gives a plain C entry point.

- The entry takes the two pointer arguments the interpreter passes and ignores them. It never returns to the
  interpreter: it runs until end of input, a signal or a fatal error, then exits the process itself.
- First it opens the private framework by its fixed system path with `dlopen` and resolves every name in one table
  with `dlsym`, in the shape of `Sources/Zeus/Intent/FastActions.swift:478-479`. Any miss: it writes `hello` with the
  count and exits. Nothing is called through a pointer that was not checked.
- Then it writes `hello`, registers for changes (or polls, if step zero item 4 says so), and writes an `item` or
  `none` on each change, coalesced over 100 ms. A `read` forces one. Artwork goes in its own `art` line, once per
  `key`, so text never waits for a picture.
- Artwork: only bytes under 8 MB that begin as JPEG or PNG (plus any format step zero item 11 adds) are decoded,
  scaled to at most 512 pixels and re-encoded as JPEG under 512 KB; anything else is skipped. The app never parses
  picture bytes that another app supplied. This is crash isolation, not a sandbox: the helper is resident and runs
  as the same user.
- A `cmd` re-reads the playing app's bundle id immediately before sending. If it differs from `app`, the command is
  not sent and the `ack` says `stale`. Seek clamps inside the duration.
- A reader on its own thread watches standard input; end of input exits at once, even if the main thread is stuck.
  A broken output pipe ends the process by default. So a helper never outlives Zeus by more than a moment.
- Nothing is written to standard error but fixed codes. No metadata ever goes there.

The header also declares three functions with no system call in them, so they can be tested: `ZNPEncodeItem`,
`ZNPDecodeCommand` and `ZNPScaleArtwork`. Target size: under 400 lines.

Fail closed: a symbol miss, an unreadable answer, an encoding failure or a command it cannot parse never produces an
`item`; at worst it produces `none`, a failed `ack` or an exit, and the reducer in P1b takes it from there.

### Tests first

`Tests/ZeusAppTests/SystemSourceHelperTests.swift` (the test target gains the dependency, `Package.swift:45`), with
synthetic dictionaries and a generated image only: an encoded item matches the literal line in the wire table; text
with a line break stays one line; a command line parses and a malformed one does not; a large generated image comes
back as JPEG within both limits; non-image bytes and a format outside the list give nil. The tests never call the
entry point, never start the interpreter and never touch the live service (lint, P1d). P1c adds the suite's
native-fixture row to `qa/feature-map.json` itself, since it merges before P1e.

## P1d. Packaging, identity and lints

### Behaviour

| File | Change |
| --- | --- |
| `scripts/bundle.sh`, `scripts/verify-release-signature.sh` | Build the library product by name, create `Contents/Frameworks`, copy the library there, strip it with the others, and sign it with the hardened runtime and the same identity before the app is signed. Today the strip loop (`:66-68`), the signing loop (`:71-73`) and the release check (`verify-release-signature.sh:6`) cover `Contents/Helpers` only; each gains the library explicitly. Bundling stops with a clear message when the library product is missing. The library stays out of `Contents/Helpers`, because peer identity reads that folder's signing identifiers to recognise Zeus's own programs (`Sources/ZeusCore/PeerSigning.swift:34`) |
| `qa/release-scripts/test_release_scripts.py` | It runs the real `bundle.sh` and `verify-release-signature.sh` against a mock `swift` whose output holds four executables (`:115-118`), so the release-scripts CI job (`.github/workflows/build.yml:34-44`) would break on the new copy. Its mock output and app fixture (`:88`) gain the library, and its mock `codesign` gains a state for one file |
| `Sources/ZeusCore/PeerSigning.swift` | Three public functions, each with a stub that always refuses in the non-Darwin half of the file (`:184-187`). `bundledLibrarySignature(path:)` is new code, not reuse: a static validity check of the file with the running app's own requirement compiled, under the strict, all-architectures and nested-code flags. It returns the existing `CodeSignature` with `satisfiesIdentityRequirement` set, or nil. `interpreterIsVendor(path:)` checks the launch file against the vendor's anchor. `childIsVendor(pid:)` checks the running child's image the same way after `hello`, which covers a release where the launch path re-executes another copy |
| `Sources/ZeusCore/Compliance/AtticusCleanRoom.swift` | The owner's approval of this private route is recorded in its comment, naming no product; the `docs/STATE-MACHINES.md` entry that P1b writes carries the same note. The forbidden-token list (`:6-13`) is unchanged; it does not cover this framework, and its scan reads `.swift` files only (`:47`) |

### Lints (`qa/closed-loop/tests/test_source_lint.py`), each with a fail-first sample as at `:157`

- The private framework's name and its symbol prefix appear under `Sources/` only in `Sources/ZeusNowPlayingHelper/`.
- `/usr/bin/perl` appears only in `ZeusCore/TopBar/SystemSourceLaunch.swift`.
- `SystemSourceChild(` is constructed only in `TopBar/SystemNowPlayingFeed.swift`; `systemCommand` is assigned only
  there; `Zeus/Intent/**`, `Zeus/Voice/**`, `ZeusCore/ZeusTag.swift` and `ZeusCore/BrowserCommand.swift` never
  mention `systemCommand` or `SystemSourceCommand`.
- `MPNowPlayingInfoCenter` appears only in `TopBar/SystemSourceCanary.swift`.
- `Tests/` never names the helper's entry symbol, the interpreter path, or the canary type.

### Tests first

`Tests/ZeusCoreTests/BundledLibraryRuleTests.swift`, on the three new functions only (requirement text is already
covered by `PeerBinaryRuleTests`; path and link refusals are P1b's): a missing file, an unsigned temporary file and
a file that is not code each give nil; a temporary copy of a text file is not the vendor's interpreter; pid 0 and
a pid that is not running are not the vendor's. `test_release_scripts.py` gains: bundling passes with the library
in the mock output and fails with a message without it; the release check fails when only the library lacks
Developer ID, a time stamp or the runtime flag. The Security call on a real signed library is an owner check.

## P1e. The feed

### Behaviour

- `SystemSourceChild` (an actor, in the shape of `Sources/Zeus/Voice/KokoroWorkerSession.swift:10`, pipes through
  `MCPPipeIO`, `Sources/Zeus/BrowserAgent/MCPPipeIO.swift:10`): starts the interpreter off the main actor with the
  arguments, empty environment and working directory from `SystemSourceLaunch`, standard error to the null device,
  and all its own pipe ends close-on-exec. It reads lines with the 1 MB cap and hands each decoded value, with the
  run token, to the feed. `stop` is this plan's own ladder: close the input pipe (the helper exits on end of
  input), `SIGTERM` after 0.5 s, `SIGKILL` after 2 s, each wait an awaited sleep off the main actor in the shape of
  `finishChild` (`KokoroWorkerSession.swift:389-407`, which itself terminates at once and kills after about 0.25 s).
- With each `hello` the child hands the feed `PeerSigning.childIsVendor(pid:)` for the process it still holds.
- The orphan sweep lists processes with public calls, reads each real image path (`proc_pidpath`, as
  `Sources/ZeusCore/Insomnia/InsomniaRestore.swift:189`), applies `isOrphan`, and sends `SIGTERM` to matches only.
- `SystemSourceCanary`: sets one entry through the public MediaPlayer interface (title "Zeus", the token in the
  album field, playing), and clears it. It runs only on the reducer's effect.
- `SystemNowPlayingFeed` (main actor): holds one machine state, applies effects, owns every deadline as a task that
  carries its run token, and feeds the hub. It observes the switch, the follow setting, sleep and wake
  (`queue: .main` with `MainActor.assumeIsolated`, as `Sources/Zeus/TopBar/TopBarServices.swift:115-127`), screen
  lock, unlock and the session pair (as `Sources/Zeus/Voice/WakeWordController.swift:62-69`), the Music page
  through the hub's `observeMusicPage`, and player evidence from the hub's Music and Spotify entries.
- Every helper report replaces the system slot (the rule below), so the arbiter never holds two system entries.
- `applicationWillTerminate` (`Sources/Zeus/App/AppDelegate.swift:88`) sends `quit`. Started from one line in
  `TopBarServices.start` (`:44`), so it never runs in a start mode without top bar services (`AppDelegate.swift:136`).

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/SystemSourceRules.swift`:

| Rule | Result |
| --- | --- |
| `verdict(item:ownBundleID:browserFeedActive:)` | `own` (the app or its parent is `app.zeus.mac`, `Resources/Info.plist:8`; used as proof only, never shown), `callApp` (a native call app, by bundle id), `shadowedByPlayer` (Music or Spotify, by `NowPlaying.Player.init(bundleID:)`, `NowPlaying.swift:17`), `shadowedByBrowser`, `show` |
| `nowPlaying(_:appName:receivedAt:)` | Maps a shown item to an A1 value. The position anchors at the service's own time stamp when it lies within the last day and not in the future, else at receive time. Rate 0 is paused |
| `forward(previous:next:lastIdentityChange:now:)` | Position-only updates pass; a change of app, title or artist passes at most once a second, so a program that rewrites its entry in a loop cannot make the notch flicker |
| `slot(verdict:key:current:)` | `clear` for `none` and for every verdict but `show`; `replace` when the shown key differs from the entry's; `update` otherwise. The feed runs `clear` and `replace` as `remove(where: \.isSystem)` first, so a change of app (one browser, then a video app) or a call app taking over leaves no stale entry |
| `command(for:item:seconds:)` | `MusicCommandKind` to a wire command. `playPause` becomes `pause` when the shown item's rate is above 0, otherwise `play` (the wire has no toggle). Nil for shuffle, repeat or a stale key |

Fail closed: a rejected, shadowed, own or call item never becomes an entry and removes the one shown. A command is
sent only for the entry that is shown and only in `live`. On any effect failure (a spawn error, a pipe error) the
feed reports `exited`.

### Tests first

- `Tests/ZeusCoreTests/SystemSourceRulesTests.swift`: every verdict; a parent bundle id wins over a helper's own;
  mapping with a stale, future and missing time stamp; rate 0, 1 and 2; live content has no seek; the forward rule
  under a burst; every slot change; command mapping, with `playPause` on a playing and on a paused item.
- `Tests/ZeusAppTests/SystemNowPlayingFeedTests.swift` (`@MainActor`, serialized, a fake child, a fake canary, a
  recording hub): switch on with a passing fake reaches `live` and one entry; a second app's item leaves exactly
  one system entry; a call-app item and a `none` remove the shown entry; switch off removes the entry and stops
  the child; a failing preflight never constructs a child; a canary is cleared on every path, a lock among them; a
  line from an old run is ignored; a pin stops the child; `quit` stops it. P1e adds its native-fixture row to
  `qa/feature-map.json`.

## P1f. Settings

| Id | Where | Control | Default | Ticket |
| --- | --- | --- | --- | --- |
| `music.systemSource` | Privacy, Music card (`Sources/Zeus/Settings/GlanceSettingsPages.swift:1142`) | Toggle: "Show what any app is playing" | Off, opt in, never enabled by import | P1f |
| `music.systemSourceStatus` | The same row's trailing edge | Status: a word with its symbol; "Check again" only when Unavailable | n/a | P1f |

| Part | Rule |
| --- | --- |
| Design | One row. The title says what the switch does, so there is no note, tagline or second label. The status is a word with a symbol, never colour alone. The button is drawn only when it can do something. No new motion, so nothing to do for Reduce Motion. No new window, so `ZeusWindowSharing` is untouched. The card is already placed on a page (`test_source_lint.py:313`) |
| The row view | Built in the page, with no change to `GlanceSettingsStyle.swift`: `GSToggleRow` holds only a switch in its trailing slot (`:116-126`), but `GSRow` takes any trailing view (`:81`), here the status label, the button when Unavailable, and a switch in `GSToggleStyle` |
| VoiceOver | The switch is one element, labelled with the title, whose value is the switch value and the status word ("On, Ready"). "Check again" is a separate element, present only when the status is Unavailable |
| "Check again" | Calls `store.actions["music.systemSource.check"]`, as the button at `GlanceSettingsPages.swift:1149` calls its action. P1e sets that action in `AppDelegate`; it sends `checkAgain` to the feed. `wireSettingsCatalog` (`AppDelegate.swift:882`) is P1e's too: the switch reaches the feed as `settingChanged` |
| Generator and store | The generator row carries the mechanism in its inventory note (not shown in the app): "Reads the system now-playing service through the system Perl interpreter. Off removes the helper." It joins `opt_in`. `SettingsStore.neverEnabledByImport` gains `music.systemSource`. `SettingStatus.value` (`SettingsStore.swift:438`) gains the status case, with a fixed snapshot value |
| Diagnostics | `LiveDiagnostics` (`Sources/ZeusCore/Diagnostics/LiveDiagnostics.swift:26`, `:129`) gains one row, "System source", with the status word and reason code. Never a title or bundle id. The existing "Now playing" row takes the source's name (`:65-70`, `:129-136`), which after A1 would be the playing app's name, and its summary is copied to the clipboard: for a system item it says "Another app" |

Tests first: `SettingsConsumerTests` gains: the option exists, is a toggle and defaults to off; an import file with
the value "true" leaves it off, and one with "false" turns it off. `LiveDiagnosticsTests` gains the new row for each
state, and a system item whose row and summary hold "Another app" and not the app's name. The generator check
(`scripts/check-settings-catalog.sh`) passes; generated files are never hand-edited.

## Security: how it could be abused, and how each way is closed

| Abuse | Closed by |
| --- | --- |
| Another program swaps the library, or points Zeus at its own | The path is computed from the running bundle, must resolve inside it, and must carry a valid signature meeting Zeus's own identity requirement, checked before every spawn. A remaining gap between check and load needs write access to the app bundle, which already means Zeus itself can be replaced |
| Code injected into the interpreter through its environment or module path | Empty environment, `-f`, working directory `/`, and no module file read at all: the loader is booted from inside the interpreter (verified here). No `PATH` lookup: one absolute interpreter path, itself checked against the vendor's signature |
| A user-writable preference makes the launch path run another interpreter copy | The running child's own image is checked against the vendor's anchor after `hello`; anything else is stopped and reads "Unavailable". The sweep matches the real image path |
| A crafted app location (quotes, spaces, a leading hyphen) breaking the launch program | The program is a constant; the path travels as an argument after `--`, never inside program text |
| Someone at the lock screen, or another user at the console, sees or drives a Zeus entry | The helper is stopped and the canary is never published while locked, asleep or with the session inactive |
| Another program writes commands to the helper or reads its output | Private pipes created by Zeus, close-on-exec. Nothing listens on a socket, a port or a named pipe |
| Another program kills or stalls the helper again and again | Back-off, five exits end in "Unavailable", ping and ack deadlines. Never a spawn storm |
| The sweep kills someone else's process | It matches only the system interpreter, parent 1, the same user and Zeus's own library path as the last argument |
| Hostile metadata from any app (any app may publish an entry) | Length caps, control and direction-override characters removed, bundle id pattern, finite numbers only, JSON framing so a line break cannot forge a line, a 1 MB line cap |
| A hostile picture | Only JPEG and PNG under the size limit are decoded, in the helper, and the app receives only a JPEG the helper produced. A decoder flaw would crash the helper, not Zeus, but its code would still run unsandboxed as the same user: the boundary is crash isolation and a short format list, no more |
| Another app's titles sent to the lyrics service, or its name copied out with diagnostics | A system item has no `lyrics` capability; the diagnostics row says "Another app" |
| A program rewriting its entry in a loop | 100 ms coalescing in the helper, the flood rule in the reducer, one identity change a second in the feed |
| Metadata used to make Zeus fetch a URL or launch an app | No URL is accepted from this source. Open only activates a running app |
| A tap landing on a different app than the one shown | The command names the expected bundle id; the helper re-reads and refuses on a mismatch |
| A network peer streaming to this Mac sets the title Zeus shows | The same text rules; it is display data only; a command reaches that stream only on the owner's tap |
| A model, voice turn or imported settings file turning the feature on or driving playback | Never enabled by import; no command path from intents or voice (lint) |
| Titles leaking to disk, logs or a shared screen | Memory only; logs carry codes; Zeus surfaces stay out of capture unless the owner chose otherwise |

## Repo hazards that apply

- Swift 6: pipe readers and the termination handler are not main-actor code; the child lives in an actor and only
  Sendable values cross. Workspace observers keep `queue: .main` plus `MainActor.assumeIsolated`.
- No blocking waits (`test_source_lint.py:267`): no `waitUntilExit` on the main actor, no semaphore, no polling
  loop. `SpotifyPlayer.osascript` polls with `usleep` in a detached task
  (`Sources/Zeus/Intent/SpotifyPlayer.swift:98-110`); that shape is not copied here.
- Lightness: with the switch off no helper may run, in the spirit of `PerformanceBudget.forbiddenDefaultProcesses`
  (`Sources/ZeusCore/Performance/PerformanceBudget.swift:10`). With it on and nothing playing: one idle child,
  inside the 1 percent and 150 MB idle budget (`:5-6`) for the two processes together. "No timer" holds only if
  step zero item 4 finds change notifications; otherwise the child polls and its CPU is measured in that mode.
  `scripts/check-perf-budget.sh` samples one pid (`:9-15`), so the child is sampled in a second run.
- Bundle: the size budget (`scripts/check-bundle-size.sh`) is not at risk from a library this small. `codesign
  --verify --deep --strict` (`scripts/bundle.sh:76`) sees the new nested code.
- Whether plain `swift build` emits the dynamic library product next to the executables is unverified; `bundle.sh`
  builds it by product name.
- A build signed with the local development identity (`scripts/bundle.sh:23`) passes the preflight but may get an
  empty answer from the service. That is the fail-closed path, shown as "Unavailable", not a bug.
- The em dash lint (`test_source_lint.py:126-131`) reads `Sources/Zeus` only (`:14`, `:46-47`) and looks for
  U+2014 only. It covers the settings strings; the status words live in ZeusCore and are covered, for both dashes,
  only by P1b's own test. Settings generator and REG ids: above. Agent sandboxes have not compiled Swift
  (TYPE-012): budget a Mac build for every ticket.
- `docs/STATE-MACHINES.md` gains the system source, explicit from the start, with its states and tests. The
  highest entry today is 23 (`:17`), so this is 24 unless another plan of this wave merges an entry first.

## Out of scope

- Shuffle and repeat through this route, including a repeat-one for Spotify.
- Feeding Music's position from the system source (it would replace A2's probe while the switch is on).
- A per-app choice in `music.follow`. A cue in the notch when the route closes.
- Asking the service which commands an app supports, to hide Next and Previous for apps that ignore them.
- A second interpreter as a fallback. The lock screen. Any use of this source outside the notch and Home.

## Decisions the owner owes

These are inputs and trade-offs, not verdicts. The writer is not a lawyer; licence points go to counsel if they matter.

| # | Decision | The plan assumes | The other choice |
| --- | --- | --- | --- |
| 1 | Step zero | Go or stop on its recorded results. Needs the owner at the Mac and a release-style signing run | None |
| 2 | The canary | Kept: a definite answer at once, at the price of a "Zeus" entry in the system's own now-playing display for up to 3 s when nothing plays here (never on the lock screen), and once when a player app starts playing on another device | Without it, "Checking" lasts until something plays, a doubt must end in "Unavailable" by itself, and playback on a phone or a speaker then reads as a closed route |
| 3 | Lyrics for system items | Never | The capability behind its own switch, off by default and never enabled by import, because it sends the title of anything that plays to the lyrics service |
| 4 | The A1 contract change (a third source case) | P1a, after A1 | Fold it into A1 before A1 starts |
| 5 | Music and Spotify | They keep their own feeds, so their controls still need Automation consent | This route drives them without that consent, which changes what the consent means |
| 6 | The record of approval | Written in the clean-room comment and the state machine register | None |
| 7 | Bundling the BSD-3-Clause prior art | Not bundled | Only if step zero shows an own helper cannot work. It brings the duty to keep its copyright notice and licence text in `NOTICES.md`, `Resources/NOTICES.txt` and About |
| 8 | A call in a browser tab | The gap is accepted: such a call can be shown, paused by dictation and sent a command, like any browser media | Drop every browser system item while Scribe's call watcher reports a call. That needs one read-only accessor in `Sources/Zeus/Scribe/ScribeCallWatcher.swift` (added to P1e) and works only while that watcher runs, which is never at launch (`:207-208`); this feature would not start it |
| 9 | The feature's floor | "Unavailable" below the lowest release tested in step zero. The package runs from macOS 14.2 and every interpreter fact here was checked on 27.2 only | A 14.x and a 15.x Mac join step zero |

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the ticket's new names).
2. `swift build --build-tests`, then `swift test --filter` for `SystemSourceMachineTests`, `SystemSourceWireTests`,
   `SystemSourceLaunchTests`, `SystemSourceRulesTests`, `BundledLibraryRuleTests`, `SystemSourceHelperTests`,
   `SystemNowPlayingFeedTests`, and the pinned `NowPlayingSourceTests`, `NowPlayingArbiterTests`,
   `NowPlayingHubTests`, `SettingsConsumerTests`, `LiveDiagnosticsTests`.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared (known failures recounted after the
   earlier waves merge). `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_*.py'`.
   `python3 qa/release-scripts/test_release_scripts.py` (P1d). The settings generator and its check.
   `./tools/check.sh` development mode from a worktree under `<models-dir>`.
4. A real compile on a Mac before any ticket is called done. An independent review of each diff, reading the
   reducer transitions, the launch arguments, the preflight and the helper's symbol table line by line.
5. Still owed on a real Mac, by the owner, in a release-signed build. P1b closes none alone: its rules are seen
   through P1e.

| Check at the Mac | Closes |
| --- | --- |
| Step zero, items 1 to 11, before the wave; then the same facts again in the real build | P1c |
| Switch off: no interpreter child of Zeus in the process list, after launch and after an hour | P1e |
| Switch on with nothing playing: "Checking", then "Ready"; the canary entry is gone within 3 s | P1e |
| A desktop player with no scripting feed, a second browser and a video app each show title, artist, artwork and a moving position; play, pause, next, previous and seek act on that app and on no other. Moving from one to the next leaves one item, never a stale paused one. The main button pauses a playing item and plays a paused one | P1e |
| Music and Spotify look and act exactly as before, with the switch on and off. A pin shows only its player. With lyrics on, a video in a browser shows no lyrics and makes no request to the lyrics service | P1a |
| Spotify playing on a phone, and Music playing to a network speaker: the status stays "Ready" | P1e |
| Lock the screen: no interpreter child while locked. Wake to the lock screen with nothing playing: no "Zeus" entry in the system's now-playing display. Unlock: "Checking", then "Ready". The same across a user switch | P1e |
| Dictation pauses the shown app and resumes that app only. Sleep and wake mid-song. A long title, a right-to-left title, a missing artist, artwork that arrives late | P1e |
| A call in a native call app is never shown or paused. A call in a browser tab and private-window media: what appears is recorded against owner decision 8 | P1e |
| Force quit Zeus: the helper is gone within a second. Kill the helper: the item returns after the back-off. A command for an app that just lost the election is refused | P1c |
| VoiceOver on the status row (the switch reads its status; "Check again" is its own element) and on the notch source line. Reduce Motion on. A shared screen with the default capture setting shows no title. An imported settings file cannot turn the switch on. Diagnostics copied while another app plays say "Another app" | P1f |
| A build with the library removed, and one with an ad hoc library: "Unavailable", nothing shown, no child. `codesign -dv --verbose=2` on the library inside the built app: same team, hardened runtime, time stamp. On each older Mac of step zero item 10: the status word, the child's image path, the helper leaving with Zeus | P1d |
| `<pid>` is `the Zeus process id`. `PID="<pid>" SECONDS_IDLE=60 scripts/check-perf-budget.sh` with the switch on and nothing playing, run once for Zeus and once for the interpreter child; the two CPU figures and the two memory figures, added, stay inside the budget. Repeated in polling mode if step zero item 4 requires it | P1e |

## Review notes

All 21 review findings were checked against the code and the study; 20 were accepted, in full or in part. Main
changes: `State` is a struct that holds every fact a rule reads (gates, a run counter that is never reset, the
failure count, the last report, pending ids, the last ping), with `now` and the token handed in; a deadline on the
first read; a back-off of 1, 2, 4, 8 s that the fifth failure can reach; lock, unlock and session events, so the
test runs at unlock and nothing runs on the lock screen; one system slot, replaced by every report; no `lyrics`
capability; the call claim narrowed to native call apps; a feature floor and a check of the running child's image;
`--` before the path; `playPause` mapped; "Another app" in diagnostics; the release-scripts test and the
feature-map rows given owners; the corrected citations; the idle and budget claims tied to step zero.

Narrowed or rejected:

- Playback on another device. Neither offered fix was taken as written: no field that tells local from remote was
  found, and "re-test only" still read "Unavailable" at the first proof. Instead a doubt never decides; it runs
  the canary once, and only a failed canary closes the route.
- ZeusCoreTests suites need no row in `qa/feature-map.json`: the module is bound whole (`:398-402`). Only the two
  ZeusAppTests suites got rows.
- "P1d after P1b" was not adopted. The new function returns the existing `CodeSignature`, so P1d uses no P1b
  type; the path and link cases stay in P1b's tests.
- No new row view and no change to `GlanceSettingsStyle.swift`: `GSRow` already takes any trailing view.
- The state machine register does not stop at 22: entry 23 exists (`docs/STATE-MACHINES.md:17`), so 24 is next.
- The open-source notch project stays in "Open source checked first". It is open source, not commercial, the
  sources plan lists it in the same section (`docs/NOTCH-SOURCES-PLAN.md:35`), and the row records that no GPL
  code was read.
- The design still departs from the study's contract on purpose (an own library, one resident child, a pipe each
  way). Not verified in this session: anything that needs the service to answer, the symbol names beyond the two
  the study resolved, the command numbers on device, older releases, and how `swift build` emits the library.
