# Bug Fix: Shipped talk walk

- **Slug**: voice-walk-state-bound
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The canonical graph is the search the shipped talk run prints. It is not pinned. Run 44445566167 (SHA 48add1d1) printed `1883647 states`. That line is the unfolded bug, not a red run of this pull request and not a count for this head. The folded search must stay under that unfolded size. A lower bound comes from the age cuts and the key bits.

Production timings are lets. The harness derives `WalkTiming` from those lets and from `PointingKeyGesture.watchdog`, `tapMaximum` and `doubleTapWindow`. Shifting the harness copy does not change the lets. There is no `VoiceWalkClock` static for the Control/Option mirror or the cut override.

The agreement walk is not the search's whole move list. It adds interrupt, sweep, deliver, catchUp, busy, flip, mouse, missUp and waitLate where that run's machine has them, and it runs over every `WalkRun`. `waitHalfSecond` stays on the search only. A repeated keyDown is not a separate adapter event: toggle releases a key that is already down. Focus loss is the tiling matcher's result, not a talk-key event.

## Changes

| File | Change |
|------|--------|
| `Sources/ZeusCore/VoiceKeyMachine.swift` | Timing values are `let`. |
| `Tests/ZeusCoreTests/VoiceKeyWalkTests.swift` | Harness clock, agreement moves, unpinned bounds. |
| `Sources/Zeus/Pointing/PointingHotkeyMonitor.swift` | Watchdog period is `PointingKeyGesture.watchdog`. |
| `Sources/ZeusCore/TopBar/NotchClosedBodyLayout.swift` | `rowLayout` clips music to the box. |
| `Sources/Zeus/TopBar/TopBarViews.swift` | The row passes the art and bars proposals and clips the music container. |

## Local Verification

Planner and closed-loop selftests on Linux. The Swift walk and the owned-window wing test were not executed here.
