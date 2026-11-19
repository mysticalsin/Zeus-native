# Bug Fix: Shipped talk walk explodes to 1,883,647 states

- **Slug**: voice-walk-state-bound
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

A bound no longer lets the walk pass. If a bound or `WALK_LIMIT` stops the search, the run is marked truncated and fails. The shipped talk walk has no bound. Ages fold onto the rule thresholds, and only-Option-down is the same state as only-Control-down when the own set is exactly that pair. The canonical graph has 906,908 states. A search wait jumps to the next machine window, so the successor lands on the cut the key records. Visited states are compared by the whole key. The replay tests are unchanged.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift` | Search waits jump to the next machine window. Visited states are the whole key. | Run A has no bound. The count is 906,908. |

## Tests Added or Updated

- `VoiceKeyWalkTests.theShippedTalkHoldWalkFinishesUnderItsStateBound`

## Local Verification

- A throwaway optimized build of this harness, not `swift test`, reported 906,908 states, depth 33, no violations. Exact ages at depth 2 are covered by the folded keys. Shifting each window by one step changes the landings.
- The replay functions are not edited. The macOS package was not built.

## Deviations from Assessment

None.

## Follow-ups

- Read the hosted ZeusCoreTests log. Run A should print 864682 states and the run must not be truncated.
