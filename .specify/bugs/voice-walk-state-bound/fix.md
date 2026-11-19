# Bug Fix: Shipped talk walk explodes to 1,883,647 states

- **Slug**: voice-walk-state-bound
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

A bound no longer lets the walk pass. If a bound or `WALK_LIMIT` stops the search, the run is marked truncated and fails. The shipped talk walk has no bound. Ages fold onto the rule thresholds, and only-Option-down is the same state as only-Control-down when the own set is exactly that pair. The canonical graph has 864,682 states. The replay tests are unchanged.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift` | Canonical ages and the Control/Option mirror. A bound sets `truncated` and fails. | Run A has no bound. The count is 864,682. |

## Tests Added or Updated

- `VoiceKeyWalkTests.theShippedTalkHoldWalkFinishesUnderItsStateBound`

## Local Verification

- A throwaway optimized build of this harness, not `swift test`, reported 864,682 states, depth 33, no violations. The plain walk was 66,429 sequences with no stranger and no rule break. The processing-time, I6s, and I9 searches still stop on those rules.
- The replay functions are not edited. The macOS package was not built.

## Deviations from Assessment

None.

## Follow-ups

- Read the hosted ZeusCoreTests log. Run A should print 864682 states and the run must not be truncated.
