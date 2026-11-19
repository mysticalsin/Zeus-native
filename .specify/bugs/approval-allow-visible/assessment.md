# Bug Assessment: Approval card shows Deny and hides the command

- **Slug**: approval-allow-visible
- **Created**: 2026-11-19
- **Source**: pasted text
- **Verdict**: valid
- **Severity**: high

## Symptom

The approval card could show only Deny, with the command hidden and a line about answering in the terminal. Allow was blank unless a modifier was held. After the countdown the card could stay up.

The expected card always shows Allow and Deny. The command, tool, and file stay visible unless the Mac is locked or the screen is shared or recorded, and then the card says why. The card leaves when the countdown ends. High risk still uses a visible Allow that is held.

## Reproduction

1. Raise an approval, including a high-risk one and one whose detail has its own actions.
2. Read the buttons. Both Allow and Deny must be visible. High risk Allow is a hold.
3. Lock the Mac, or share the screen. The command hides and the card says why. Unlock and stop sharing. The command returns.
4. Let the countdown reach its deadline. The card is gone.

## Suspected Code Paths

- `Sources/ZeusCore/ApprovalCard.swift` — `buttons`, `showsCommand`, `hiddenReason`, `stillShown`.
- `Sources/Zeus/Notch/NotchView.swift` — `ApprovalBody` used a hidden-details branch that left only Deny, and button titles that were empty unless modifiers were held.
- `Sources/Zeus/Notch/NotchController.swift` — the timeout task must clear the card when `stillShown` is false.

## Root Cause Hypothesis

Two rules were wider than the report. Hiding details for any privacy flag removed Allow and the command. Button titles depended on keycaps being held, so the label was empty. The countdown slept and did not always clear the card. Confidence: high, from the tests added with the fix.

## Proposed Remediation

**Preferred**: Always return Allow and Deny. Hide the command only for lock or screen share, with a reason. Clear the card when the deadline has passed. Keep the high-risk hold on the visible Allow button.

**Files likely to change**:

- `Sources/ZeusCore/ApprovalCard.swift`
- `Sources/Zeus/Notch/NotchView.swift`
- `Sources/Zeus/Notch/NotchController.swift`
- `Tests/ZeusCoreTests/ApprovalCardTests.swift`

**Tests to add or update**:

- Every risk, hidden or not, still has Allow and Deny.
- The command stays unless the Mac is locked or the screen is shared.
- The card is not shown once the deadline has passed.

## Risks & Considerations

- A high-risk Allow is still a hold. Making it a plain tap would weaken the gate.
- The hover layout must not grow to fit the card. That is the notch-bounds bug, not this one.

## Open Questions

- The installed app may be an older build than this source. The hosted job is the check that this head compiled and the tests passed.
