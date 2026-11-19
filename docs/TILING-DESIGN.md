# Tiling section and overlays: design

Written 14 November 2026 for ticket T4 of `docs/TILING-PLAN.md`. It follows `docs/DESIGN-DIRECTION.md`. The plan owns
behaviour and fail-closed paths; this note owns what the owner sees and feels.

## What the owner sees

Three surfaces, and nothing else.

1. **The Tiling tab**, second in the top row right after Home. One page, three tiles side by side.
2. **A focus ring**, one thin rounded stroke around the window the keys act on.
3. **A key sheet**, a small card in the middle of the screen listing the keys, shown on request.

Nothing appears until the switch is on. With the switch off there is no ring, no sheet, no key tap, no observer and
no timer.

## The page

Reading order is outcome first, then control, then detail (Stripe, Linear). Three tiles, left to right:

| Tile | Holds | Why it is there |
| --- | --- | --- |
| Control | The on and off switch, one status line, the Accessibility row, the two gaps, the key pair, Pause | Everything the owner can change, in the order they will want it |
| Layout | A small picture of each screen with the tiles as they sit now | The one purposeful focal point (Aesop): the owner sees the result without touching a window |
| Keys | A read-only list, one row per action | Reference, built from the same table the key tap matches, so it cannot drift |

Rules the page keeps:

- **Status is a word and a shape, never a colour alone.** Off, Key clash, Needs Accessibility, Keys unavailable, Paused, On
  each have their own symbol and word (`TilingPhase`). Colour only reinforces.
- **One primary action per state** (Muji). Off: the switch. Key clash: the key pair picker, with the note naming the key that holds the pair. Needs Accessibility: "Open Permissions". On: Pause.
- **The page never asks for a permission.** The Accessibility row says what is true and opens the one existing place
  that asks. It makes no Accessibility call of its own.
- **Gaps and the key pair edit the same settings as Settings.** There is one source of truth, `SettingsStore`.
- **Snapshots are fixed.** The page reads a seeded controller, calls no Accessibility function and shows no overlay.
- Type roles are the notch's existing ones (`TopBarStyle.label`). Gap values use monospaced digits. Long words
  truncate before an action does.
- Keyboard and VoiceOver: every control has a label and a value ("Gap between windows, 8 points"). The key list reads
  each chord in words ("Control + Option with Left Arrow").

## The focus ring

- A 2 point stroke in `Theme.accent`, 12 point corner radius, drawn just outside the window frame. It marks the one
  window the tiling keys act on and nothing else.
- Click-through, never key or main, joins every Space, never takes focus, hidden from screen sharing unless the owner
  turned sharing on. Level `.floating`, so it stays below the notch window.
- It exists only while it is showing. Hiding closes the panel, so nothing idles on screen.
- Motion explains a change and stays interruptible (Apple): a 120 ms fade when the ring first appears, and the ring
  jumps to a new window at once. With Reduce Motion there is no fade. With Reduce Transparency the soft halo is
  dropped and only the stroke remains.
- It hides when tiling is off or paused, when the focused window is floating, excluded, minimized or full screen, and
  in snapshots.

## The key sheet

- A rounded card centred on the main screen, `.statusBar` level, click-through, never key.
- One heading, "Tiling keys", then one row per action: the name on the left, the chord on the right in the system
  rounded face. Eight rows by default.
- It is a quiet reminder, not a modal. It hides after a few seconds, on the next tiling key, and when tiling stops.
- The tap sees only chords the owner bound, so Escape is not taken. Closing by timer or by the next tiling key keeps
  the rule that Zeus never consumes a key it was not given.
- Reduce Transparency swaps the material for a solid card.

## Copy

Plain and short. No dashes, no filler. Examples: "Off", "Key clash", "Needs Accessibility", "Keys unavailable", "Paused", "On";
"Allow Accessibility so Zeus can move windows."; "Windows stay where they are."; "Hold the keys and tap an arrow."

## Checked on a real Mac, not here

Light and dark, a small display and an external one, the ring over a busy window, Reduce Motion and Reduce
Transparency toggled while the page is open, VoiceOver order on the page, and the ring and sheet absent from a screen
share. These are listed in the plan's verification section and stay open until seen.
