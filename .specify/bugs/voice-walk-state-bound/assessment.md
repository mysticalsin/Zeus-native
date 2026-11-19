# Bug Assessment: Shipped talk walk explodes to 1,883,647 states

- **Slug**: voice-walk-state-bound
- **Created**: 2026-11-19
- **Source**: pasted text (Devin retro on PR #4, hosted runs 44445557994 and 44445566167)
- **Verdict**: valid
- **Severity**: high

## Symptom

The voice-key walk `A talk hold Control-Option confirm 0.15` reached 1,883,647 states (about 1068 s in the log) and ZeusCoreTests was killed at 3600 s.

## Reproduction

1. Run ZeusCoreTests on the hosted macOS runner.
2. The first walk prints `voice key walk A talk hold Control-Option confirm 0.15: 1883647 states`.
3. The suite does not finish inside 3600 s.

## Suspected Code Paths

- `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift` — `WalkRun.all[0]` and `search`.
- The replay tests (`theOrdersTheReviewsFoundKeepTheRules`, `theChordOrdersKeepTheRules`) are the bridge. They are not the exploding search.

## Root Cause Hypothesis

Run A is the full late chord search. Its reachable graph is about 1.9 million states, which alone takes a large part of the 3600 s Core budget, and the runs after it do not finish. Confidence: high. The hosted log names this run and that state count.

## Proposed Remediation

**Preferred**: Give this run an explicit state ceiling of 200,000. The search stops once that many states are recorded. States already recorded are still checked. Do not skip, loosen, or early-return the bridge replay tests. Do not change timeouts, Package.swift, or CI.

**Files likely to change**:

- `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift`

**Tests to add or update**:

- `theShippedTalkHoldWalkFinishesUnderItsStateBound`

## Risks & Considerations

- A violation that appears only after 200,000 states of this one run is not visited. The named orders stay covered by the replay tests.

## Open Questions

- The hosted suite has not been re-run with the ceiling.
