# Notch surface upgrades: plan and design

Written 13 November 2026 on `codex/island-20261113`. Second wave after `docs/NOTCH-MUSIC-PLAN.md`. Same rules:
pure rules in ZeusCore with tests first, `docs/DESIGN-DIRECTION.md` for anything visible, nothing accepted until
the named tests run on macOS and the behaviour is seen on a Mac. All three tickets use public interfaces only and
add no permission.

| Ticket | Gap | Today | After |
| --- | --- | --- | --- |
| S1 | Open on click | The notch opens only by hovering | A setting chooses Hover or Click |
| S2 | Rounded bottom corners | None | An optional click-through overlay rounds the two bottom corners of a notched display |
| S3 | Live diagnostics | A log and an export | A card with Zeus's own CPU, memory, heat and audio state, and a Copy button |

## Open source checked first

| Need | Project | Licence | Use |
| --- | --- | --- | --- |
| Click and hover state for a notch panel | Lakr233/NotchDrop | MIT | Technique only: open on click inside the notch rect, close on outside click |
| Corner overlays | nisesimadao/Rounder | MIT | Technique only: one small click-through window per corner, rebuilt on screen changes |
| Overlay panel flags | Apple developer forum guidance for full-screen overlays | n/a | Non-activating panel, joins all Spaces, full-screen auxiliary |
| Own-process CPU and memory | exelban/stats | MIT | Not used: it reads system-wide values; Zeus already samples its own process in `EnergyMonitor` |

No code is copied and no dependency is added.

## S1. Open on click

### Behaviour

- Setting `notch.openTrigger` (Appearance, Notch behavior, directly after `notch.openDelay`): "Open the notch on",
  choices `Hover` and `Click`, default `Hover`. Note: "Hover opens it after the delay. Click opens it only when you
  click the notch."
- `Hover` is today's behaviour, unchanged in every detail.
- With `Click`, hovering the notch does not open the panel. A left click inside the click zone opens it. Closing is
  unchanged: the pointer leaving (when auto-hide is on), a click elsewhere, or the shortcut.
- Click zone: on a notched display, the hardware notch rectangle, which no other app can use. On a display without a
  notch, the pill's own rectangle grown by 12 pt on each side and to 14 pt tall, so it stays clear of menu bar items.
- The click is observed, not taken: Zeus does not start absorbing mouse events while closed. The closed window stays
  click-through exactly as today.
- Anything that opens the notch without the pointer (agent cards, cues, the shortcut, voice) is unchanged.
- The open haptic that already exists fires as it does today.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/NotchOpenTrigger.swift`:

- `NotchOpenTrigger`: `hover`, `click`; `init(label:)` maps the stored display strings, anything unknown is `hover`.
- `NotchOpenRules.opensOnHover(_:)`.
- `NotchOpenRules.clickZone(screenFrame:notchSize:topOffset:)`: the rectangle in screen coordinates. A zero notch
  size means no notch and gives the grown pill rectangle. Works for screens with negative origins.
- `NotchOpenRules.opensOnClick(trigger:isClosed:point:zone:)`.

App side: one static reader beside the existing open-delay reader in `NotchController`, a gate in the hover branch,
and click handling in the existing global left-mouse monitor plus a local one for when a Zeus window is frontmost.
`NotchController` is anchored by source lints (see `qa/closed-loop/tests/test_source_lint.py` and
`test_alerts_lint.py`): keep the anchored lines intact and run those lints.

### Tests first (`Tests/ZeusCoreTests/NotchOpenTriggerTests.swift`)

Label parsing with an unknown value; hover opens only for `hover`; the click zone for a notched screen, a screen
without a notch, a screen with a negative origin and a non-zero top offset; a click inside and outside the zone;
no open when the notch is already open; no open for `hover`.

## S2. Rounded bottom corners

### Behaviour

- Setting `screen.roundBottomCorners` (Appearance, new group "Screen", toggle, off by default): "Round the bottom
  screen corners". Note: "Rounds the two bottom corners of a notched display to match the top. Click-through."
- Setting `screen.cornerRadius` (same group, choices `Small`, `Medium`, `Large` for 8, 12 and 18 pt, default `Medium`):
  "Corner size".
- Drawn only on a display that has a notch, since only those have rounded top corners. Other displays are untouched.
- Each corner is a tiny window, not a screen-sized one. It is click-through, joins every Space, shows over full-screen
  apps, never takes focus, and is not in the window cycle.
- It follows the screen: rebuilt on every screen parameter change (resolution, arrangement, display added or removed),
  not only when the display count changes.
- It follows the Zeus capture rule: hidden from screenshots and screen sharing unless "Show in screen sharing" is on,
  through `ZeusWindowSharing`, and registered wherever the other overlays are registered.
- Static: no timers, no animation, nothing to reduce for Reduce Motion. Hidden from accessibility as decoration.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/TopBar/ScreenCorners.swift`:

