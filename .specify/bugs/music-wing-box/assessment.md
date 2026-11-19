# Bug Assessment: Music wings miss the content box by 14 pt

- **Slug**: music-wing-box
- **Created**: 2026-11-19
- **Source**: pasted text (Devin retro on PR #4, hosted runs 44445557994 and 44445566167)
- **Verdict**: valid
- **Severity**: medium

## Symptom

Devin's retro says `theMusicWingsStayClearOfTheNotch` fails by 14 pt. That distance is `contentInset`. The music frames have to sit in the inset content box, which is 14 pt inside the full wing.

The app job log for run 44445557994 marks `ClosedWingsNotchTests` passed (10 tests). The 14 pt assertion text is not in that log. The geometry still has to name the box and the view has to frame the content to it.

## Reproduction

1. Show the closed notch with music wings (a playing track, no cue).
2. Read the wing content frames against `NotchClosedBodyLayout.closedWingGeometry` with extra 0.
3. The frames extend 14 pt outside that box, which is `contentInset`.

## Suspected Code Paths

- `Sources/ZeusCore/TopBar/NotchClosedBodyLayout.swift` — the content box is `wingWidth - contentInset + extra`.
- `Sources/Zeus/TopBar/TopBarViews.swift` — `ClosedWingsRow` overlays the music art and bars without framing them to that width.
- `Tests/ZeusAppTests/ClosedWingsNotchTests.swift` — `theMusicWingsStayClearOfTheNotch`.

## Root Cause Hypothesis

The symmetric content box is 14 pt inside the full wing. The music art and level bars were measured at the full wing, so they miss the box by `contentInset`. Confidence: high. The inset constant is 14 and the hosted failure is 14 pt.

## Proposed Remediation

**Preferred**: Give the music frames the inset box, and frame and clip each wing's content to `wingContentWidth`.

**Files likely to change**:

- `Sources/ZeusCore/TopBar/NotchClosedBodyLayout.swift`
- `Sources/Zeus/TopBar/TopBarViews.swift`
- `Tests/ZeusCoreTests/NotchClosedBodyLayoutTests.swift`

**Tests to add or update**:

- `theMusicWingFramesStayInsideTheSymmetricContentBox`

## Risks & Considerations

- Other cues use the same row. Framing their content to the same width keeps them in the box too. It does not change the body width.

## Open Questions

- The hosted app test has not been re-run on this fix.
