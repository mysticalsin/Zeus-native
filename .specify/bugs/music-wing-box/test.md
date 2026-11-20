# Bug Verification: Music wings miss the content box by 14 pt

- **Slug**: music-wing-box
- **Tested**: 2026-11-19
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

The frames are defined as the inset box and the row clips content to that width. The hosted app test has not been re-run here. This is not a verified verdict.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | `theMusicWingsStayClearOfTheNotch` on a Mac | not-run | No macOS UI here. |
| New / updated tests | `theMusicWingFramesStayInsideTheSymmetricContentBox` | not-run | Linux cannot compile this target. |
| Regression suite | Hosted Zeus checks | not-run | Waiting on the hosted run. |

## Output Excerpts

No local test output.

## Residual Risks

- The hosted wing test is still the one that measures real frames. This note does not replace it.

## Recommendation

Hold. Do not call this verified until the hosted app job passes `theMusicWingsStayClearOfTheNotch`.
