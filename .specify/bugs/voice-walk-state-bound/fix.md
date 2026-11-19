# Bug Fix: Shipped talk walk explodes to 1,883,647 states

- **Slug**: voice-walk-state-bound
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Run A declares `stateBound` 200,000. `search` stops when that many states are recorded and does not add a fake pass. The replay tests are unchanged.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift` | `WalkRun.stateBound` and the stop in `search` | Only run A sets it. |

## Tests Added or Updated

- `VoiceKeyWalkTests.theShippedTalkHoldWalkFinishesUnderItsStateBound`

## Local Verification

- Commands run: none. The walk is too large to run here, and the app target does not build on Linux.
- Manual checks: the ceiling is read only when `run.stateBound` is set. The replay functions are not edited.

## Deviations from Assessment

None.

## Follow-ups

- Read the hosted ZeusCoreTests log. Run A should print a state count at or under 200,000, and the suite should finish inside 3600 s.
