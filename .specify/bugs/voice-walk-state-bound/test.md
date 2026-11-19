# Bug Verification: Shipped talk walk explodes to 1,883,647 states

- **Slug**: voice-walk-state-bound
- **Tested**: 2026-11-19
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

The silent 200,000 ceiling is gone. A local optimized run of the canonical graph reported 864,682 states, depth 33, no violations, and the plain walk of 66,429 sequences met no stranger and no rule break. The negative searches still find the processing-time mistake, I6s, and I9. The hosted suite has not been re-run. This is not a verified verdict.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | ZeusCoreTests voice walk on a Mac | not-run | The previous log showed 1883647 states before the ceiling. |
| New / updated tests | `theShippedTalkHoldWalkFinishesUnderItsStateBound` | not-run | Linux cannot compile this target. |
| Bridge replay tests | unchanged source | not-run | They were not edited and were not re-run. |
| Regression suite | Hosted Zeus checks | not-run | Waiting on the hosted run. |

## Output Excerpts

Previous hosted line, before this fix: `voice key walk A talk hold Control-Option confirm 0.15: 1883647 states, 28473473 moves, 1067.94 s`.

## Residual Risks

- Orders past the ceiling in this one run are not searched. The replay tests still cover the orders they name.

## Recommendation

Hold. Do not call this verified until the hosted Core suite finishes and the printed state count for run A is at or under 200,000.
