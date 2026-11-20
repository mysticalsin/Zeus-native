# Bug Fix: High-risk confirm accepts a second shortcut or spoken yes

- **Slug**: high-on-screen-confirm
- **Fixed**: 2026-11-19
- **Status**: applied

## Summary

Reduce Motion and VoiceOver use an on-screen confirm. It arms on the first button press, allows on a later button press after 0.4 s and before 8 s, and ignores shortcut and voice. A hold clears on release and cancel, and a release outside the button does not allow. The hold and the helper deadline use a monotonic clock. The audit drops U+2028 and U+2029.

## Tests

- `ApprovalQueueTests.aPlainActivationDoesNotAllowHigh`
- `ApprovalHighPathTests` for the controller, the shortcut, the spoken yes, and a release outside the button
