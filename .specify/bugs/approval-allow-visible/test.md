# Bug Verification: Approval card shows Deny and hides the command

- **Slug**: approval-allow-visible
- **Tested**: 2026-11-19
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

The rules are in `ApprovalCard` and the card view. This environment did not run the macOS tests, and the hosted job for this head has not been read here. This is not a verified verdict.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | Raise a card on a Mac | not-run | No macOS UI here. |
| New / updated tests | `swift test --filter ApprovalCardTests` | not-run | Linux cannot compile the app target. |
| Regression suite | Hosted Zeus checks | not-run | Waiting on the hosted run. |
| Source inspection | Read `ApprovalCard.buttons` | pass | Allow and Deny are returned for every risk. |

## Output Excerpts

No test output.

## Residual Risks

- High risk still requires a hold. A quick tap must not count as Allow.
- If the hosted job fails for a reason other than these three tests, this note does not cover that failure.

## Recommendation

Hold. Do not call this verified until the hosted app job on this head passes `ApprovalCardTests`.
