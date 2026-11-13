# Notch now-playing sources: plan and design

Written 13 November 2026 against `codex/island-20261113` (HEAD `47566d1`). Third wave after `docs/NOTCH-MUSIC-PLAN.md`
and `docs/NOTCH-SURFACE-PLAN.md`. Both are assumed merged before this is built: `TopBarModel.musicModes` and the two
mode cases on `MusicCommand` (M1), lyric matching (M2), word lighting (M3), the display hold while music plays (M4),
open on click (S1), rounded corners (S2) and live diagnostics (S3). Nothing here redoes them. Same rules: pure rules in
ZeusCore with tests first, `docs/DESIGN-DIRECTION.md` for anything visible, nothing accepted until the named tests run
on macOS and the behaviour is seen on a Mac. Public interfaces only. Line numbers below were read on `47566d1`.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| A1 | One source model | A closed two-case `Player` and hidden "not Music means Spotify" defaults | A source value with capabilities, one rule for what is shown, a setting to follow any source or pin a player |
| A2 | Music position after a change | Music's notification has no position, so progress, lyrics and word lighting drift after a seek | The existing probe re-run, coalesced and bounded, once step zero shows when it is needed |
| A3 | Browser media | Not shown | Media in Chrome tabs, read and controlled through the Zeus extension and bridge |
| A4 | Source on screen | No source name; every control drawn for every player | The source is named, and controls a source cannot honour are not drawn |

Worktrees and order:

| Ticket | Files it owns | Runs |
| --- | --- | --- |
| A1 | `NowPlaying.swift`, `Artwork.swift`, `Lyrics.swift`, new `NowPlayingSource.swift`, new `NowPlayingArbiter.swift`, `TopBarServices.swift` (music block out), new `MusicPlayerFeed.swift`, new `NowPlayingHub.swift`, `ArtworkStore.swift`, `LyricsViews.swift`, `TopBarModel.swift`, `TopBarViews.swift` (`:111`, `:567`, the Music page appear hook), `FastActions.swift`, `DictationController.swift`, `GlanceSettingsPages.swift` (new Music group), the S3 call site, new `Tests/ZeusAppTests/NowPlayingHubTests.swift`, generator row | First, alone |
| A2 | `MusicPlayerFeed.swift`, new `ZeusCore/TopBar/PositionReread.swift`, its tests | Step zero on a Mac first; then after A1, parallel with A3 and A4 |
| A3 | `extension/**`, `UnixSocket.swift`, `ChromeBridge.swift`, `ChromeInstaller.swift`, new `Chrome/BrowserMediaFeed.swift`, new `Chrome/ChromeOutputActivity.swift`, new `ZeusCore/TopBar/BrowserMedia.swift`, new `ZeusCore/TopBar/BrowserPollMachine.swift`, one accessor in `ScribeCallWatcher.swift`, one line in `TopBarServices.start`, `SettingsStore.swift` (import list, `SettingStatus`), `GlanceSettingsPages.swift` (privacy row), `test_source_lint.py`, generator row | `extension/**` may start at once; the rest after A1 |
| A4 | `TopBarViews.swift`, `HomeWidgetViews.swift`, `NowPlayingHub.swift` (cue only), `TopBarLayout.swift`, `SnapshotRenderer.swift` (new fixtures), new `ZeusCore/TopBar/NowPlayingDisplay.swift` | After A1, parallel with A2 and A3 |

Only A1 edits routing in the hub; A3 and A4 call it. Every branch appends to `qa/regressions.json` (claim a decade
block at merge; REG-410 is next here and the two waves in flight take the first blocks; clashes go through
`~/AI-Brain-build/zeus-merge-reg.py`; feature `F13`, as in `qa/extension-regressions.json`) and the generated settings
files (re-run the generator on the merged table; never hand-merge `SettingsCatalog.swift` or the inventory).

## Open source checked first

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| One controller per source behind one model | TheBoredTeam/boring.notch | GPL-3.0 | Technique only. No code is read into Zeus |
| Which source counts as playing | servitola/nowplayingseek | AGPL-3.0 | Technique only: the most recent starter is elected and kept a while after a pause. Zeus's rule is its own |
| Bounded player reads | justinmdickey/goplaying | MIT | Technique only: a 3 s bound, the `is running` check before the tell, one read in flight |
| Media session read and native host plumbing | JosephusPaye/chrome-media-controller | MIT (stated on the repo page; read the file before any reuse) | Technique only: read media session metadata and the media element |
| Notification keys | rwijnen/cuecard | MIT | Already matched by `NowPlaying.parse`; nothing new |
| System-wide source | ungive/mediaremote-adapter | BSD-3-Clause | Not used. It needs a private framework; see "Out of scope" |
| Reading rules | Media Session spec, Chrome extension scripting docs | n/a | Only `metadata` and `playbackState` are readable; position comes from the media element; ISOLATED and MAIN worlds |

No code is copied and no dependency is added. GPL and AGPL projects were read for technique only.

## Privacy and consent

