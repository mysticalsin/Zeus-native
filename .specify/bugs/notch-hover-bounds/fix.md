# Bug Fix: Notch hover grows with a long notification

- **Slug**: notch-hover-bounds
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Hover size comes from `NotchLayoutBounds.size`. A notification sets a factor and does not add its height. The home body is the wider, shorter `GlanceTopBar` panel.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Sources/ZeusCore/TopBar/NotchLayoutBounds.swift` | modified | Hover uses `panelSize`. Notification height is not an input to that size. |
| `Sources/Zeus/Notch/NotchView.swift` | modified | `topBarPanelSize` delegates to the bounds. Peeks are clamped. |
| `Sources/ZeusCore/TopBar/GlanceTopBar.swift` | modified | Wider, shorter body. |
| `Tests/ZeusAppTests/NotchLayoutBoundsTests.swift` | added | The long note must match a plain hover and stay inside the maximum. |

## Tests Added or Updated

- `NotchLayoutBoundsTests.aLongNotificationDoesNotStretchTheHomeHover`
- `NotchLayoutBoundsTests.hoverWithANotificationMatchesAPlainHover`
- `NotchLayoutBoundsTests.everyPanelCombinationStaysInsideTheDesignedMaximum`

## Local Verification

- Commands run: none on this Linux checkout. The app target does not compile here.
- Manual checks: the hover branch of `size(_:)` does not read `approvalExtra`.

## Deviations from Assessment

None. The wider and shorter body was part of the same report and is on this branch.

## Follow-ups

- The hosted app job must render the notch-bounds snapshots. This note does not claim that render.
