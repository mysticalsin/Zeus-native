# DESIGN: Scribe and Record pages redesign

Owner feedback (2026-11-11): Scribe and Record look boring; the flat red pill buttons ("Start", "Record") feel
cheap. Goal: Apple-quality pages that feel alive, while keeping Zeus's palette, fonts and the notch panel shape.
Follows `DESIGN-DIRECTION.md` (meaning before decoration, one primary action, Reduce Motion) and
`SCRIBE-SPEAKER-NAMES-DESIGN.md`.

Evidence of the problem (snapshots of build 224d9df): Scribe idle is a text column, a permission sentence in
plain grey, an empty "Recent meetings" line and a red "Start" pill bottom-left. Record idle is an empty grey panel
with a dim red "Record" pill. Neither shows what will be captured or what you will get.

## Shared rules
- Red means "capturing right now" only: a small live dot and the timer. Never a resting button colour.
- Primary action = the capture control, a round glass button (56 pt): white ring, inner glyph (Scribe: waveform;
  Record: filled dot). Hover lifts 2 %, press 0.97, focus ring visible. While capturing it morphs to a rounded
  square Stop with the elapsed time beside it (monospaced digits). Countdown = a ring drawing around it.
- Accent for idle emphasis = Zeus's existing accent (`OB.controlAccent` / Theme tokens), never new colours.
- Missing permission = an inline banner with an icon, one sentence and a button ("Allow microphone",
  "Open Screen Recording settings"); the capture button is disabled with that reason as its tooltip and VoiceOver
  hint. Never a plain grey paragraph.
- Motion: page spring from `Motion`; state changes cross-fade under Reduce Motion; nothing animates while idle
  except one slow ambient element that pauses when the panel is hidden (DisplaySynchronizedView). No CPU at rest.
- Empty states have a small illustration (mascot pose already bundled) and one line that says what will appear.

## Scribe
**Idle**
- Left, "Up next" card: the next calendar meeting (title, "in 4 min", call app icon from `EngineBrandLogo`, stacked
  attendee initials). Button "Take notes" starts with that title. With no meeting: "Ready when you are".
- Capture control centred under the card, with three small source chips beneath: Microphone, Call audio, Names
  (each with a status dot: on, off, needs permission).
- Ambient element: a soft waveform line that breathes slowly (synthetic, not the mic: no audio before Start).
- Right, "Recent meetings": cards (title, date, duration, people chips with names and colours, first action item).
  "Memory" stays as a secondary text button top-right.
**Recording**
- Top strip: live dot, "Recording", timer, call app icon, Stop control, discard (trash, confirm).
- "Now speaking" pill (from the names design) above a live level ribbon coloured by the current speaker
  (uses the existing 24-value `levelHistory`, no new audio work).
- Live transcript: name chips in speaker colours, newest at the bottom, gentle word reveal (existing).
- People rail on the right: everyone heard so far, talk share bars growing smoothly, "Naming…" placeholders.
**Ending / saved**: progress ring "Writing notes", then a recap card slides in with summary, action items, people.

## Record (Recordly)
**Idle**
- Left, preview stage (16:10): the display arrangement diagram (from the Record fix) with the selected display
  filled in the accent and its name; when Screen Recording is already granted, a still thumbnail of that display
  (refreshed only on page open and on selection, never streaming).
- Source switcher: segmented control with symbols: Display, Window, Area.
- Options as icon chips: Microphone, System audio, Camera bubble, Cursor zoom, each showing on/off.
- Capture control bottom-centre; "Records Built-in Retina Display" caption beneath.
**Countdown**: ring 3, 2, 1 around the control, Esc cancels; stage dims slightly.
**Recording**: control becomes Stop with timer; stage shows a red frame outline around the selected display
diagram; small level meter for the mic chip when the mic is on.
**Saved**: thumbnail card of the clip with duration, Reveal in Finder, Export presets.

## Acceptance
- Snapshot states: Scribe idle (with/without next meeting, permission missing), recording (named speakers),
  saving, saved; Record idle (one and two displays, permission missing), countdown, recording, saved.
- VoiceOver: capture control announces state and source; chips have labels and selected traits.
- Instruments check on the owner's Mac: idle page under 1 % CPU with the panel open.

## Scribe Memory (owner request 2026-11-11: "sexier and cleaner, with Zeus walking around in there")
- Layout: left rail of meetings grouped by Today, This week, Earlier (title, time, duration, people initials,
  one-line outcome); right pane the selected meeting: summary, decisions, action items with checkboxes, people chips
  with talk share, transcript collapsed behind "Show transcript". Search field on top with `speaker:` and
  `with:` filters as removable chips (people names from speaker naming).
- Zeus mascot lives in the Memory pane: walks along the bottom edge between the rail and the content using the
  existing mascot animations (LivingMascot / MascotMotion / Anim frames), stops and looks at the item under the
  pointer, sits when idle, waves on an empty state ("No meetings yet"), and "reads" (book or glance pose) while a
  search runs. One mascot, max 12 fps sprite updates, paused when the panel is hidden or the window is not key,
  Reduce Motion: static pose that changes on state only. Never covers text: it walks in a reserved 64 pt lane.
- Motion: selecting a meeting slides the content with the page spring; list items fade in staggered 30 ms on
  first open only; action item check has a small spring tick.
- Clean: no borders between rows, hairline separators only between groups, generous spacing, tabular numerals.
- Snapshots: empty, list with 6 meetings, selected meeting, search with a speaker chip, mascot in walk, sit, wave.
