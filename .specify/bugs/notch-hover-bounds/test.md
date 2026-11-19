# Bug Verification: Notch hover grows with a long notification

- **Slug**: notch-hover-bounds
- **Tested**: 2026-11-19
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

The size rule is in the source and in the tests. This checkout cannot run the macOS app tests, and the hosted job for this head has not been read. This is not a verified verdict.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | Hover with a long note on a Mac | not-run | No macOS UI in this environment. |
| New / updated tests | `swift test --filter NotchLayoutBoundsTests` | not-run | Linux cannot compile the app target. |
| Regression suite | Hosted Zeus checks | not-run | Waiting on the hosted run. |
| Source inspection | Read `NotchLayoutBounds.size` | pass | Hover does not add notification height. |

## Output Excerpts

No test output. The hosted log is the missing check.

## Residual Risks

- A peek with a very tall approval is clamped, which can clip that peek. That is the bound, and it is not the hover bug.
- Snapshot files are not in the repository. They appear only in the hosted artifact.

## Recommendation

Hold. Do not call this verified until the hosted app job on this head passes `NotchLayoutBoundsTests` and the snapshot step.
