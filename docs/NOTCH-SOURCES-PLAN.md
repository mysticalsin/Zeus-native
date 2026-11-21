# Notch now-playing sources: plan and design

Written 13 November 2026 against `codex/island-20261113` (HEAD `47566d1`). Third wave after `docs/NOTCH-MUSIC-PLAN.md`
and `docs/NOTCH-SURFACE-PLAN.md`. Both are assumed merged before this is built: `TopBarModel.musicModes` and the two
mode cases on `MusicCommand` (M1), lyric matching (M2), word lighting (M3), the display hold while music plays (M4),
open on click (S1), rounded corners (S2) and live diagnostics (S3). Nothing here redoes them. Same rules: pure rules in
ZeusCore with tests first, `docs/DESIGN-DIRECTION.md` for anything visible, nothing accepted until the named tests run
on macOS and the behaviour is seen on a Mac. Public interfaces only. Line numbers below were first read on `47566d1`
and read again on `3757de2`.

Refreshed 14 November 2026 on `codex/sources-20261114` (HEAD `3757de2`), before the build. Both earlier waves are
merged there, with fixes on top. Stale file and line references are corrected in place; what changed in the code and
what it means for each ticket is in "Addendum: the code on 14 November 2026". Five decisions were applied at the same
time: A2 is deferred; the build order is A1, then A4, then A3; this plan's regression ids come only from REG-450 to
REG-469; the system-wide source, planned in `docs/NOTCH-SYSTEM-SOURCE-PLAN.md`, adds a third source case after A1, so
the A1 model stays open to it without building it; and A3 adds its one accessor to `ScribeCallWatcher.swift` in the
smallest way, because that file is being rewritten on another branch.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| A1 | One source model | A closed two-case `Player` and hidden "not Music means Spotify" defaults | A source value with capabilities, one rule for what is shown, a setting to follow any source or pin a player |
| A2 (deferred) | Music position after a change | Music's notification has no position, so progress, lyrics and word lighting drift after a seek | The existing probe re-run, coalesced and bounded, once step zero shows when it is needed |
| A3 | Browser media | Not shown | Media in Chrome tabs, read and controlled through the Zeus extension and bridge |
| A4 | Source on screen | No source name; every control drawn for every player | The source is named, and controls a source cannot honour are not drawn |

Worktrees and order:

| Ticket | Files it owns | Runs |
| --- | --- | --- |
| A1 | `NowPlaying.swift`, `Artwork.swift`, `Lyrics.swift`, new `NowPlayingSource.swift`, new `NowPlayingArbiter.swift`, `ZeusCore/TopBar/MusicModes.swift` (`:87`), `TopBarServices.swift` (music block out), new `MusicPlayerFeed.swift`, new `NowPlayingHub.swift`, `ArtworkStore.swift`, `LyricsViews.swift`, `TopBarModel.swift`, `TopBarViews.swift` (`:118`, `:583`, the Music page appear hook), `FastActions.swift`, `DictationController.swift`, `GlanceSettingsPages.swift` (new Music group, the note at `:107`), the S3 call site (`ZeusCore/Diagnostics/LiveDiagnostics.swift:69`), new `Tests/ZeusAppTests/NowPlayingHubTests.swift`, `qa/feature-map.json` (one row per new app suite), generator row | First, alone |
| A2 | `MusicPlayerFeed.swift`, new `ZeusCore/TopBar/PositionReread.swift`, its tests | Deferred. Step zero needs a person at the Mac and nothing is scheduled until it has run; then after A1 |
| A3 | `extension/**`, `UnixSocket.swift`, `ChromeBridge.swift`, `ChromeInstaller.swift`, new `Chrome/BrowserMediaFeed.swift`, new `Chrome/ChromeOutputActivity.swift`, new `ZeusCore/TopBar/BrowserMedia.swift`, new `ZeusCore/TopBar/BrowserPollMachine.swift`, one accessor in `ScribeCallWatcher.swift` (one computed property, nothing else in that file), one line in `TopBarServices.start`, `SettingsStore.swift` (import list, `SettingStatus`), `GlanceSettingsPages.swift` (privacy row), `test_source_lint.py`, generator row | Third, after A4. `extension/**` depends on neither A1 nor A4, but it is built and merged with the rest of A3 |
| A4 | `TopBarViews.swift`, `HomeWidgetViews.swift`, `NowPlayingHub.swift` (cue only), `TopBarLayout.swift`, `SnapshotRenderer.swift` (new fixtures), new `ZeusCore/TopBar/NowPlayingDisplay.swift` | Second, after A1 |

Build order: A1, then A4, then A3, one at a time. A2 is deferred and is not in the order.

Only A1 edits routing in the hub; A3 and A4 call it. Every branch appends to `qa/regressions.json` (ids for this plan
come only from REG-450 to REG-469: A1 takes 450 to 455, A4 456 to 459, A3 460 to 467, and 468 and 469 are held for
A2 while it is deferred; REG-410 to REG-449 are held by other work and are never used here; with fixed blocks no clash
is expected, and if `<models-dir>/zeus-merge-reg.py` does rename an id it numbers from the top of the tree and can
land in another plan's block, so the id is put back inside this plan's block by hand; feature `F13`, as in
`qa/extension-regressions.json`) and the generated settings files (re-run the generator on the merged table; never
hand-merge `SettingsCatalog.swift` or the inventory).

## Open source checked first

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| One controller per source behind one model | TheBoredTeam/boring.notch | GPL-3.0 | Technique only. No code is read into Zeus |
| Which source counts as playing | servitola/nowplayingseek | AGPL-3.0 | Technique only: the most recent starter is elected and kept a while after a pause. Zeus's rule is its own |
| Bounded player reads | justinmdickey/goplaying | MIT | Technique only: a 3 s bound, the `is running` check before the tell, one read in flight |
| Media session read and native host plumbing | JosephusPaye/chrome-media-controller | MIT (stated on the repo page; read the file before any reuse) | Technique only: read media session metadata and the media element |
| Notification keys | rwijnen/cuecard | MIT | Already matched by `NowPlaying.parse`; nothing new |
| System-wide source | ungive/mediaremote-adapter | BSD-3-Clause | Not used in this plan. It needs a private framework; see "Out of scope" |
| Reading rules | Media Session spec, Chrome extension scripting docs | n/a | Only `metadata` and `playbackState` are readable; position comes from the media element; ISOLATED and MAIN worlds |

No code is copied and no dependency is added. GPL and AGPL projects were read for technique only.

## Privacy and consent

- No capture, no new OS permission, entitlement or manifest permission; nothing prompts. No test touches TCC (tests set
  `Automation.testStatusProvider`), a real Chrome (`node:vm`) or the network (a stub `URLProtocol`). The output gate
  reads Core Audio process flags, which never prompt and carry no audio, as `ScribeMicActivity.swift` does.
- A2 reuses Music's consent via `Automation.allowed` (`PermissionsModel.swift:343`): without it nothing runs, no hint.
- Browser media is off until the owner turns on `music.browserMedia` (in `SettingsStore.neverEnabledByImport`,
  `SettingsStore.swift:255-258`). It reads media metadata, playback state and the chosen element's numbers, never page
  text, and skips incognito and discarded tabs. The tab URL stays in memory only, never logged, stored or shown.
- Calls are never a source: a `MediaStream` element is not a candidate (A3), and while `ScribeCallWatcher` runs and
  reports a browser call, the feed drops browser entries and refuses browser commands.
- Browser media never reaches a model, voice, chat or agent context. Logs and diagnostics carry the kind ("Chrome"),
  codes and counts, never a host or title. `AudioSpectrumService.setMusicPlaying` (`TopBarModel.swift:131`) now
  follows browser playback too; it never asks. So does the display hold, through `onMusicPlaying` on the next line
  (`:132`), as A1 says below.
