# Bug Verification: Shipped talk walk

- **Slug**: voice-walk-state-bound
- **Tested**: 2026-11-19
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

The upper bound is a sanity window, not a pin. Run 44445566167 at SHA 48add1d1 printed `voice key walk A talk hold Control-Option confirm 0.15: 1883647 states`. That is evidence of the unfolded bug, not a count for this head. Pinning waits on a hosted log of this head. The test requires the folded search to be larger than the cuts-and-keys floor and smaller than that unfolded bug size.

## Checks Performed

| Check | Result | Notes |
|-------|--------|-------|
| Hosted log 44445557994 | read | `native-ClosedWingsNotchTests` passed. No 14 pt music failure. |
| Hosted log 44445566167 | read | The 14 pt failure is `theMusicWingsStayClearOfTheNotch`: wing frames differ by 14.0. Bug evidence at 48add1d1. |
| Swift walk and wing layout | not-run | Linux cannot compile the macOS target. |

## Residual Risks

The exact state count of this head is whatever the next hosted run A line prints.
