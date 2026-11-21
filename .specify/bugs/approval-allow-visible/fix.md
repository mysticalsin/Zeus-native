# Bug Fix: Approval card shows Deny and hides the command

- **Slug**: approval-allow-visible
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Allow and Deny are always titled. The command hides only while the Mac is locked or the screen is shared, and the card says why. The timeout clears the card when the deadline has passed. High risk still holds the visible Allow button.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Sources/ZeusCore/ApprovalCard.swift` | modified | `buttons`, `showsCommand`, `hiddenReason`, `stillShown`. |
| `Sources/Zeus/Notch/NotchView.swift` | modified | Both buttons use those titles. The hidden-details Deny-only branch is gone. |
| `Sources/Zeus/Notch/NotchController.swift` | modified | Lock and share are copied onto the card. The timeout clears it. |
| `Tests/ZeusCoreTests/ApprovalCardTests.swift` | modified | The three rules above. |

## Tests Added or Updated

- `ApprovalCardTests.everyArrivalShowsAllowAndDeny`
- `ApprovalCardTests.theCommandStaysVisibleUnlessTheMacIsLockedOrTheScreenIsShared`
- `ApprovalCardTests.theCardLeavesWhenTheCountdownEnds`

## Local Verification

- Commands run: none on this Linux checkout. The app target does not compile here.
- Manual checks: `buttons` ignores `detailsHidden` and `detailHasOwnActions` and always returns both titles.

## Deviations from Assessment

The integration merge also added pointer and click-through state beside the lock flag. That was kept. It is not part of the button bug.

## Follow-ups

- Read the hosted app job for this head before calling the fix verified.
