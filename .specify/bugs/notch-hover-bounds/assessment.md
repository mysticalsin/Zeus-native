# Bug Assessment: Notch hover grows with a long notification

- **Slug**: notch-hover-bounds
- **Created**: 2026-11-19
- **Source**: pasted text
- **Verdict**: valid
- **Severity**: high

## Report (verbatim or summarized)

A notification or approval made the hover panel very tall. The hover should stay the normal panel size. The panel was also too narrow and too tall in the middle; the redesign is wider and shorter.

## Symptom

Hovering the notch while a long agent note was up stretched the home panel by the note's height. The expected panel is the designed hover size, with the note drawn inside it.

## Reproduction

1. Open the notch on the home page.
2. Raise an approval or notification whose text is many lines.
3. Hover the notch.
4. The panel used to grow with that text. It should match a hover with no notification.

## Suspected Code Paths

- `Sources/Zeus/Notch/NotchView.swift` — `topBarPanelSize` used to add the approval's extra height to the home frame.
- `Sources/ZeusCore/TopBar/NotchLayoutBounds.swift` — `size(_:)` is the bound the hover now asks.

## Root Cause Hypothesis

The hover size and the notification size were one formula. A long note changed the panel because the layout added `approval.extraHeight` to the home frame. Confidence: high. The old addition is gone; hover now calls `NotchLayoutBounds.size`, which uses `GlanceTopBar.panelSize` and does not add the note height.

## Proposed Remediation

**Preferred**: Hover size ignores notification and approval height. Clamp every combination to the designed maximum. Draw the long note inside that size.

**Files likely to change**:

- `Sources/ZeusCore/TopBar/NotchLayoutBounds.swift`
- `Sources/Zeus/Notch/NotchView.swift`
- `Tests/ZeusAppTests/NotchLayoutBoundsTests.swift`

**Tests to add or update**:

- A long notification does not stretch the home hover.
- Hover with a notification matches a plain hover.
- Every panel combination stays inside the designed maximum.

## Risks & Considerations

- Peek cards still have their own size, then `NotchLayoutBounds.clamp`.
- The wider, shorter body changes card geometry tests. Those numbers must match `GlanceTopBar`, not a guessed size.

## Open Questions

- Hosted snapshot PNGs for the six notch-bounds images are produced only by the macOS app job. They are not in this tree.
