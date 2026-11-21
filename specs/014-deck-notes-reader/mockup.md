# Mock-up — deck notes in the top bar

`mockup.html` is a static drawing of the open top bar. It is not a window, and it is not a screenshot of the running app. Open the file in a browser to see it. The two figures are the `showing` state and the `notesNotOnPage` failure from `spec.md`.

## Frame

The panel is the existing top bar from `Sources/ZeusCore/TopBar/GlanceTopBar.swift`.

| Piece | Size |
| --- | --- |
| Body | 870 pt wide |
| Bottom radius | 22 pt |
| Notch row | 38 pt, left empty |
| Tab row | 34 pt, inset 24 pt, with the 30 pt more circle at the trailing edge |
| Page | 236 pt, the tall page used by every tab except Home |
| Gap under the page | 14 pt |

The tab capsule is black with a faint top rim. The selected tab is Prompter, on the existing grey pill, name set in the bar's sans. The drawing shows Home, Tiling, Agents, Chat, and that pill, then the more circle. The real row is the existing one; the drawing shortens it so the pill stays readable. No title bar and no window controls, because this is the bar under the notch.

## Page, showing

Reading order, top to bottom:

1. Kicker, "Speaker notes", small caps, quiet ink.
2. Position "04 / 18" in light tabular figures, and the deck name "Quarterly review" in the secondary ink.
3. A hairline.
4. The notes, a serif, about 17 pt, a measure near 60 characters, line breaks kept. The sample sentence is synthetic: "Open on the quarter, then the two numbers. Pause after the second. If they ask about the hiring plan, it is on the next slide. Leave the chart up while you answer."
5. One line under the notes: "On this Mac. Cleared when you leave."
6. Read again, as the filled paper button. Follow and Clear, as hairline buttons.

The notes are the only long text. The script already on the Prompter page is not replaced and is not drawn in this result state. The idle page, which this drawing does not repeat, keeps that script and adds Read.

## Page, notes not on this page

The same bar and the same Prompter pill. The notes region is the failure, in the same serif, with the specified title and line:

- Title: "Notes are not on this page"
- Line: "Open the speaker notes in the browser, then press Read."

Read again is the only button. The sample notes are absent.

## Ink

Monochrome, taken from the bar's existing ink. No second hue.

| Role | Value |
| --- | --- |
| Panel | `#0E1116` |
| Primary text | `#E9EDF2` |
| Secondary | `#A3ADB8` |
| Quiet | `#8A94A0` |
| Selected pill | `#353537` |
| Notes | `#E7E1D6` on the same panel |
| Hairline | white at 16% |
| Filled button | `#E9EDF2` with `#0E1116` text |

The notes face is a serif the system already has (Iowan Old Style, Palatino, or Georgia). Labels stay in the bar's sans. Figures are tabular.

## Motion and keys

A new slide replaces the paragraph in place. Reduce Motion uses the same replacement. The drawing has no transition. Read again is the default button. Follow is never the default. Clear and Escape return the page to idle and the sentence is gone.

## What the drawing leaves out

The idle script, the empty-slide caption, and the other six failures. Their words are in `spec.md`. The drawing was not reviewed on a Mac, and a static file is not the visual acceptance named in the spec.