- Nothing from a browser item touches the disk: its cover (the page's own `https` link, ephemeral session, no cookies)
  bypasses `~/Library/Caches/Zeus/artwork`, and its lyrics (`privacy.lyrics` on, an artist, a duration) stay in memory.
- Control of a tab comes only from the owner: a tap on the notch, or "pause media while dictating"
  (`DictationController.swift:608-610`, resume `:1066-1069`). A tap does not touch `ChromeActions.allowedHosts`
  (`ChromeActions.swift:12`, `:164-173`), and no model or voice action can send `media.command` (lint, A3). Voice
  transport stays on the media keys (`FastActions.swift:337-350`).

## A1. Now-playing source abstraction

### Behaviour

- Zeus keeps one entry per source (Music, Spotify, each browser document) and shows one. The source that most
  recently started playing is shown. If none plays, the last one shown stays, paused, until another starts or its app
  quits. A source first seen paused never displaces the shown one. A track change is not a new start.
- Setting `music.follow`: "Show music from", `Any player` (default), `Music` or `Spotify`. A pin shows only that
  player, or nothing.
- Commands go to the shown source and are checked against its capabilities; one it cannot honour is ignored. With
  nothing shown, the target is the pinned player, else Music: Open launches or activates it (as today), Play reaches
  it only if it is running. Open on a browser item activates the running Chrome and never launches it.
- The track cue (`TopBarServices.swift:179-181`) fires as today, on the shown item. With one player, Music and Spotify
  behave exactly as today: same lyric asks, same artwork cache keys.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/NowPlayingSource.swift`:

- `BrowserMediaKey` (`tabID`, `documentID`, `host`, `fingerprint`; Hashable, Sendable). `NowPlayingSource`:
  `.player(NowPlaying.Player)`, `.browser(BrowserMediaKey)`, with `kindName` ("Music", "Spotify", "Chrome"),
  `appBundleID`, `baseCapabilities`, `artworkStrategy` (`spotifyOEmbed`, `catalogSearch`, `pageImage`, `none`),
  `scriptedPlayer` (nil for a browser) and `persistsDerivedData` (false for a browser: no disk cache at all).
- `SourceCapabilities` (OptionSet): `playPause`, `next`, `previous`, `seek`, `shuffle`, `repeatMode`, `lyrics`. Music
  has all. Spotify lacks `shuffle` and `repeatMode` until the check in item 6 passes (the research found its scripted
  modes may no longer act from outside). A browser has `playPause`, plus `seek` and `lyrics` per item.
  `allows(_ command: MusicCommandKind)`, a mirror of `MusicCommand` (M1's cases too) plus explicit `play` and `pause`.
- Open to a third case. `docs/NOTCH-SYSTEM-SOURCE-PLAN.md` adds `.system` after A1 (its ticket P1a); A1 builds none
  of it: no case, no key type, no command closure, no setting. So that P1a is one new case and not a second refactor,
  every fact that differs by kind is a property of `NowPlayingSource` in this file, code elsewhere reads the property
  and does not match on the cases, the few places that must match (the artwork key, the arbiter's tie order,
  `hasPlayerSession`) use a `switch` that names every case with no `default`, and nothing treats "not a player" as
  "a browser". The names that plan depends on (its lines 181 to 186) keep their spelling.

`NowPlaying` (`NowPlaying.swift:5-123`): `Player` (`:6`) gains `CaseIterable`. The stored `player` (`:34`) becomes
`source: NowPlayingSource`, so every read of `.player` fails to compile, which is how each hidden default is found;
`init(player:...)` stays, so the fixtures at `SnapshotRenderer.swift:589`, `:826`, `NotchDebugAnimator.swift:62` and the
tests still compile. New `rate = 1` (`elapsed(at:)`, `:113-116`, multiplies by it) and `artworkURL`. New
`capabilities`: the base set, minus `seek` when `duration == 0`; for a player `lyrics` holds exactly when
`LRCLIBQuery(self).isAskable` (`Lyrics.swift:111`), as today; a browser item also needs a duration. `parse` and
`parseProbe` keep their signatures; their ternaries (`:70`, `:76`, `:108`) become exhaustive switches.

New file `Sources/ZeusCore/TopBar/NowPlayingArbiter.swift`:

- `Follow`: `any`, `pinned(NowPlaying.Player)`; `init(label:)`, unknown is `any`. `Entry`: `playing`, `startedAt`,
  `seenAt`. `mutating update(_ source:, _ playing: NowPlaying?, now:) -> Bool`: nil removes; a `playing` whose
  `source` differs is rejected (false, no change); not playing to playing sets `startedAt = now`.
- `remove(where:)` (a quit, a closed tab, a feed off), `entry(_:)`, `hasPlayerSession` (a Music or Spotify entry).
- `shown(follow:)`: playing entries by latest `startedAt`, else all by latest `startedAt`, then `seenAt`; ties go
  Music, Spotify, then browser by tab id. `commandTarget(shown:follow:)`: shown, else the pinned player, else Music.

Every hidden two-player assumption, and its replacement:

| Where | Today | After |
| --- | --- | --- |
| `NowPlaying.swift:70`, `:76`, `:108` | `player == .music ?` and `== .spotify ?` | Exhaustive switches |
| `Artwork.swift:84` | Anything not Music keys as `spotify-` | Switch on `source`: `music-`, `spotify-` as today, `page-` plus a hash of the image URL |
| `TopBarViews.swift:118` | Not Spotify draws the note glyph | A switch on `source` (A4 swaps in `NowPlayingDisplay.glyph`) |
| `TopBarViews.swift:583` | `player.rawValue ?? "Music"` | `source.kindName`, and the command target when nothing is shown |
| `TopBarServices.swift:103`, `:130` | Loops over `[.music, .spotify]` | `NowPlaying.Player.allCases` |
| `TopBarServices.swift:159` | A probe skips if another player plays | Removed: each source updates its own entry; the arbiter decides |
| `TopBarServices.swift:182` | Clears only if the same player | `arbiter.update(source, nil)` |
| `TopBarServices.swift:191-209` | Seek: `playing.player`, in-process `NSAppleScript`, Automation hint | Through the hub: a player seek runs `MusicSeek.script` via `SpotifyPlayer.osascript`; a browser seek is `media.command seek`; the hint only for players |
| `TopBarServices.swift:230` | `?.player ?? .music` | `NowPlayingArbiter.commandTarget` |
| `TopBarServices.swift:175-177` (added 14 November) | M1 resets the modes when `previous?.player` differs and reads them for `playing.player` | Reset when the shown source changes; read only when the shown source has a `scriptedPlayer`, never for an entry that is not shown |
| `MusicModes.swift:87` (added 14 November) | `shouldRead` compares `previous.player` with `current.player` | Compares `source`; the signature stays, so `MusicModesTests` passes unchanged |
| `LiveDiagnostics.swift:69` (added 14 November) | S3 takes `nowPlaying?.player.rawValue` as the player's name | `nowPlaying?.source.kindName`: the kind only, never a host or title |
| `FastActions.swift:81` | `hasSession: topBar?.nowPlaying != nil` | `hub.hasPlayerSession`, so a shown tab never stops voice "play" resuming Spotify |
| `FastActions.swift:291` | Shown item `player == .spotify` | `hub.entry(.player(.spotify))?.isPlaying`, so a Music pin cannot hide Spotify's state |
| `DictationController.swift:608-610`, `:1066-1069` | Blind `.playPause` on pause and on resume | `pauseForDictation()` and `resumeAfterDictation(_:)` (below) |
| `ArtworkStore.swift:122-125` | Switch on player | Switch on `artworkStrategy`; the player fallback scripts (`:140`, `:152`) and `Automation.players` (`PermissionsModel.swift:328`) stay |

### App side

- `TopBarServices.swift:99-209` and `:229-267` (not output devices, `:211-227`) move to a new `MusicPlayerFeed.swift`
  with M1's mode reads (`:269-367`), reporting to the hub. The seek moves to the bounded `SpotifyPlayer.osascript`
  (`SpotifyPlayer.swift:98`).
- New `NowPlayingHub` (main actor) owns the arbiter and follow setting, writes `model.nowPlaying`
  (`TopBarModel.swift:128`) only when it differs, raises the cue, requests artwork, and routes `musicCommand` and
  `seek` (wired at `TopBarServices.swift:45-46`). Browser commands go to an optional `browserCommand` closure (A3);
  nil does nothing. After any command it updates the entry at once, as `TopBarServices.swift:258-262` does today; for
  a player the feed then reads the player back, as `:263-265` does today (see the addendum).
- Dictation: the hub sets `TopBarModel.pauseForDictation: () -> NowPlayingSource?` (an explicit `pause` to the shown
  playing source, which `DictationController` keeps instead of `pausedMedia`) and `resumeAfterDictation(_:)` (an
  explicit `play` to that same source only if its entry still exists and is paused; never the fallback target).
- `TopBarModel.musicPageVisible` is set by the Music page's appear and disappear in `TopBarViews.swift`; the hub's
  `observeMusicPage(_:)` lets A2 and A3 register from their own files. `musicModes` (M1) resets when the source changes.
- `ArtworkStore.load` (`:116-131`): `pageImage` returns before the disk read (`:117`) and never calls `save` (`:127`).
  It streams with `session.bytes(from:)`, rejects a `Content-Length` over 2 MB and stops at 2 MB, keeps the 8 s
  timeout, and a task delegate refuses any non-`https` redirect. `ArtworkSource.pageImageAllowed(_:)`: `https` only,
  no IP literal, no `localhost`, no name ending in `.local`, `.localhost`, `.lan`, `.internal` or `.home.arpa`. A public
  name that resolves to a private address is a known gap for A3 to weigh.
  Every cover request, a page's and the Music and Spotify lookups alike, goes through one session that accepts no cookie,
  stores none and keeps no URL cache.
- Lyrics: `LRCLIBQuery` (`Lyrics.swift:96`) is unchanged. `LyricsStore.load` (`LyricsViews.swift:56`) asks only with
  the `lyrics` capability, else `.none` as today; without `persistsDerivedData` it skips `cache.load` and `cache.save`.
  The store is now a thin adapter over the pure `LyricsFlow` reducer, so both rules are applied in the adapter and
  the reducer is not edited: the capability goes in as `LyricsFlow.Track.isAskable` (`:61`), and the cache is skipped
  where the adapter runs the `readCache` and `saveCache` effects (`:82-84`, `:90-91`). Details in the addendum.
- M4's `MusicAwakeHold` follows the shown item, so it counts any shown source; its note says "the source shown in the
  notch" instead of the player. S3's "Now playing" row reads `source.kindName`.

Fail closed: an unknown follow label is `Any player`. A pinned player that is not running shows nothing, not another
source. A command outside the capabilities, or with no target, does nothing; so does a dictation resume whose source is
gone. A failed, oversized, redirected or disallowed cover leaves the hue tile and writes nothing to disk.

### Tests first

- `Tests/ZeusCoreTests/NowPlayingArbiterTests.swift`: a second start wins; the shown source pausing while another
  plays shows the one playing; pausing alone stays; first seen paused never displaces; a track change keeps the
  start; quit and stop remove; a pin ignores others and gives nil when absent; ties; labels; `commandTarget` with and
  without a pin; a mismatched update is rejected; `hasPlayerSession` ignores browser entries.
- `Tests/ZeusCoreTests/NowPlayingSourceTests.swift`: names, bundle ids, base sets (Spotify without the modes),
  per-item `seek` and `lyrics`, a Music item with duration 0 and an artist keeps `lyrics`, `allows` for every kind,
  `persistsDerivedData`, `elapsed` at rate 2 and 0.
- `ArtworkTests` gains `@Test` functions `playerCacheKeysAreUnchanged` (literal keys recorded on the base first),
  `pageImageKeysHashTheURL` and `pageImageAllowedRules`. `W8NowPlayingTests` gains `parsedItemsCarryTheirSource`.
  `NowPlayingTests` (`TopBarTests.swift:140`) and `MusicSeekTests` pass unchanged.
- `Tests/ZeusAppTests/NowPlayingHubTests.swift` (fakes, recording closures): out-of-capability commands are refused;
  nil `browserCommand` does nothing; the pin holds; entries go when a feed turns off; an identical sample writes
  nothing; two quick toggles give pause then play; resume after its source was removed does nothing and never reaches
  Music. `PageArtworkDiskTests`: `ArtworkStore(directory: temp)` with a stub `URLProtocol` shows a page cover, leaves
  the directory empty, and ignores a file seeded at the page key.

## A2. Music position re-read (deferred)

Deferred on 14 November 2026: step zero below needs a person at the Mac, so A2 is not in the build order (A1, then A4,
then A3) and no builder starts it. The text is kept as written, with its line references corrected, for when step zero
has run. Until then Music's position still drifts after a scrub, as it does today.

### Step zero, on a Mac, before A2 is scheduled

`NowPlaying.probeScript` and `parseProbe` (`NowPlaying.swift:85-111`) already read state, title, duration and `player
position` behind the `is not running` guard, and `syncMusic` (`TopBarServices.swift:148-167`) drops stale answers via
`musicRevision`; A2 adds no second script, parser or check. The research found Music's notification names only in the
binary on macOS 27, so the owner first logs `com.apple.Music.playerInfo` for play, pause, a track change and a scrub.

### Behaviour

- If a scrub posts, the feed runs the existing probe once after each Music notification, coalesced over 250 ms. If
  not (or nothing posts), it runs when the Music page opens and every 10 s while it is open and Music is shown playing.
- Only with Music running and Automation already granted; no prompt, no hint. One Music read in flight across all
  callers, launch syncs included; a notification during a read makes it stale (`musicRevision`) and one more read
  runs. The position anchors at receive time, as `parseProbe` does: process start-up dominates any send and receive
  midpoint. Spotify is not read: its notification carries `Playback Position` (`NowPlaying.swift:72`).

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/PositionReread.swift`: `PositionRereadGate` (value type), `debounce = 0.25`,
`pageInterval = 10`, `mode` (`afterNotification`, `whilePageOpen`); `request(revision:now:)` gives `.startAfter(delay)`
or `.markPending`; `finish(revision:current:)` gives `.done` or `.readAgain`; `nextPageRead(visible:shownIsMusic:
playing:now:)` gives a delay or nil. `MusicPlayerFeed` routes every `syncMusic(.music)` through the gate.

Fail closed: on no Music, no consent, a timeout, a bad answer, a stale revision or a quit mid-read, the extrapolated
position stays and nothing is retried until the next trigger.

### Tests first (`Tests/ZeusCoreTests/PositionRereadTests.swift`)

Never two reads in flight; a burst inside 250 ms gives one read; a notification during a read gives exactly one more;
`nextPageRead` is nil when the page is hidden, Music is not shown or not playing, and 10 s otherwise.

## A3. Browser media through the Zeus extension

### Behaviour

- With `music.browserMedia` on and the extension connected, Chrome tab media is a source, shown per A1. Read:
  `media.state`. Control: `media.command` with `play`, `pause`, `seek`; `next` and `previous` have no standard path
  (an extension cannot call a page's media session handlers), so they answer `not_supported`.
- The chosen element, by one helper nested in both page functions: `video, audio` in the top frame with `srcObject ===
  null`, a non-empty `currentSrc`, not muted and `volume > 0`, ranked by not paused, then largest visible area, then
  longest finite duration. A page whose only candidates carry a `MediaStream` (a call) gives no item. The fingerprint
  is a short hash of `currentSrc` plus the rounded duration, never the URL itself.
- Title, artist and album come from media session metadata; without it the tab title is used with no artist (so no
  lyrics). Position, duration, rate and paused come from the chosen element. A live stream has duration 0, no scrub.

### The bridge is pull-only

`zeus-bridge` answers only `ping` from Chrome (`unknown_type` otherwise, `main.swift:128-134`), so the app polls and a
pure reducer decides: `BrowserPollMachine.next(state, event) -> (state, [effect])`, with events `tick`, `reply`,
`timedOut`, `notConnected`, `staleTarget`, `notSupported`, `chromeLaunched`, `chromeQuit`, `settingOn`, `settingOff`,
`screensSlept`, `screensWoke`, `followChanged`, `outputActivity(Bool)` and `version(String?)`.

- Failures told apart: `UnixSocket.request` returns nil for connect, write and read-timeout failures alike, and
  `ChromeBridge.call` (`ChromeBridge.swift:54-68`) makes any nil `notConnected`. A3 adds `UnixSocket.exchange(path:
  payload:timeout:) -> Outcome` (`notConnected`, `timedOut`, `closedEarly`, `reply(Data)`) and
  `ChromeBridge.callOutcome` (`.ok`, `.notConnected`, `.timedOut`, `.failed(BridgeError)`); `request` and `call` stay.
  A `closedEarly` exchange is `.notConnected`: since the bridge began checking its peer's signature, that is also how
  a refused app looks (see the addendum).
- It polls only when the setting is on, top bar services started (never in `--qa-startup`), Chrome runs, `ping`
  reports 0.5.0 or later (`sw.ts:92-93`), screens are awake, `music.follow` is `Any player`, and Chrome output is
  running, a browser item is shown, or a known paused entry exists while the Music page is open. 2 s while a browser
  item is shown and playing, else 5 s; one request in flight; 1.5 s timeout.
- Output gate: new `ChromeOutputActivity` in the `ScribeMicActivityObserver` pattern (not main-actor isolated,
  explicit hop) listens for `kAudioProcessPropertyIsRunningOutput` on processes whose `kAudioProcessPropertyBundleID`
  starts with `com.google.Chrome`, else for the default output's `kAudioDevicePropertyDeviceIsRunningSomewhere`.
  Property listeners only: no IO proc, no tap, no audio.
- `notConnected` while Chrome runs (the worker reconnects every 5 s, `sw.ts:7`, `:61-68`) backs off 5, 10, 20, 40,
  60 s with a `ping` before polling again; `timedOut` keeps the state; three failures in a row drop the entries; a good
  reply resets. The loop stops only on `didTerminateApplication` for `com.google.Chrome`, the setting off or an old
  version, and restarts on `didLaunchApplication` (`queue: .main`, `MainActor.assumeIsolated`, as at
  `TopBarServices.swift:115-127`). Screen sleep pauses it.
- Between polls: `position + (now - anchor) * rate` while playing, clamped, anchored at receive time; a sample
  re-anchors only past 0.75 s of error or on a paused or rate change, so the hub sees an equal value.

### Messages (extension)

- `media.state` (read only, no consent, like `page.context` at `sw.ts:100-107`), params `known` (at most 4
  `{tabId, documentId}`). Tabs: `chrome.tabs.query({audible: true})` plus known ones, at most 4, skipping `discarded`,
  `incognito` and tabs `scriptable()` refuses (`sw.ts:286-288`). Each tab has its own `try`/`catch` raced against
  400 ms and one `executeScript` of `mediaState()`, which also returns `location.href`; the frame's `documentId` is the
  target and an `href` unlike `tab.url` skips the tab. This replaces `captureTarget` then `runTarget` (`sw.ts:229-239`,
  `:266-278`) for reads. A slow or failed tab is left out, never an error; closed or reloaded known tabs go in `gone`.
- Item: target, audible, title, artist, album (300 characters each), one `artworkURL` the worker picked (largest
  `https`, never `data:`, `blob:` or `http:`; 2048 characters), `playbackState`, `currentTime`, `duration` (null when
  infinite), `playbackRate`, `paused`, `seekable`, `fingerprint`: about 3.5 KB at worst, far under 64 KB for four.
- Single flight: a `media.state` during another gets the last reply marked `stale: true`, so work does not pile up
  behind `zeus-bridge`'s 60 s pending timeout (`main.swift:6`, `:106`).
- World: reads run in ISOLATED. If the step-zero spike shows metadata as null there while the page set it, only that
  read moves to `world: "MAIN"` (minimum Chrome 120), with values type-checked and capped in the worker and in Swift.
- `media.command`: `validatedTarget(params, true)` (`sw.ts:242-264`) then `runTarget` with `mediaCommand(action,
  seconds, fingerprint, expectedURL)`. `requiresActive: false` lets a background tab be controlled, but a closed,
  navigated or reloaded document, or a chosen element with another fingerprint, fails as `stale_target` with nothing
  changed. A `play()` refused by autoplay rules is `blocked_by_page`. Seek clamps inside the seekable range, short of
  the end. `next` and `previous` throw `not_supported` before any injection. Commands never run in MAIN.
- Size: far under the 1 MB host-to-Chrome frame (`Bridge.swift:73`) and the 4 MB reverse cap (`:75`). Page functions
  keep the `page.ts:1-2` contract: no imports, nested helpers (vm fixtures run them through `toString()`).

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/BrowserMedia.swift`: `BrowserMediaItem`, `BrowserMediaElement`;
`BrowserMediaState.parse(_ value: JSONValue)` rejects non-finite or negative numbers, caps strings and counts, drops a
malformed item and keeps the rest. `BrowserMediaRules`: `nowPlaying(_:anchor:)`, `extrapolate`,
`shouldReanchor(predicted:observed:)`, `pollDelay(_:)`, `command(for:item:)` with `params(target:)` in the shape of
`ChromeBridge.ActionTarget.value` (`ChromeBridge.swift:27-32`) plus the fingerprint, `extensionSupportsMedia(version:)`
and `BrowserMediaFailure.init(code:)`. Swift re-checks the artwork scheme. `BrowserPollMachine` lives beside it.

App side: `BrowserMediaFeed` (main actor) applies the machine's effects in one `Task` with a generation token, feeds
the hub and sets `hub.browserCommand`. Socket I/O stays on the detached task inside `ChromeBridge`; only Sendable values
cross. `ScribeCallWatcher` gains a read-only `browserCallPresent`; the feed never starts the watcher. That file is
being rewritten on another branch, so the accessor is one computed property over state the watcher already keeps and
A3 changes nothing else there (the exact line is in the addendum). Lint in
`test_source_lint.py`: the literal `"media.command"` appears in `Sources/Zeus` only in `Chrome/ChromeBridge.swift`;
`ChromeBridge.mediaCommand(` is called only from `Chrome/BrowserMediaFeed.swift`; `Chrome/ChromeActions.swift`,
`ZeusCore/ZeusTag.swift`, `ZeusCore/BrowserCommand.swift`, `Zeus/Intent/**` and `Zeus/Voice/**` never mention either.
One fail-first sample per shape, as in `test_pointing_lint_detects_its_failure_shapes`.

### Shipping the extension

- `extension/manifest.json`: 0.4.0 to 0.5.0. Permissions unchanged: `tabs`, `scripting` and `<all_urls>` already
  cover `tabs.query({audible})` and both worlds. `package.json` stays 0.1.0 (not tied to the manifest).
  `scripts/bundle.sh:54-60` copies the build into the app, and `AppDelegate.swift:217-222` refreshes the unpacked copy
  at launch (`ChromeInstaller.swift:49-66`). Chrome loads it only on a reload of the extension or a restart.
- Until then the old worker answers `ping` with 0.4.0 and `media.state` with `unknown_type` (`sw.ts:222-223`); Zeus
  does not poll. While Chrome runs, a `SettingStatus` row reads "Press Reload on the Zeus card in Chrome's extensions
  page". Its button opens `chrome://extensions` only on a press and only if Chrome runs (the helper at
  `ChromeInstaller.swift:69-76` would launch Chrome and points at Load unpacked). It re-checks when Chrome launches,
  the setting is turned on, or the Music page opens.

Fail closed: with the setting off, an old extension, a pin or Chrome closed there is no polling and no browser entry.
Timeouts and `notConnected` keep the state for three failures, then drop it; a malformed reply is a failure.
`stale_target` drops the item, no retry, page unchanged. `not_supported` or `blocked_by_page`: one hint, no retry. A
call gives no item. A failed cover leaves the hue tile.

### Tests first

- `Tests/ZeusCoreTests/BrowserMediaTests.swift`: a full reply; no metadata gives the tab title and no artist; infinite
  duration gives 0 and no seek; bad numbers rejected; items and strings capped; extrapolation at rate 1, 2 and 0;
  re-anchor tolerance; `pollDelay` nil when pinned and with no output and nothing shown, else 2 s or 5 s; command
  mapping (next and previous nil, seek clamped); target JSON with the fingerprint; the version gate.
- `Tests/ZeusCoreTests/BrowserPollMachineTests.swift`: a timeout keeps the state for 3 polls, then drops it;
  `notConnected` while Chrome runs backs off and recovers; Chrome quitting stops and drops; `stale_target` drops with
  no retry; `not_supported` hints once; setting off, a pin and screen sleep stop polling.
- `UnixSocketSafetyTests` gains: a missing path is `notConnected`, a silent listener `timedOut` within the bound, a
  closing one `closedEarly`; `request` still returns nil for all three.
- `extension/tests/media.test.mjs`, reusing the vm fixture of `browser-target.test.mjs:11-107`: an audible tab is
  reported; no media gives no item; a `MediaStream` element is not reported; an ad and a content element pick the
  content one; incognito and discarded tabs are skipped; a throwing and a never-resolving tab still leave a reply for
  the healthy one in budget; a second `media.state` gets `stale: true`; a known paused tab is reported; play, pause and
  seek reach the captured document; a changed fingerprint, reload, navigation or closed tab give `stale_target` with
  no `play()` or `pause()` call; next and previous give `not_supported` with no injection; a command without
  `pageTarget` fails; a background tab can be controlled.

## A4. Source name and honest controls

### Behaviour

- The Music page names the source above the title: "Music", "Spotify", or "Chrome · example.com". The Open button
  reads "Open Music", "Open Spotify" or "Open Chrome"; the hub (A1) routes it.
- Controls a source cannot honour are not drawn: Previous and Next for a browser item, M1's Shuffle and Repeat where
  the capability is missing, the scrubber's seek without a duration (progress still shows), the lyrics button without
  `lyrics`. The transport stays centred. With nothing playing, today's controls show. The Home music widget
  (`HomeWidgetViews.swift:78`) hides Previous and Next the same way.
- Closed notch: the wing width does not change (`ClosedWings.extraWidth`, `TopBarViews.swift:1468`). The tile's
  placeholder glyph and the cue glyph (`TopBarViews.swift:1500`, always `music.note` today) follow the source. When the
  shown source changes the cue reads "Spotify · Title"; within one source it keeps "Title · Artist" (`:1559`).

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/NowPlayingDisplay.swift`: `sourceLine(_:)`, `glyph(for:)` (`music.note`,
`dot.radiowaves.left.and.right`, `globe`), `openLabel(for:)`, `visibleControls(for:)` (an option set over previous,
playPause, next, shuffle, repeat, scrub, lyrics, open), `accessibilityLabel(for:)`, and `cueText(title:artist:source:
sourceChanged:)`. `NotchCue.trackChanged` (`TopBarLayout.swift:237`) gains `source: NowPlayingSource?`.

### Design

Source line in `TopBarStyle.label(10, .semibold)`, `Theme.cloudQuiet`, one line, host truncated in the middle. Removed
controls leave no gap or dimmed placeholder; nothing is disabled. No new motion (none under Reduce Motion). VoiceOver
reads the left wing as "Playing in Spotify: Title"; hidden controls are not focusable. New `SnapshotRenderer` fixtures
cover a browser item on the Music page and in the cue. No new window, so `ZeusWindowSharing` is untouched.

Fail closed: unknown capabilities show today's set. An empty host shows the kind name alone. A press that races a
capability change is still checked by the hub (A1) and ignored.

### Tests first (`Tests/ZeusCoreTests/NowPlayingDisplayTests.swift`)

Source line per kind and with an empty host; glyph and open label per source; visible controls for Music, Spotify, a
browser item with and without a duration, and nothing playing; the accessibility label; cue text and glyph.

## Settings rows

| Id | Where | Control | Default | Ticket |
| --- | --- | --- | --- | --- |
| `music.follow` | Appearance, new group "Music" | Menu: Any player, Music, Spotify. "Show music from". Note: "Any player shows what started playing last." | Any player | A1 |
| `music.browserMedia` | Privacy, Music card (`GlanceSettingsPages.swift:1142`) | Toggle: "Show media playing in Chrome". Note: "Reads title, artist and position from Chrome tabs through the Zeus extension. Covers load from the page's own image link and are not saved. Calls are never shown." | Off, never enabled by import | A3 |
| `music.browserMediaStatus` | Under that toggle | `SettingStatus` row: the reload hint while the extension is older than 0.5.0 | n/a | A3 |
| `keepAwake.whileMusic` | M4's row (`GlanceSettingsPages.swift:107`, generator line 21) | Note only: "Holds the display on only while the source shown in the notch is playing. Stops on low battery or heat." | Unchanged | A1 |

Rows go in `scripts/gen-settings-catalog.py`; regenerate, never hand-edit; `scripts/check-settings-catalog.sh` passes.

## Repo hazards that apply

- Swift 6: observers keep `queue: .main` plus `MainActor.assumeIsolated`; Core Audio listener blocks live in a type
  that is not main-actor isolated (`ScribeMicActivity.swift:12-14`); detached work captures Sendable values only
  (TYPE-001, TYPE-005); no unapplied main-actor method as a Binding setter in A4 (TYPE-011). Realtime audio: nothing
  on an audio thread, no tap, `AUDITED_AUDIO_FILES` unchanged. No semaphore or group waits.
- Apple Events this plan adds or moves go through `SpotifyPlayer.osascript` (out of process, 3 s). Left alone:
  `ArtworkStore.script` (`:158-161`, in process on the main actor, unbounded), `AgentHub.swift`, `AgentCardsUI.swift`.
- `NotchController` and its lint anchors are not touched; the em dash lint covers new strings. Settings generator, REG
  ids, the 1 MB frame and the pull-only bridge: above. Sandboxes cannot compile Swift (TYPE-012): budget a Mac build.

## Out of scope, waiting on an owner decision

- A system-wide source hosting the private now-playing framework in a system interpreter (ungive/mediaremote-adapter):
  it would cover desktop players without scripting and other browsers, but rests on an undocumented gate the OS vendor
  can close, on notarizing an embedded framework, and on a watchdog. No longer waiting: the owner approved the route
  and it is planned separately in `docs/NOTCH-SYSTEM-SOURCE-PLAN.md` (tickets P1.0 to P1f, REG-470 to REG-489). It is
  still out of scope here: it adds a third `NowPlayingSource` case after A1, and A1 only keeps the model open to it.
- Tab next and previous, and embedded frames, by a script injected into every page (code in every page). Media keys as
  a fallback (needs Accessibility). Other browsers (host folders not verified).

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the missing names).
2. `swift build --build-tests`, then `swift test --filter` for `NowPlayingArbiterTests`, `NowPlayingSourceTests`,
   `PositionRereadTests` (with A2, deferred), `BrowserMediaTests`, `BrowserPollMachineTests`, `NowPlayingDisplayTests`,
   `UnixSocketSafetyTests`, `NowPlayingHubTests`, `PageArtworkDiskTests`, and the pinned `W8NowPlayingTests`,
   `NowPlayingTests`, `ArtworkTests`, `MusicSeekTests`, `LyricsTests`, `MusicModesTests`, `LiveDiagnosticsTests`, plus
   the suites the merged waves added (listed in the addendum).
3. `cd extension && npm run typecheck && npm test && npm run build`.
4. The whole `ZeusCoreTests` module on the branch and the base, compared, with the known failures in "Native host
   process boundaries" counted again on the base first (4 at `47566d1`; the fixture changed in `9f2ffe4`). The
   settings generator and its check; `python3 -m unittest discover -s qa/closed-loop/tests`.
5. `./tools/check.sh` development mode, from a worktree under `<models-dir>`. An independent review of each diff.
6. Still owed on a real Mac: A2 step zero (deferred with A2); Music and Spotify in turn, both pins; Spotify shuffle
   and repeat set by script and read back; dictation pausing a tab and resuming that tab, never Music; the ISOLATED
   metadata spike; play, pause, seek on a tab; a reload then a tap changing nothing; a video call tab never shown or
   paused; an ad element; Chrome quit stopping the loop (`zeus-bridge` gone); the reload hint; idle CPU with the
   toggle on and nothing playing (`scripts/check-perf-budget.sh`); a page cover shown, absent from the artwork cache,
   gone after relaunch.

## Addendum: the code on 14 November 2026

Read on `codex/sources-20261114` at `3757de2`, 117 commits after `47566d1` (`git log --oneline 47566d1..HEAD`). Every
file and line reference in this plan was opened again. The stale ones are corrected in place above; this section says
what the merged code changes for each ticket. Where a point of a ticket is not named here, its behaviour and its files
stay as planned. Nothing was compiled or run for this refresh: it is a reading of the tree, so every statement about
behaviour is a statement about the source.

### What changed in the code since the plan was written

| Area | What merged | Where it sits now |
| --- | --- | --- |
| Lyrics (M2, M3 and their fixes) | The lookup, retry, cache and privacy decisions are one pure reducer, `LyricsFlow`. `LyricsStore` only runs its effects. Matching, size limits and word timing have their own files. The lookup is three requests, checked against the privacy switch before each one | `ZeusCore/Lyrics/LyricsFlow.swift`, `LyricsMatching.swift`, `LyricsLimits.swift`, `LyricWords.swift`; `LyricsViews.swift:12-200` (`load` at `:56`, effects at `:76-93`); `LRCLIBQuery` at `Lyrics.swift:96`, `isAskable` at `:111` |
| Shuffle and repeat (M1 and its fixes) | `MusicCommand` has `toggleShuffle` and `cycleRepeat`. The modes are one value on the model. A press runs through the `MusicModePress` reducer, which sends the change and reads the player back. Spotify's modes are scripted too. An unknown mode is drawn subdued and still takes a press; an on toggle is a bordered capsule | `TopBarModel.swift:137`, `:242`; `ZeusCore/TopBar/MusicModes.swift`; `TopBarServices.swift:22-24`, `:269-367`; `TopBarViews.swift:503-527` |
| Play and pause | After the optimistic toggle the player is read back at 1.5 s and 4 s; a notification that lands first wins | `TopBarServices.swift:258-266` |
| Display hold while music plays (M4 and its fixes) | The hold follows the model's play state through a callback set in `nowPlaying`'s `didSet`, with a 20 s grace, a two minute lease and its own assertion. Setting `keepAwake.whileMusic` | `TopBarModel.swift:128-134`, `:229`; `AppDelegate.swift:172-175`; `TopBar/MusicAwakeHold.swift`; `ZeusCore/TopBar/MusicAwake.swift`; row at `GlanceSettingsPages.swift:107`, generator line 21 |
| Surface (S1, S2, S3 and their fixes) | Open on click in `NotchController`, with source lints on its wiring. Rounded corners in their own window. The live diagnostics card, whose "Now playing" row takes the player's name from a `NowPlaying` value | `test_source_lint.py:585-679`; `Notch/ScreenCornerOverlay.swift`; `Settings/GSLiveDiagnosticsCard.swift:93`; `ZeusCore/Diagnostics/LiveDiagnostics.swift:65-71`, `:129-137` |
| Local sockets and the browser bridge | A socket that names its allowed program now also checks that program's code signature, once per connection, before it reads a byte. `chrome.sock` accepts only the app: the right file name, a valid signature, the app's identifier. The bridge reads its own identity at start. A bridge and an app of different build kinds refuse each other until Chrome is started again, and the not-connected message says so | `ZeusCore/PeerSigning.swift`, `PeerBinaryRule.swift`, `PeerCredentials.swift:150-166`, `UnixSocket.swift:230-273`; `Sources/zeus-bridge/main.swift:146-152`; `ChromeBridge.swift:41`, pinned by `ChromeBridgeHintTests` |
| Command line | "Allow command-line control" lives in the Keychain. The debug hooks that open panels, capture or write (`tab`, `animate`, `screenshot`, `hud-state`, `open-settings` and others) refuse unless it is on and the caller is the app's own `zeus` command | `ZeusCore/CLIGate.swift:9-13`; `App/CommandCenter.swift`; `scripts/qa-n-lane-hooks.sh` |
| Stored keys | A saved key is bound to the address it was saved for | `ZeusCore/Connections/CredentialOrigin.swift` |
| Test gates | A suite under `Tests/ZeusAppTests` runs in CI and in `tools/check.sh` only when `qa/feature-map.json` has a `native-fixture` row for it; `ZeusCoreTests` is bound whole. `UnixSocket.swift` is also built by two portable groups, and `UnixSocketSafetyTests` by one of them | `qa/closed-loop/native_evidence.py:15-42`; `qa/feature-map.json:398-402`, `:654-660`; `qa/portable-core/prepare.py:48-57` |
| Sister plans | The system-wide source, lock screen, earbuds, Focus name, output list and drawn notch plans are in `docs/`. Their regression blocks start at REG-470 | `docs/NOTCH-SYSTEM-SOURCE-PLAN.md:44-50` |

None of the new files this plan names exists yet, and no merged change built any part of A1 to A4.

### Decisions applied on 14 November

- Regression ids come only from REG-450 to REG-469. The split is A1 450 to 455, A4 456 to 459, A3 460 to 467, and
  468 and 469 held for A2. REG-410 to REG-449 are held by other work. The highest id in the tree is REG-409.
- A2 is deferred. Its text stays, marked deferred, with its references corrected.
- The build order is A1, then A4, then A3, one after the other. The plan had A2, A3 and A4 in parallel after A1.
- The system-wide source is planned in `docs/NOTCH-SYSTEM-SOURCE-PLAN.md` and adds a third source case after A1. A1
  keeps its model open to that case and builds none of it.
- `Sources/Zeus/Scribe/ScribeCallWatcher.swift` is being rewritten on another branch, so A3 adds its one accessor in
  the smallest way there is.

### A1: what changes

Behaviour stays as planned. The points below are where the merged code moves the work or adds to it.

1. The music block to move is larger. It is `TopBarServices.swift:99-209` and `:229-367` (M1's reads and presses are
   in the file now, at `:269-367`), plus the music state at `:18-24` and the music lines of `stop()` at `:85-90`.
   `TopBarServices.stop()` stays and calls the feed's own stop. Output devices (`:211-227`) stay where they are.
2. The read-back after play or pause moves with it. `TopBarServices.swift:263-265` reads the player again 1.5 s and
   4 s after the optimistic toggle, because the display hold follows that guess. The hub still updates the entry at
   once; for a player source `MusicPlayerFeed` keeps this read-back, and a notification that lands first still wins.
   A browser entry needs no extra read: A3's next poll is its read-back. `NowPlayingHubTests` gains one case: after a
   play or pause sent to a player, the feed is asked for a read-back, and never for a browser source.
3. The modes belong to the shown source. There is one `musicModes` value (`TopBarModel.swift:137`), and today it is
   reset and read inside `updateMusic` for whichever player just reported (`TopBarServices.swift:175-177`). With one
   entry per source that would let a player that is not shown reset the shown one's modes. So the reset happens when
   the shown source changes, and the read happens only when the shown source has a `scriptedPlayer`. This is what
   "`musicModes` (M1) resets when the source changes" already meant; the code now makes the place exact.
   `MusicModePress` takes a `NowPlaying.Player` (`MusicModes.swift:176-182`): the feed hands it the source's
   `scriptedPlayer`, and a source without one never reaches it, because the hub checks capabilities first.
4. Two more hidden reads of `player`, both added to the table above: `MusicModeRules.shouldRead`
   (`MusicModes.swift:87`) and the diagnostics row (`LiveDiagnostics.swift:69`, which is "the S3 call site"). The card
   itself (`GSLiveDiagnosticsCard.swift:93`) hands over the whole value and does not change. The row then reads
   "Chrome, Playing" for a browser item: the kind only, as the privacy section requires.
5. Lyrics go through `LyricsFlow`. `LyricsStore.load` no longer decides anything itself (`LyricsViews.swift:56-64`),
   so the two A1 rules are applied in the adapter and `LyricsFlow.swift` is not edited:
   - "Asks only with the `lyrics` capability, else `.none`": `LyricsFlow.Track.isAskable` (`LyricsViews.swift:61`)
     is set from the item's `lyrics` capability. For a player that is exactly `LRCLIBQuery.isAskable`, as today, so
     nothing changes for Music or Spotify; the reducer already answers `.none` for a track that is not askable
     (`LyricsFlow.swift:89`).
   - "Without `persistsDerivedData` it skips `cache.load` and `cache.save`": the store keeps that flag beside `query`
     (`:31`), set in `load`. On the `readCache` effect (`:82-84`) a source that does not persist answers
     `.cacheRead` with `cached: nil` and never opens the file; on `saveCache` (`:90-91`) it does nothing.
   - The source lint at `test_source_lint.py:629-637` pins this file: `func load(for playing: NowPlaying?)` must
     still contain `send(.load(enabled: Self.enabled`, `run` must keep `guard mayRequest(key) else { return }`
     before `Self.fetch(`, the `retryPlan(for: key, now: Date(), enabled: Self.enabled)` call stays, and there is
     exactly one `self?.run(`. A1 keeps all four; `test_source_lint.py` belongs to A3 and A1 does not edit it.
   - `LyricsTests` in step 2 of the verification still pass unchanged, and so must `LyricsFlowTests`.
6. The display hold needs no new wiring, but it depends on where the hub writes. The hold and the spectrum service
   are both driven from `nowPlaying`'s `didSet` (`TopBarModel.swift:128-134`), so the hub must write that property and
   no parallel one. "Writes only when it differs" keeps the hold from being poked by equal samples. The note text
   A1 changes is at `GlanceSettingsPages.swift:107` and generator line 21 (today: "Holds the display on only while
   Music or Spotify is playing."); the catalog and inventory are regenerated, never edited.
7. Spotify's shuffle and repeat ship today. The plan gives Spotify no `shuffle` and no `repeatMode` until a check on
   a Mac, and "Review notes" already calls that an owner decision. Since then M1 merged with Spotify's modes live
   (`MusicModes.swift:25-30`, `:119-124`) and with a read-back after every press, so a mode Spotify did not take is
   shown as it really is or as unknown. A1 as planned therefore takes away a control that works today, and between
   A1 and A4 the two Spotify buttons would still be drawn and do nothing. The plan is not changed here; the owner
   decides before A1's base capability set is final. If the answer is to keep them, Spotify's base set has both and
   the line about the check in step 6 goes.
8. Open to a third case, without building it (the bullet added under "Rules"). In practice: `kindName`,
   `appBundleID`, `baseCapabilities`, `artworkStrategy`, `scriptedPlayer` and `persistsDerivedData` are the only
   places that know what a kind is; `ArtworkStore` switches on `artworkStrategy` with every case named, so a new
   strategy stops the build there; the artwork key in `Artwork.swift` and the arbiter's tie order each sit in one
   function that names every case; a pin shows a source only when its `scriptedPlayer` is the pinned player, so it
   needs no list of the other kinds; the hub sends a command that is not for a player through the optional closure
   of that kind and never through an `else`. A1 adds no `.system` case, no `SystemMediaKey`, no `systemCommand`, no
   `isSystem` and no `inline` strategy. `NowPlayingSourceTests` runs its checks over a list of sample sources, so a
   third sample is one more row.
9. A compile hazard for the "exhaustive switches": on the pinned toolchain a `switch` expression cannot sit directly
   in a call argument (TYPE-009 in `qa/native-compile-regressions.md`). The ternary at `NowPlaying.swift:76` is a call
   argument, so its replacement is bound to a local first.
10. The new app suites need rows in the feature map. `NowPlayingHubTests` and `PageArtworkDiskTests` are compiled but
    never run by CI or `tools/check.sh` unless each has a `native-fixture` check and an `F13` obligation in
    `qa/feature-map.json`, in the shape of `native-MusicAwakeHoldTests` (`:654-660`). A regression row that guards
    one of their cases names that check. The new `ZeusCoreTests` suites need no row.
11. The Appearance page already has a "Music" sub-heading (`GlanceSettingsPages.swift:353`) inside the card "Small
    moments, softly signaled", over the light rows that the generator groups as Everyday lights. `music.follow` is
    not a light, so it still gets its own group in the generator, as planned, and its own card on the page; the
    builder checks on screen that the two do not read as one, and
    `test_every_settings_card_and_page_is_placed_on_a_page` (`test_source_lint.py:313`) passes.
12. Not affected: A1 adds no Apple Event target (Open on a browser item activates a running app), so the Automation
    usage text and `AutomationUsageStringTests` stay as they are. The page-cover fetch and the lyric ask carry no
    stored key, so the origin binding of stored keys does not touch them.
13. With A2 deferred, `MusicPlayerFeed` carries `syncMusic` and `musicRevision` over as they are
    (`TopBarServices.swift:148-167`), and `observeMusicPage(_:)` is still built, because A3 registers through it.

### A2: what changes

Deferred; nothing is built. Two notes for when step zero has run:

- There is one more caller of the Music read than the plan counted: the read-back after play or pause
  (`TopBarServices.swift:265`, in `MusicPlayerFeed` after A1). "One Music read in flight across all callers" includes
  it, so it goes through the gate with the launch syncs.
- A2's files are unchanged (`MusicPlayerFeed.swift`, new `PositionReread.swift`, its tests). It takes REG-468 and
  REG-469.

### A3: what changes

Behaviour stays as planned. A3 is now built third, on top of A1 and A4.

1. A refused app looks like `closedEarly`. The bridge now checks the app's signature on every connection
   (`UnixSocket.swift:259-272`, with the rule set in `PeerCredentials.swift:150-166`). When it refuses, it closes
   the connection without writing, so the app sees the socket end before a line arrives. Before, an early close
   meant only that Chrome's side was going away. `UnixSocket.exchange` reports both as `closedEarly`: a failed write
   after a good connect, an end of stream and a reset all count. `ChromeBridge.callOutcome` maps it to
   `.notConnected`, so the poll machine backs off (5, 10, 20, 40, 60 s with a `ping`) exactly as planned and never
   polls faster against a bridge that refuses it. The machine gains no event. The message for that state is the
   existing one (`ChromeBridge.swift:41`), which already tells the owner to quit Chrome and open it again after a
   change of build kind; A3 does not reword it (`ChromeBridgeHintTests` pins it). The status row of
   `music.browserMediaStatus` keeps its one job, the reload hint.
2. Every poll now costs one signature check inside the bridge. A request is one connection
   (`UnixSocket.swift:122-141`), and the source says the check "can be slow" (`:260-263`). At a 2 s poll that is a
   check every 2 s while a tab plays, inside the 1.5 s timeout and on `zeus-bridge`'s CPU. The plan's numbers stay.
   A3 adds two measurements to its Mac pass, in a bundled build: the time of one `ping` over the socket, and
   `zeus-bridge`'s CPU while a tab plays with the toggle on. A3 adds no cache and no shortcut to the check, and does
   not edit `PeerSigning.swift`, `PeerBinaryRule.swift`, `PeerCredentials.swift` or `Sources/zeus-bridge/main.swift`:
   the check per connection is the security design (`41f3ea3`, `b47ded0`). If the measurement does not fit the
   budget, that goes back to the owner with the numbers.
3. `UnixSocket.exchange` and its `Outcome` stay inside `UnixSocket.swift`, beside `request` (`:122-141`), sharing its
   connect and write steps so both keep the same bounds. The file is built by the portable groups `socket-safety`
   and `bridge-transport` (`qa/portable-core/prepare.py:48-57`) with a fixed list of files, and it has a Glibc
   branch, so the new code uses nothing from outside that list and compiles on both branches.
4. The new `UnixSocketSafetyTests` cases use a test server with the default policy (same user only), as the existing
   cases do, so no signed program is needed: a missing path, a listener that never answers, and a handler that
   replies with nothing (the server closes without writing). They pass no verifier and touch no peer file.
5. The Mac pass needs the bundled app. The bridge accepts only a program named `Zeus` with a valid signature that
   carries the app's identifier, so a loose build product is not expected to pass and every A3 check on a Mac runs
   from the app made by `scripts/bundle.sh`, with Chrome started again after any change between a preview and a
   release build.
6. No new command-line path. A3 adds no `zeus` command and no debug hook for `media.state` or `media.command`. One
   path exists already and is named here as an exception: `Zeus --chrome <type> <json>`
   (`App/DebugCommands.swift:137-158`) sends one raw request of any type, in debug builds only, as a launch argument
   typed by the owner. It is compiled out of a release, it is not a model or voice action, and the lint's literal
   rule does not see it. A3 leaves it alone. The debug hooks a tester may use to open the Music page (`tab`,
   `animate`, `screenshot`) now need "Allow command-line control" turned on first.
7. The call watcher accessor, in the smallest way: one computed, read-only property placed directly under
   `isRunning` (`ScribeCallWatcher.swift:227`), true when the watcher is running and one of `latestCalls` (`:222`,
   set at `:335`) has a browser as its main process (`ScribeCallDetection.isBrowser` on the bundle id of the call's
   `pid`). No stored property, no new scan, no observer, no change to `poll`, `apply` or the probe, and no other
   line of that file. If the rewrite on the other branch merges first, the same property is written again on the
   new file from whatever state it keeps; if the rewritten watcher already exposes that fact, A3 uses it and adds
   nothing. The `MediaStream` rule stays the main guard, as "Review notes" says.
8. The display hold follows a tab. Once the feed reports, a playing tab shown in the notch holds the display when
   `keepAwake.whileMusic` is on, as A1 planned. A3's Mac pass checks that, and that a paused or closed tab lets go
   after the 20 s grace.
9. Small facts: `music.browserMedia` joins `neverEnabledByImport` at `SettingsStore.swift:255-258`.
   `test_source_lint.py` grew by the island lints (`:557-679`); A3 adds its own class and leaves them.
   `qa/extension-regressions.json` binds one test file (`native-session.test.mjs`), so `media.test.mjs` runs through
   `npm test` and is not listed there; A3 leaves that file alone. A3 takes REG-460 to REG-467.

### A4: what changes

Behaviour stays as planned. A4 is now built second, right after A1 and before any browser feed exists.

1. The controls it edits carry M1's work now. `MusicControls` (`TopBarViews.swift:503-527`) draws Shuffle and Repeat,
   subdued while the mode is unknown, with the on state as a bordered capsule and a spoken value. A4's rule sits on
   top of that: a control whose capability is missing is not drawn at all; a control the source can honour keeps
   M1's look, the subdued unknown state included. That state is not a disabled control (it takes a press), so
   "nothing is disabled" still holds. The lyrics button is at `:580-581` and the Open button at `:582-583`.
2. "Unknown capabilities show today's set": today's set now has Shuffle and Repeat in it.
3. Browser items are proven with fixtures in A4. No feed reports a tab until A3, so the browser cases rest on
   `NowPlayingDisplayTests` and the new `SnapshotRenderer` fixtures; seeing a real tab's source line, hidden
   Previous and Next, and its cue on a Mac moves to A3's Mac pass.
4. Open to the third case: `NowPlayingDisplay` reads the source's properties where it can, and where it must match
   (the glyph, the source line) it names every case with no `default`, so P1a's case stops the build there.
5. If the owner keeps Spotify's shuffle and repeat (A1, point 7), A4 draws them: it follows the capabilities and
   needs no change of its own.
6. The lints on `NotchController` grew (`test_source_lint.py:589-602`); A4 still does not touch that file. The
   rounded corners are a separate window and A4 adds none, so `ZeusWindowSharing` is still untouched.
7. A4 takes REG-456 to REG-459.

### File sets that are now different

| Ticket | Added to its files | Why |
| --- | --- | --- |
| A1 | `Sources/ZeusCore/TopBar/MusicModes.swift` | `shouldRead` reads `player` at `:87` |
| A1 | `Sources/ZeusCore/Diagnostics/LiveDiagnostics.swift` | The S3 call site is here, at `:69`, not in the card |
| A1 | `qa/feature-map.json` | One `native-fixture` row and one `F13` obligation per new app suite, or the suite never runs |
| A2 | Nothing | Deferred |
| A3 | Nothing | The file list is the same; the accessor in `ScribeCallWatcher.swift` is narrowed to one property, and four security files are named as not to be edited |
| A4 | Nothing | The file list is the same |

A1 and A3 both edit `GlanceSettingsPages.swift`, `TopBarServices.swift` and the generator; with the order now one
after the other, A3 builds on A1's version and there is no merge between them.

### Verification, added to the list above

- Pinned and expected to pass unchanged, beside the suites in step 2: `LyricsFlowTests`, `LyricsMatchingTests`,
  `LyricsHardeningTests`, `LyricsLimitsTests`, `LyricWordsTests`, `LyricsRetryTests`, `MusicModePressTests`,
  `MusicAwakeTests`, and in the app target `MusicAwakeHoldTests`, `LiveDiagnosticsCardTests`,
  `NotchDebugAnimatorTests` and `ChromeBridgeHintTests`.
- `python3 -m unittest discover -s qa/closed-loop/tests` runs the island lints, which are new, and the checks of
  `qa/feature-map.json`; both must pass after A1's rows are added.
- On a Mac, added to step 6: the two A3 measurements (one `ping`, the bridge's CPU while polling); the hold taken
  for a playing tab and released after a pause; a refused bridge (switch build kind without restarting Chrome)
  giving back-off and no browser entry; play and pause on Music and on Spotify each followed by the read-back.

### What stops a ticket from being built now

- A1: nothing stops the build. One owner decision is still open and changes its base capability set: whether
  Spotify loses shuffle and repeat until checked (point 7).
- A4: waits for A1 to merge, by the order. Nothing else.
- A3: waits for A1 and A4 to merge, by the order. Its acceptance on a Mac needs a bundled app and bridge of the same
  build kind, and the cost of the signature check under polling is not measured yet. `ScribeCallWatcher.swift` is
  being rewritten elsewhere, so the one property is written against whichever version has merged.
- A2: deferred. Step zero needs a person at the Mac.

## Review notes

Changed after review: socket outcomes told apart, a pure poll reducer that backs off while Chrome runs; an element
rule, fingerprint and call exclusion; dictation bound to one source; the lint matched to the real files (voice intents
live in `Intent/`); an output gate, no polling under a pin; per-tab budgets, single flight, one injection per read;
A2 on the existing probe behind a step zero; owners for settings, the page hook and Open; no disk for browser covers
or lyrics, incognito skipped; seek, voice "play" and Spotify-check rows; player lyrics unchanged; Spotify modes hidden
until checked; hub and poll tests; one artwork URL; every minor. Fail closed now ends each ticket without a heading.

- Arbiter mismatch is rejected (returns false) rather than a precondition, so a test can cover it without a trap.
- `ScribeCallWatcher` runs only with Scribe (`ScribeController.swift:436`): the `MediaStream` rule is the main guard.
- `ArtworkStore.script` is worse than reported (in process, on the main actor), but it is today's behaviour and its
  Music fallback returns raw bytes the text-only runner cannot carry. Named as an exception, not changed here.
- Hiding Spotify's shuffle and repeat changes what M1 draws, so it is also an owner decision.
