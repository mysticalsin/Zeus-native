# Sensory

**Status**: Draft, inferred. The settings inventory records no Sensory contract, so this file is the working spec for the section. Open questions are listed at the end and in the pull request.

**Placement**: `.topbarTab(6)`, the shell's zero-based tab. The slot is filled. Spacing comes from `GlassSettingsMetrics`.

Sensory is the volume and brightness overlay. It keeps the keys the app already stores and adds the two controls the overlay was missing: how long it stays, and whether the level is an icon or words.

## Keys

Existing keys stay as they are. Absent values keep the catalog default, on.

| Key | Control | Default | Meaning |
| --- | --- | --- | --- |
| `lights.hud.volume` | toggle | on | Show the overlay when output volume changes. |
| `lights.hud.brightness` | toggle | on | Show the overlay when built-in display brightness changes. |
| `lights.hud.replaceSystem` | toggle | on | While the overlay is up, hide the system overlay. Off leaves the system overlay alone. On does nothing until Accessibility is trusted; until then both overlays can show and the row explains why. |

New keys are catalog rows in Everyday lights, stored as `opt.<id>` like every other catalog value. A fresh store keeps the historical 1.2 second dwell and the icon. Words is off until chosen.

| Key | Control | Default | Meaning |
| --- | --- | --- | --- |
| `lights.hud.hold` | stepper, 0.1 s | 1.2 s | How long the overlay stays fully visible after the latest change. |
| `lights.hud.label` | icon or words | icon | Icon draws the level symbol. Words draw the level as text. VoiceOver hears the level either way. |

`lights.hud.hold` accepts a number of seconds. A missing, blank, or non-finite value is 1.2. A finite value below 0.4 becomes 0.4. A finite value above 6 becomes 6. A value inside the range is kept as written, including one that is not on the 0.1 grid. The stepper snaps to that grid, then moves by 0.1, and never leaves 0.4...6.

`lights.hud.label` accepts `icon` or `words`. Anything else, including a blank, is `icon`.

Keyboard backlight, the mute pulse, and the screen-edge glow keep their current keys and are not rows on this section.

## Lifecycle

One overlay is shared by volume and brightness. The latest accepted change owns it. A keyboard-backlight change is ignored. A change for a kind that is turned off is ignored, except that a change for the kind currently on screen hides the overlay.

States are `hidden`, `showing`, `extending`, and `fading`.

- `hidden` and an accepted change becomes `showing`. The anchor is that change.
- `showing`, `extending`, or `fading` and an accepted change becomes `extending`. The anchor moves to that change and any fade is cancelled.
- `showing` lasts the fade-in plus the hold. The fade-in is 0.12 s.
- `extending` stays fully visible for the hold. It does not fade in again.
- When that visible time ends, the state becomes `fading` for 0.25 s, then `hidden`.
- A tick at a boundary takes the later state. A tick after the fade has finished is `hidden`, not a stale `fading`.
- Dismiss from any visible state is `hidden`.
- Turning the current kind off hides immediately.
- Editing the hold while `showing` or `extending` uses the new hold from the same anchor. Editing it during `fading` does not bring the overlay back.

Reduce Motion sets the fade-in and the fade-out to 0. The hold still applies. A tick at the end of the hold goes straight to `hidden`. Settings motion uses the same rule: the preview does not animate while Reduce Motion is on.

The time until hidden, measured from the anchor, is fade-in + hold + fade-out for `showing`, and hold + fade-out for `extending`. With the default hold and motion allowed, a fresh overlay is on screen for 1.57 s and a repeat change keeps it for 1.45 s from that change. The notch removes the cue on that same interval.

## Section chrome

Dark glass cards. Each control is a 52 pt row with a helper line under it. The panel padding is 32 pt and the gap between cards is 28 pt. The preview tile shows the current overlay: a sample level, the chosen label, and the lifecycle phase. It has a loading line while a reading is in flight, an empty line when both overlays are off, and the Accessibility explanation when replace-system is on but not trusted. Every control has a VoiceOver label and is keyboard reachable.

## Open questions

- The inventory's plan was that this section adds no key. The names `lights.hud.hold` and `lights.hud.label` need confirmation, as does leaving them out of the generated catalog.
- Should volume and brightness be one switch instead of the two keys that already exist?
- Should keyboard backlight, mute, and the screen-edge glow move here, and should the glow use this hold?
- Are 0.4 s and 6 s the right bounds, and is the dwell the full-opacity time rather than the whole time on screen?
- Should replace-system stay on by default?
- The shell places this section at `.topbarTab(6)`. Portal keeps `.topbarTab(7)`.
