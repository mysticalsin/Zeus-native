# Approval sync

**Status**: Stub. Not started. 2026-11-19 13:07 BRT.

After a choice is answered in the terminal, Zeus's approval card lags or stays up, so the same choice is clicked twice.

This slice builds on the approval queue in PR #14. It is not part of Explain slice 001.

## Acceptance

- One answer in either place clears both within 300 ms (p50).
- No duplicate card and no stale card.
- Red-first tests cover both directions: an answer in the terminal clears the card, and an answer on the card clears the terminal choice.

No production work in this folder.

## Identity check

A Zeus approval is accepted by the camera face check in notch parity (R-023), not by typing a password. Touch ID or LocalAuthentication is the fallback. Both the card and the terminal choice stay up until that check succeeds, then both clear within 300 ms (p50). A failed check, a lockout, or the kill switch clears neither. The check stores no image and logs no biometric value. Details and the licence blocker are in `specs/004-notch-parity/spec.md` on `zeus-bot/notch-parity`.
