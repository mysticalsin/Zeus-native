# Bug Fix: Music wings miss the content box by 14 pt

- **Slug**: music-wing-box
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

`musicWingFrames` returns the inset box. Each wing's content is framed to `wingContentWidth` and clipped, so the measured frame cannot stick out by the 14 pt inset.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Sources/ZeusCore/TopBar/NotchClosedBodyLayout.swift` | added `musicWingFrames` | The box for extra 0. |
| `Sources/Zeus/TopBar/TopBarViews.swift` | modified `ClosedWingsRow` | Content is framed and clipped to the box. |
| `Tests/ZeusCoreTests/NotchClosedBodyLayoutTests.swift` | added the failing test, now expected to pass | Frames equal the inset box and sit 14 pt inside the full wing. |

## Tests Added or Updated

- `NotchClosedBodyLayoutTests.theMusicWingFramesStayInsideTheSymmetricContentBox`

## Local Verification

- Commands run: none. This checkout cannot compile the macOS app target.
- Manual checks: `contentInset` is 14. `musicWingFrames` returns `closedWingGeometry` with extra 0, whose content width is `wingWidth - 14`.

## Deviations from Assessment

None.

## Follow-ups

- Read the hosted `ClosedWingsNotchTests` result before calling this verified.