- `ScreenCornerSize`: `small`, `medium`, `large`; `init(label:)`; `radius`.
- `ScreenCorners.draws(hasNotch:enabled:)`.
- `ScreenCorners.cornerFrames(screenFrame:radius:)`: bottom-left and bottom-right squares in screen coordinates
  (AppKit origin at bottom-left), correct for negative origins; the radius is clamped to a quarter of the shorter side.
- `ScreenCorners.maskPoints` or an equivalent pure description of the filled region (the square minus the quarter
  disc) for each side, so the drawing can be tested without a view.

App side: `ScreenCornerOverlay` (main actor, one instance) modelled on `EdgeWaveController`, with the same panel
flags as the existing overlays, started where they are started, reacting to the two settings without a restart.

### Tests first (`Tests/ZeusCoreTests/ScreenCornersTests.swift`)

Size labels and radii; draws only with a notch and the setting on; frames for an ordinary screen, a screen at a
negative origin and a second display to the right; radius clamping on a tiny frame; the filled region contains the
outer corner point and excludes a point just inside the arc, for both sides.

## S3. Live diagnostics

### Behaviour

- Settings, Diagnostics gains a card between "Local connection" and the log: "Zeus right now".
- Rows: CPU (Zeus's own process, percent), Memory (Zeus's own footprint, MB), Heat (the Mac's thermal state in words),
  System audio capture (Running, Off, or Not allowed), Now playing (the player's name and Playing or Paused, or None).
  Status is always a word with a symbol, never colour alone.
- A value over the idle budget in `PerformanceBudget` is marked "High" beside the number.
- "Copy" puts a short plain-text summary on the clipboard for a bug report. It contains the Zeus version and build,
  the macOS version and the rows above. It never contains a track title, artist, file path or any other content.
  Nothing is sent anywhere.
- Sampling runs only while the card is on screen, through the existing reference-counted `EnergyMonitor`. No new timer
  when the card is closed. In snapshots the card shows fixed values.

### Rules (ZeusCore, pure)

New file `Sources/ZeusCore/Diagnostics/LiveDiagnostics.swift`:

- `LiveDiagnostics`: optional CPU percent, optional memory bytes, thermal level (reuse `KeepAwakeRules.Thermal`),
  audio capture state, optional player name with a playing flag, app version, build and OS version strings.
- `LiveDiagnostics.rows`: label and value pairs in display order, with "Unknown" for missing values, one decimal for
  CPU, whole megabytes for memory.
- `LiveDiagnostics.isHigh(cpu:)` and `isHigh(memoryBytes:)` against the existing idle budget numbers.
- `LiveDiagnostics.summaryText`: the copied text, deterministic, without user content.

### Tests first (`Tests/ZeusCoreTests/LiveDiagnosticsTests.swift`)

Row order and formatting; missing values read "Unknown"; thermal words; the High marks at and around the budget;
the summary holds version, build and OS and never the track title passed to the fixture; rounding.

## Verification for this wave

Same as wave one: tests committed first and shown failing, focused suites, the whole `ZeusCoreTests` module compared
with the base (4 known failing cases in "Native host process boundaries"), the settings generator and its check, the
Python source lints, `./tools/check.sh` development mode, and an independent review of each diff. Still owed on a
real Mac: a click opening the notch on a notched and on an external display, the corners seen at each size and after a
resolution change, and the diagnostics card watched while music plays.
