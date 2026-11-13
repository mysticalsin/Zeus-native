# Notch music upgrades: plan and design

Written 13 November 2026 on `codex/island-20261113`, cut from `codex/integration-20261111` at `d3a2e43`.
This is the spec, design note and task list for the first wave of music work in the notch. It follows
`docs/DESIGN-DIRECTION.md` and the pure-rules-in-ZeusCore pattern used by `KeepAwakeRules` and `PermissionSweep`.
Nothing here is accepted until the named tests run on macOS and the behaviour is seen on a Mac.

## What the owner asked for

Zeus's notch should do what the notch-island utility category does for music. A survey of that category against
Zeus at `d3a2e43` found these gaps in the music area. This wave closes the four that need only public interfaces:

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| M1 | Shuffle and repeat | Play, pause, next, previous and scrub only | Shuffle on or off; repeat off, all or one (Music), off or all (Spotify) |
| M2 | Lyric matching and polite failure | One strict request, one loose request; a failed request looks like "no lyrics" | Version suffixes no longer hide lyrics; a duration check guards against the wrong version; a service failure says so and backs off |
| M3 | Word by word lyrics | The current line lights as a whole | Each word of the current line lights as it is sung, from estimated timing, with a setting |
| M4 | Keep the display awake while music plays | Timed keep-awake sessions only | An optional hold that lasts only while music plays, with the same battery and heat rules |

Later waves (separate plans): more now-playing sources (browser tabs through the Zeus extension, a system-wide
source), headphone status, a per-app equaliser, lock screen surfaces, rounded bottom corners, live diagnostics.

## Open source checked first

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| Title clean-up rules | web-scrobbler/metadata-filter | MIT | Port a small subset of its suffix rules, credited in `NOTICES.md` |
| Retry and back-off policy | tranxuanthang/lrcget | MIT | Follow its status mapping and Retry-After handling as a technique; no code copied |
| Search-then-check ordering | beetbox/beets (lyrics plugin) | MIT | Technique only: rank search results by duration distance |
| Estimated word timing | tangyunpei/AlpacaMusic | MIT | Technique only: weight words by syllables, one unit per CJK character |
| Syllable counting | words/syllable | MIT | Technique only: vowel groups, at least one per word |
| Player scripting | The Music and Spotify scripting dictionaries on the Mac | n/a | `shuffle enabled`, `song repeat`, `shuffling`, `repeating` |

Projects under GPL or AGPL in this space were read for technique only and none of their code is used.
No new package dependency is added in this wave.

## Privacy and consent (unchanged rules)

- Lyrics stay off until `privacy.lyrics` is on. Requests still carry only title, artist, album and duration to lrclib.net.
- Apple Events never prompt from the music path. Every new script goes through `Automation.allowed`, talks only to a
  player that is already running, and runs out of process through `SpotifyPlayer.osascript` with its timeout.
- No capture, no new permission, no new entitlement.

## M1. Shuffle and repeat

### Behaviour

- The Music page shows two more controls beside the transport: Shuffle (left of Previous) and Repeat (right of Next).
- Shuffle toggles on and off. Repeat cycles off, all, one, off for Music and off, all, off for Spotify, whose
  scripting interface has no repeat-one.
- The controls show what the player reports. Until the player has answered (no Automation consent, player not
  running, unknown player) they are drawn subdued. A press then takes the existing path: the Automation hint.
- A press updates the control at once, sends the change, then reads the modes back and corrects the control if the
  player disagrees.