- No capture, no new OS permission, entitlement or manifest permission; nothing prompts. No test touches TCC (tests set
  `Automation.testStatusProvider`), a real Chrome (`node:vm`) or the network (a stub `URLProtocol`). The output gate
  reads Core Audio process flags, which never prompt and carry no audio, as `ScribeMicActivity.swift` does.
- A2 reuses Music's consent via `Automation.allowed` (`PermissionsModel.swift:343`): without it nothing runs, no hint.
- Browser media is off until the owner turns on `music.browserMedia` (in `SettingsStore.neverEnabledByImport`,
  `SettingsStore.swift:256-259`). It reads media metadata, playback state and the chosen element's numbers, never page
  text, and skips incognito and discarded tabs. The tab URL stays in memory only, never logged, stored or shown.
- Calls are never a source: a `MediaStream` element is not a candidate (A3), and while `ScribeCallWatcher` runs and
  reports a browser call, the feed drops browser entries and refuses browser commands.
- Browser media never reaches a model, voice, chat or agent context. Logs and diagnostics carry the kind ("Chrome"),
  codes and counts, never a host or title. `AudioSpectrumService.setMusicPlaying` (`TopBarModel.swift:129`) now
  follows browser playback too; it never asks.
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
- The track cue (`TopBarServices.swift:165-167`) fires as today, on the shown item. With one player, Music and Spotify
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

`NowPlaying` (`NowPlaying.swift:5-123`): `Player` (`:6`) gains `CaseIterable`. The stored `player` (`:34`) becomes
`source: NowPlayingSource`, so every read of `.player` fails to compile, which is how each hidden default is found;
`init(player:...)` stays, so the fixtures at `SnapshotRenderer.swift:589`, `:826`, `NotchDebugAnimator.swift:62` and the
tests still compile. New `rate = 1` (`elapsed(at:)`, `:113-116`, multiplies by it) and `artworkURL`. New
`capabilities`: the base set, minus `seek` when `duration == 0`; for a player `lyrics` holds exactly when
`LRCLIBQuery(self).isAskable` (`Lyrics.swift:89`), as today; a browser item also needs a duration. `parse` and
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
| `TopBarViews.swift:111` | Not Spotify draws the note glyph | A switch on `source` (A4 swaps in `NowPlayingDisplay.glyph`) |
| `TopBarViews.swift:567` | `player.rawValue ?? "Music"` | `source.kindName`, and the command target when nothing is shown |
| `TopBarServices.swift:95`, `:122` | Loops over `[.music, .spotify]` | `NowPlaying.Player.allCases` |
| `TopBarServices.swift:151` | A probe skips if another player plays | Removed: each source updates its own entry; the arbiter decides |
| `TopBarServices.swift:168` | Clears only if the same player | `arbiter.update(source, nil)` |
| `TopBarServices.swift:176-194` | Seek: `playing.player`, in-process `NSAppleScript`, Automation hint | Through the hub: a player seek runs `MusicSeek.script` via `SpotifyPlayer.osascript`; a browser seek is `media.command seek`; the hint only for players |
| `TopBarServices.swift:214` | `?.player ?? .music` | `NowPlayingArbiter.commandTarget` |
| `FastActions.swift:81` | `hasSession: topBar?.nowPlaying != nil` | `hub.hasPlayerSession`, so a shown tab never stops voice "play" resuming Spotify |
| `FastActions.swift:291` | Shown item `player == .spotify` | `hub.entry(.player(.spotify))?.isPlaying`, so a Music pin cannot hide Spotify's state |
| `DictationController.swift:608-610`, `:1066-1069` | Blind `.playPause` on pause and on resume | `pauseForDictation()` and `resumeAfterDictation(_:)` (below) |
| `ArtworkStore.swift:122-125` | Switch on player | Switch on `artworkStrategy`; the player fallback scripts (`:140`, `:152`) and `Automation.players` (`PermissionsModel.swift:328`) stay |

### App side

- `TopBarServices.swift:91-194` and `:214-245` (not output devices, `:196-212`) move to a new `MusicPlayerFeed.swift`
  with M1's mode reads, reporting to the hub. The seek moves to the bounded `SpotifyPlayer.osascript` (`:98`).
- New `NowPlayingHub` (main actor) owns the arbiter and follow setting, writes `model.nowPlaying`
  (`TopBarModel.swift:128`) only when it differs, raises the cue, requests artwork, and routes `musicCommand` and
  `seek` (wired at `TopBarServices.swift:41-42`). Browser commands go to an optional `browserCommand` closure (A3);
  nil does nothing. After any command it updates the entry at once, as `TopBarServices.swift:239-243` does today.
- Dictation: the hub sets `TopBarModel.pauseForDictation: () -> NowPlayingSource?` (an explicit `pause` to the shown
  playing source, which `DictationController` keeps instead of `pausedMedia`) and `resumeAfterDictation(_:)` (an
  explicit `play` to that same source only if its entry still exists and is paused; never the fallback target).
- `TopBarModel.musicPageVisible` is set by the Music page's appear and disappear in `TopBarViews.swift`; the hub's
  `observeMusicPage(_:)` lets A2 and A3 register from their own files. `musicModes` (M1) resets when the source changes.
