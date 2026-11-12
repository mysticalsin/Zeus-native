# Record section layout

The Record page lives in the open top bar: 870 pt wide, a 236 pt page, so about 806 x 208 pt of room
inside the card (`RecordlyPageLayout.innerHeight`). The old layout stacked the source list, notices and
option chips in a scrolling column next to a fixed 340 pt preview, so windows and notices pushed the
options out of view. The new layout fits that room with no scroll view, and a double click on a source
opens a setup screen of its own.

## Grid screen (default)

```
+----------------------------------------------------------------------------------------+
| [Display | Window | Area]                         (permission pill, or nothing)        |  header 30
+------------------------------------------------------+---------------------------------+
| stage (glass frame, dims and counts down)            | options                         |
|                                                      | [Microphone Soon] [System audio]|
|  Display: the monitors to scale, main one selected   | [Camera Soon]     [Cursor zoom] |
|  Window:  a grid of window tiles, 3 rows,            |                                 |
|           paged with  < 1 / 3 >  when they overflow  | notice slot (2 lines, tooltip)  |
|  Area:    "Area recording isn't available yet."      |                                 |
|                                                      | (O)  Record                     |
|                                    < 1 / 2 >  Refresh|      Records Built-in Retina... |
+------------------------------------------------------+---------------------------------+
                      flexible                                   264
```

While recording, the options and notice slot are replaced by the live capsule (dot, timer, meters).
The capture control stays in the same place in every state.

## Detail screen (double click on a source)

```
+----------------------------------------------------------------------------------------+
| [< Back]  Record this window                               Owner app, Window 123       |  header 30
+------------------------------------+---------------------------------------------------+
| preview (glass frame)              | options                                           |
|  display: live thumbnail           | [Microphone Soon] [System audio]                  |
|  window: window glyph, title,      | [Camera Soon]     [Cursor zoom]                   |
|          owner                     | notice slot                                       |
|  countdown numeral, live frame     | (O)  Record   Records "Window title"              |
+------------------------------------+---------------------------------------------------+
           320                                       flexible
```

## States

| State | Grid screen | Detail screen |
|---|---|---|
| idle | tiles selectable, options live | same options, Record enabled when allowed |
| no Screen Recording | header pill with "Open Screen Recording settings" | same pill in the notice slot |
| countdown | stage dims, 3 2 1 numeral, ring around the control, Esc cancels | same, over the preview |
| starting / recording / stopping | live frame on the stage, live capsule replaces options | live frame on the preview, live capsule replaces options |
| saved | editor (clip card left, export options right) | navigation resets to the grid |

## Navigation

Pure rules in `ZeusCore/Recordly/RecordlyRecordNavigation.swift`, tested with Swift Testing.

- Single click on a tile selects it (immediate, no double-click delay).
- Double click selects it and opens the detail screen. While capturing, nothing can be selected, so only
  the selected source opens.
- Back (button, or the accessibility action) returns to the grid.
- Every open bumps `openCount`; the detail view takes it as its identity, so each open is a new view that
  starts at the top, and the scroll fallback is reset to the top on appear.
- The detail screen closes by itself when its source disappears while idle, and whenever a saved clip
  opens the editor. It stays open while capturing.
- Window tiles are paged, not scrolled. `RecordlySourceGridPaging` works out columns, rows and pages
  from the stage size and opens on the page that holds the selected window.

## Scroll fallback

The fixed top bar is never smaller than 208 pt, so neither screen scrolls. If the room ever drops below
`RecordlyRecordLayout.minimumHeight`, the content keeps its minimum height inside a vertical scroll view.
Snapshots never use a scroll view (ImageRenderer cannot draw one).

## Motion

- Grid to detail: the detail comes in from the trailing side by 28 pt with a fade, the grid leaves
  toward the leading side; back reverses it. Spring, response 0.3, damping 0.9. Reduce Motion: fade.
- The staggered entrance runs once, when the page first opens, not again after Back.
- Visible motion runs on `DisplaySynchronizedView` (native display rate, paused off screen and in
  Reduce Motion) instead of `TimelineView`: the countdown ring, the 3 2 1 numeral and the audio meter
  (was capped at 30 fps). The elapsed timer is a label on `TickingView` (twice a second), which stops when the
  window is hidden.

## Option mapping

| Existing option | Where it is now |
|---|---|
| Display / Window / Area switcher | grid header, left |
| Display picker (main selected by default, others selectable) | stage diagram tiles; double click opens the display detail |
| Display legend (name, size, Main tag) | tile labels and the detail header |
| Window list (load, loading + cancel, stale, denied, failed, refresh) | window tile grid with the same states and buttons, pager and Refresh at the bottom |
| Permission banner | header pill (grid), notice slot (detail) |
| Display, action, selection and failure notices, Try again | notice slot, 2 lines, full text in the tooltip |
| Microphone (soon), System audio, Camera bubble (soon), Cursor zoom | options grid, both screens |
| Capture control, headline and caption | bottom of the side column, both screens |
| Countdown (numeral, ring, Esc to cancel) | stage or preview, and the control |
| Live capsule (timer, meters) | side column while capturing |
| Editor: clip card, notices, export options, export, New, discard flow | editor, two columns |
