# Native acceptance: top bar playback

Click-by-click check of a packaged Zeus.app on a Mac. One operator, or one click driver. Compare each visible result to the screen before the next click. The run never asks for a permission and never presses Allow.

## Permissions already granted

Set these before the run. If any of them is missing, stop. Do not continue into a consent sheet.

| Who | TCC | Target | When |
| --- | --- | --- | --- |
| Packaged Zeus, bundle id `app.zeus.mac` | Automation | Music, bundle id `com.apple.Music` | On for sections A and B. Off for section D. |
| The process that runs the `osascript` checks below (Terminal, or the click driver) | Automation | Music, bundle id `com.apple.Music` | On for the whole run. The player-state check is itself an Apple Event. |
| The click driver, only if it clicks through the Accessibility API | Accessibility | That driver process | On before the first click. A person using the pointer does not need this. |

Zeus does not need Accessibility for these controls. Do not call the prompt form of the trust check. Do not press Allow, Allow more, or any System Settings toggle during a step. Section D uses a grant that was turned off before that section starts.

## What to watch

Player state, only while Music is already running:

```sh
osascript -e 'tell application "Music" to player state'
```

The answer is `playing`, `paused`, or `stopped`.

While Music is quit, do not run that tell. It launches Music. Use this instead, which does not launch it:

```sh
osascript -e 'application id "com.apple.Music" is running'
```

The answer for section C is `false`.

Track name, used only to tell next from previous. Same process, same grant:

```sh
osascript -e 'tell application "Music" to name of current track'
```

Log. Start it before the first click and leave it running:

```sh
log stream --style compact --predicate 'subsystem == "app.zeus.mac" AND category == "media-playback"'
```

Subsystem `app.zeus.mac`. Category `media-playback`. Each expected line is the message text, once, at notice level. A step fails if that line is missing, if it appears twice, or if a `permissionDenied` line appears in a step that expects `accepted`.

## Before any click

1. Quit Zeus if it is open. Launch the packaged app. Confirm no consent sheet appears.
2. Home slot 1 is the playback card (the default). The open trigger is Hover (the default).
3. Music is running. A song is playing. The queue has a different track before this one and a different track after it. Neither end of the queue is the current track.
4. Read the track name with the command above. Call it Track A. The card title in later steps is this string, one line, white, ending in an ellipsis only if the name does not fit.

## Open the panel

### Step 0

- Action: move the pointer onto the notch at the top centre of the screen and hold it there until the panel opens. If the selected tab's pill does not show the word Home, click the Home tab (`notch.tab.home`).
- Visible: the panel is open. The selected pill shows the word Home in white. The leftmost card shows a 48 pt cover, the title Track A in white, the artist under it in dimmer white, a dark circle with a white previous glyph, a white disc with a black two-bar pause glyph, and a dark circle with a white next glyph. No line reads "Nothing is playing" or "Playback controls need permission."
- Player state: `playing`.
- Log: none for this step.

## A. Play, pause, next, previous

Music stays running. The Automation grant for Zeus stays on.

### A1. Pause

- Action: click the white disc on the leftmost card (accessibility label Pause).
- Visible: within about a second the same disc shows a black right-pointing triangle. The title is still Track A. The previous and next circles stay. The guidance lines stay absent.
- Player state: `paused`.
- Log: `command pause accepted bundle=com.apple.Music`

### A2. Play

- Action: click the white disc (accessibility label Play).
- Visible: the disc returns to the black two-bar pause glyph. The title is still Track A.
- Player state: `playing`.
- Log: `command play accepted bundle=com.apple.Music`

### A3. Next

- Action: read the track name and call it Track A. Click the dark circle on the right of the disc (accessibility label Next track).
- Visible: the title changes to a different name, Track B, the name now returned by the track-name command. The disc still shows the two-bar pause glyph. The artist line updates to Track B's artist.
- Player state: `playing`. Track name is Track B, and Track B is not Track A.
- Log: `command next accepted bundle=com.apple.Music`

### A4. Previous

- Action: click the dark circle on the left of the disc (accessibility label Previous track).
- Visible: the title returns to Track A. The disc still shows the two-bar pause glyph.
- Player state: `playing`. Track name is Track A.
- Log: `command previous accepted bundle=com.apple.Music`

## B. Rapid double-tap

Start from A4. Music is playing Track A. Click pause and wait until A1's log line has appeared and the disc shows the triangle, so the next clicks are Play. Player state is `paused`.

### B1. Two plays

- Action: click the white disc, then click it again before the black glyph changes from the triangle to the two bars. Do not wait between the clicks. If the glyph has already become two bars, the step was too slow. Pause again, wait for `command pause accepted bundle=com.apple.Music`, and repeat this step.
- Visible: after both clicks settle, the disc shows the two-bar pause glyph once. It does not return to the triangle. The title stays Track A.
- Player state: `playing`. One change, from `paused` to `playing`. A second read a second later is still `playing`.
- Log, in this order, one of each: `command play rejected inFlight`, then `command play accepted bundle=com.apple.Music`. No second `accepted` line.

## C. No player open

### C1. Quit Music

- Action: run `osascript -e 'tell application "Music" to quit'`. Wait until the leftmost card's title is the words Nothing playing. Do not click the disc before that.
- Visible: the title is Nothing playing. Under it, one dimmer line reads "Nothing is playing. Start playback, then these controls follow it." The white disc shows the triangle. The previous and next circles are still there.
- Player state: do not run the player-state tell. `application id "com.apple.Music" is running` is `false`.
- Log: none for the quit itself.

### C2. Play with nothing open

- Action: click the white disc (accessibility label Play).
- Visible: the title stays Nothing playing. The guidance line stays. The disc stays a triangle. It does not become two bars.
- Player state: `application id "com.apple.Music" is running` is still `false`.
- Log: `command play nosource`. No `accepted` line and no `permissionDenied` line.

## D. Automation permission denied

Prepare before the first click of this section. Turn Zeus's Automation grant for Music off in System Settings. Open Music from the Dock and start Track A playing. Do not press Allow anywhere. Relaunch the packaged Zeus.app if it was quit, and confirm no consent sheet appears.

### D1. Pause while denied

- Action: open the panel as in step 0. The leftmost card shows Track A and the two-bar pause glyph. Click that disc once (accessibility label Pause).
- Visible: the title stays Track A. A dimmer line reads "Playback controls need permission." The disc's glyph is the triangle. Its accessibility label is Allow playback control. The notch does not show a consent sheet.
- Player state: `playing`. Track name is still Track A.
- Log: `command pause permissionDenied`. No `accepted` line.

### D2. Recovery

- Action: click the same white disc once (accessibility label Allow playback control). Do not click Allow or Allow more.
- Visible: the notch panel closes. The front window is Zeus Settings, title bar hidden, window title Zeus Settings. The sidebar selection is Permissions. The page title is Permissions. The subtitle is "What macOS lets ZEUS do. ZEUS only asks from here or during setup." The Automation row is on that page. No consent sheet is attached to it.
- Player state: `playing`.
- Log: `recovery opened`.