- Modes are read again when the player or the track changes. Never on a timer.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/MusicModes.swift`:

- `RepeatMode`: `off`, `all`, `one`.
- `MusicModes`: `shuffle: Bool?`, `repeatMode: RepeatMode?`. Nil means the player has not said.
- `MusicModeRules.supportedRepeatModes(_ player)`: Music `[off, all, one]`, Spotify `[off, all]`.
- `MusicModeRules.nextRepeat(after:player:)`: the next supported mode; nil counts as off; an unsupported current mode goes to off.
- `MusicModeRules.readScript(player:)`: one AppleScript expression. It returns an empty string when the player is not
  running (the `is running` check comes first, as in `NowPlaying.probeScript`), otherwise shuffle and repeat joined by
  `NowPlaying.probeSeparator`.
- `MusicModeRules.parse(_ output:player:)`: Music answers `true|false` and `off|one|all`; Spotify answers two booleans
  (`repeating` true is `all`). Empty, malformed or unknown answers give nil. Case is ignored.
- `MusicModeRules.setShuffleScript(player:on:)` and `setRepeatScript(player:mode:)`: `one` on Spotify sets repeating on.

State lives in `TopBarModel.musicModes` (a `MusicModes`), not inside `NowPlaying`, so a playback notification can
never wipe it. It resets to unknown when the player changes or playback stops.

### Design

- Same `GlyphButton` family and size as Previous and Next, symbols `shuffle`, `repeat`, `repeat.1`.
- On is shown by shape and by value, not by colour alone: a filled capsule behind the glyph, and the accessibility
  value "on", "off", "all" or "one". Labels: "Shuffle", "Repeat".
- Unknown is subdued (the secondary cloud tone at reduced opacity), still focusable, still pressable.
- No motion beyond the shared press feedback. Nothing changes with Reduce Motion.

### Tests first (`Tests/ZeusCoreTests/MusicModesTests.swift`)

1. Music answers parse: `true` + `all`, `false` + `off`, `true` + `one`.
2. Spotify answers parse: `true` + `true` is shuffle on, repeat all; `false` + `false` is off, off.
3. Empty, one field, unknown words and nil give nil.
4. Repeat cycle for Music and for Spotify, including nil and an unsupported current mode.
5. Every script names the player by bundle id; the read script checks `is not running` before the `tell`.
6. Set scripts carry the right property and value for each player and mode.

## M2. Lyric matching and polite failure

### Behaviour

- A track whose title carries a version suffix ("- Remastered 2011", "(Deluxe Edition)", "- Single Version",
  "(feat. Someone)") finds the lyrics of the song.
- Lyrics timed for a different recording are refused: a candidate must be within 2 seconds, or 3 percent of the
  track length if that is larger, of the playing track when its length is known.
- Live recordings keep their own title: "Live" is never stripped.
- When the lyrics service fails (no network, HTTP 429, HTTP 5xx) the view says the service is not answering. It
  does not say the track has no lyrics, and nothing is cached. Zeus then waits before asking again: 30 seconds,
  doubling to a ceiling of 15 minutes, or the server's Retry-After when it sends one. A success clears the wait.
- While waiting, a new track does not cause a request. When the wait ends and the same track is still current,
  Zeus asks once.

### Lookup order

1. `GET /api/get` with the raw title, artist, album and rounded duration (today's strict request).
2. On 404, and only when clean-up changed something: `GET /api/get` with the cleaned title, the first credited
   artist and the duration, without the album.
3. On 404: `GET /api/search` with the cleaned title and first artist; pick with `LyricsMatch.best`.

The old "loose" request without a duration is removed: it could return another recording's timing.

### Rules (ZeusCore, pure)

- `LyricsTitle.stripped(_:)` and `LyricsTitle.primaryArtist(_:)` in a new `Sources/ZeusCore/Lyrics/LyricsMatching.swift`.
- `LyricsCandidate` (id, title, artist, duration, instrumental, synced text, plain text) and
  `LRCLIBResponse.parseSearch(_:)`.
- `LyricsMatch.best(_ candidates:duration:)`: synced before plain, inside the duration window, then nearest duration.
  With an unknown duration (0) only an exact title match, ignoring case, is taken.
- `LyricsRequest` values for the three steps, built by `LRCLIBQuery`, so URL building stays testable.
- `LyricsBackoff` (failures, blocked-until, `recordFailure(now:retryAfter:)`, `recordSuccess()`, `canAsk(now:)`).
- `LyricsFetchOutcome`: `found`, `notFound`, `failed(retryAfter:)`, and `LyricsStatus.outcome(status:retryAfter:)`
  mapping HTTP status codes.

The cache key is unchanged, so lyrics already on disk stay valid.

### Design

- New `LyricsStore.State.unavailable`. Copy: title "Lyrics service is not answering", detail "Zeus will try again
  shortly." Same `note` layout as the other states.
- "No synced lyrics for this track" now means the service answered and had none.

### Tests first

`Tests/ZeusCoreTests/LyricsMatchingTests.swift`: a table of titles and artists through the clean-up rules (including
titles that must not change), candidate ranking and the duration window, search response parsing, the three request
URLs, the status mapping, and the back-off sequence with and without Retry-After.

## M3. Word by word lyrics

### Behaviour

- In the lyric views the current line lights one word at a time. Words already sung are bright, the word being sung
  is bright, words to come are dim. Other lines are unchanged.
- Timing is estimated from the line timing: a line's sung span is shared among its words by how long each takes to
  sing. On a long gap before the next line the words finish early and the line stays lit.
- Setting `lyrics.wordByWord` (Appearance, Everyday lights), on by default: "Light lyrics word by word". Note:
  "Each word lights as it is sung. Word timing is estimated from the line timing." Off restores whole-line lighting.
- Inline word tags in a lyric file (`<mm:ss.xx>`) no longer appear as text.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Lyrics/LyricWords.swift`:

