# Bug Fix: Shipped talk walk

- **Slug**: voice-walk-state-bound
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The canonical graph is the search the shipped talk run prints. It is not 864,682 and it is not 906,972: those two numbers disagreed, and neither is taken from a `swift test` log of this head. A bound or `WALK_LIMIT` still fails the run. Ages fold onto the fixed timing lets. The harness keeps its own clock and windows, so a test can shift a window without a mutable static on the machine. `Sim.now`, wake steps and cuts use that one quantum. The agreement walks include the late, held and chord moves.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Sources/ZeusCore/VoiceKeyMachine.swift` | Timing values are `let`. | No `Timing.active`. |
| `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift` | Harness `WalkTiming`. Agreement moves. Unpinned count. | The printed state count is the graph. |
| `Sources/Zeus/Pointing/PointingHotkeyMonitor.swift` | Watchdog period is `PointingKeyGesture.watchdog`. | Not the literal 0.25. |

## Tests Added or Updated

- `VoiceKeyWalkTests.theShippedTalkHoldWalkFinishesUnderItsStateBound`
- `VoiceKeyWalkTests.theExactAndFoldedWalksAgreePastTheFirstCut`
- `VoiceKeyWalkTests.theControlOptionMergeAgreesWithTheUnmergedWalk`
- `VoiceKeyWalkTests.shiftingEachMachineWindowChangesTheWalk`
- `VoiceKeyWalkTests.productionTimingsAreFixedLets`

## Local Verification

- Planner and closed-loop selftests on Linux. The Swift walk was not executed here.

## Deviations from Assessment

The exact state count stays unpinned until one hosted log of this head prints it.

## Follow-ups

- Read the hosted ZeusCoreTests log for this head. The run A line is the canonical count.