- `ArtworkStore.load` (`:116-131`): `pageImage` returns before the disk read (`:117`) and never calls `save` (`:127`).
  It streams with `session.bytes(from:)`, rejects a `Content-Length` over 2 MB and stops at 2 MB, keeps the 8 s
  timeout, and a task delegate refuses any non-`https` redirect. `ArtworkSource.pageImageAllowed(_:)`: `https` only,
  no IP literal, no `.local` or `localhost`.
- Lyrics: `LRCLIBQuery` (`Lyrics.swift:84`) is unchanged. `LyricsStore.load` (`LyricsViews.swift:47`) asks only with
  the `lyrics` capability, else `.none` as today; without `persistsDerivedData` it skips `cache.load` and `cache.save`.
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

## A2. Music position re-read

### Step zero, on a Mac, before A2 is scheduled

`NowPlaying.probeScript` and `parseProbe` (`NowPlaying.swift:85-111`) already read state, title, duration and `player
position` behind the `is not running` guard, and `syncMusic` (`TopBarServices.swift:140-159`) drops stale answers via
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
  `TopBarServices.swift:107-119`). Screen sleep pauses it.
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
cross. `ScribeCallWatcher` gains a read-only `browserCallPresent`; the feed never starts the watcher. Lint in
`test_source_lint.py`: the literal `"media.command"` appears in `Sources/Zeus` only in `Chrome/ChromeBridge.swift`;
`ChromeBridge.mediaCommand(` is called only from `Chrome/BrowserMediaFeed.swift`; `Chrome/ChromeActions.swift`,
`ZeusCore/ZeusTag.swift`, `ZeusCore/BrowserCommand.swift`, `Zeus/Intent/**` and `Zeus/Voice/**` never mention either.
One fail-first sample per shape, as in `test_pointing_lint_detects_its_failure_shapes`.

### Shipping the extension

- `extension/manifest.json`: 0.4.0 to 0.5.0. Permissions unchanged: `tabs`, `scripting` and `<all_urls>` already
  cover `tabs.query({audible})` and both worlds. `package.json` stays 0.1.0 (not tied to the manifest).
  `scripts/bundle.sh:54-60` copies the build into the app, and `AppDelegate.swift:205-210` refreshes the unpacked copy
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
- Closed notch: the wing width does not change (`ClosedWings.extraWidth`, `TopBarViews.swift:1452`). The tile's
  placeholder glyph and the cue glyph (`TopBarViews.swift:1484`, always `music.note` today) follow the source. When the
  shown source changes the cue reads "Spotify · Title"; within one source it keeps "Title · Artist" (`:1543`).

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
| `music.browserMedia` | Privacy, Music card (`GlanceSettingsPages.swift:1118`) | Toggle: "Show media playing in Chrome". Note: "Reads title, artist and position from Chrome tabs through the Zeus extension. Covers load from the page's own image link and are not saved. Calls are never shown." | Off, never enabled by import | A3 |
| `music.browserMediaStatus` | Under that toggle | `SettingStatus` row: the reload hint while the extension is older than 0.5.0 | n/a | A3 |
| `keepAwake.whileMusic` | M4's row | Note only: "Holds the display on only while the source shown in the notch is playing. Stops on low battery or heat." | Unchanged | A1 |

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
  can close, on notarizing an embedded framework, and on a watchdog.
- Tab next and previous, and embedded frames, by a script injected into every page (code in every page). Media keys as
  a fallback (needs Accessibility). Other browsers (host folders not verified).

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the missing names).
2. `swift build --build-tests`, then `swift test --filter` for `NowPlayingArbiterTests`, `NowPlayingSourceTests`,
   `PositionRereadTests`, `BrowserMediaTests`, `BrowserPollMachineTests`, `NowPlayingDisplayTests`,
   `UnixSocketSafetyTests`, `NowPlayingHubTests`, `PageArtworkDiskTests`, and the pinned `W8NowPlayingTests`,
   `NowPlayingTests`, `ArtworkTests`, `MusicSeekTests`, `LyricsTests`, `MusicModesTests`, `LiveDiagnosticsTests`.
3. `cd extension && npm run typecheck && npm test && npm run build`.
4. The whole `ZeusCoreTests` module on the branch and the base, compared (4 known failures in "Native host process
   boundaries"). The settings generator and its check; `python3 -m unittest discover -s qa/closed-loop/tests`.
5. `./tools/check.sh` development mode, from a worktree under `~/AI-Brain-build`. An independent review of each diff.
6. Still owed on a real Mac: A2 step zero; Music and Spotify in turn, both pins; Spotify shuffle and repeat set by
   script and read back; dictation pausing a tab and resuming that tab, never Music; the ISOLATED metadata spike; play,
   pause, seek on a tab; a reload then a tap changing nothing; a video call tab never shown or paused; an ad element;
   Chrome quit stopping the loop (`zeus-bridge` gone); the reload hint; idle CPU with the toggle on and nothing playing
   (`scripts/check-perf-budget.sh`); a page cover shown, absent from the artwork cache, gone after relaunch.

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