- `LyricWord`: text, start, end.
- `LyricWordTiming.units(_ word:)`: vowel groups for Latin script, one per CJK character, never less than one;
  punctuation alone counts as nothing.
- `LyricWordTiming.words(in line:lineEnd:)`: sung span is `min(lineEnd - line.time, max(1.0, units * 0.45))`.
  Text without spaces in CJK script is split per character. An empty line has no words.
- `LyricWordTiming.index(_ words:at:)`: the word being sung, nil before the first, the last after the span.
- `LyricWordTiming.nextChange(_ words:after:)`: the next time the lit word changes, or nil.
- `LRC.parse` strips inline word tags from the text.

### Design

- The current row is one `Text` built from word runs, so wrapping, `lineLimit(2)` and the fixed row height are the
  same as today. Sung and current words use the current-line white; words to come use the next-line tone.
- The view wakes at word changes, not on a fast timer: it asks `nextChange` and sleeps until then. Nothing runs while
  paused, off screen, in snapshots, or when the setting is off (the existing once-a-second tick remains for line changes).
- Reduce Motion: words change state without a fade.
- VoiceOver still reads the whole current line once per line, never per word.

### Tests first

`Tests/ZeusCoreTests/LyricWordsTests.swift`: unit counts ("hello" 2, "the" 1, "beautiful" 3, "rhythm" at least 1,
"!" 0, a kana and a kanji string), shares that sum to the sung span, the cap on a long gap, a one-word line, an empty
line, index and nextChange at and between boundaries, CJK splitting, and tag stripping in `LRC.parse`.

## M4. Keep the display awake while music plays

### Behaviour

- Setting `keepAwake.whileMusic` (General, Day to day), off by default: "Keep the display awake while music plays".
  Note: "Holds the display on only while Music or Spotify is playing. Stops on low battery or heat."
- While on and a track is playing, Zeus holds a display-sleep assertion. A pause or a gap between tracks shorter than
  20 seconds does not drop it.
- The existing battery floor and heat rule apply. On battery below the floor, or at the hot level, the hold is released
  and is not taken again until power or heat recovers.
- It is separate from keep-awake sessions and the Home cup: it never extends, shortens or ends them.
- The assertion has a two-minute lease renewed each minute, so a hung Zeus cannot keep the display on.
- A locked screen is not treated specially in this wave: music playing after a lock keeps the lock screen lit until it
  stops or a battery or heat rule trips. If that is unwanted, add a `screenLocked` input to `MusicAwakeRule.decide`
  fed by the `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/MusicAwake.swift`:

- `MusicAwakeRule` with `grace: TimeInterval = 20`.
- `decide(enabled:isPlaying:lastPlayedAt:now:power:rules:)` returns `.hold` or `.release(reason)` with reasons
  `off`, `notPlaying`, `lowBattery(Int)`, `tooHot`. Charging or AC overrides the battery floor, as in `KeepAwakeRules`.

App side: `MusicAwakeHold` (main actor) owns its own assertion and is driven by playing changes on `TopBarModel`
(one new closure seam beside `onKeepAwake`), a grace timer, power changes and the setting.

### Tests first (`Tests/ZeusCoreTests/MusicAwakeTests.swift`)

Playing holds; a pause inside the grace holds; beyond it releases; off releases; below the floor on battery releases
with the percent; charging below the floor holds; the hot level releases; a floor of 0 never releases for battery.

## Settings and catalog

New rows go in the table in `scripts/gen-settings-catalog.py`; `SettingsCatalog.swift` and the inventory are
regenerated, never edited by hand. `scripts/check-settings-catalog.sh` must pass.

## Verification for this wave

1. Tests are committed before the code and shown failing on the base (the build fails on the missing names).
2. `swift build --build-tests` then `swift test --filter` for each new suite.
3. The whole `ZeusCoreTests` module on the branch and on the base, compared. The base at `d3a2e43` has 4 failing
   cases, all in "Native host process boundaries" (a missing helper binary in a tests-only build).
4. `./tools/check.sh` development mode.
5. An independent review of each diff.
6. Not covered by this wave's automated checks, and still owed: the real players answering the new scripts on a Mac
   with Automation granted, word lighting judged by eye against a known song, and the display assertion seen in
   `pmset -g assertions` while a track plays.
