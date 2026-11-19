# Bug Verification: Shipped talk walk

- **Slug**: voice-walk-state-bound
- **Tested**: 2026-11-19
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

The silent 200,000 ceiling is gone. The search prints its state count and fails if it is truncated. That count is not pinned. 864,682 and 906,972 were both written down, and no single `swift test` log of this head records one of them as the count, so neither number is the canonical graph. The agreement walks use the late, held and chord moves as well as the reference pair. Linux did not run the Swift suite.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| State count | `theShippedTalkHoldWalkFinishesUnderItsStateBound` | not-run | Unpinned. The run must finish, stay untruncated, and report more than 100 states. |
| Agreement | `theExactAndFoldedWalksAgreePastTheFirstCut`, `theControlOptionMergeAgreesWithTheUnmergedWalk` | not-run | Late, held and chord moves are in the set. `reference: true` is not used. |
| Hosted log | runs 44445557994 and 44445566167 | read | Both are SHA 48add1d1. The walk line there is `1883647 states`, from before this fold. |

## Output Excerpts

`voice key walk A talk hold Control-Option confirm 0.15: 1883647 states, 28473473 moves, 1067.94 s` in run 44445557994. That is the unfolded graph, not a count for this head.

## Residual Risks

- The canonical count is the next hosted line for run A. Until that line exists, the two earlier numbers stay unpinned.

## Recommendation

Hold the exact count until a hosted `swift test` log of this head prints it.
