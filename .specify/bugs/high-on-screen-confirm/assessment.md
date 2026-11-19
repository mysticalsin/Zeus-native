# Bug Assessment: High-risk confirm accepts a second shortcut or spoken yes

- **Slug**: high-on-screen-confirm
- **Created**: 2026-11-19
- **Source**: pasted text (Sentinel on approval-queue 15073690)
- **Verdict**: valid
- **Severity**: high

## Symptom

Under Reduce Motion or VoiceOver, a second Control-Option-Y or a second spoken yes allows a high-risk request. A release outside the Allow button can also finish a hold. The hold clock is a wall clock.

## Root Cause Hypothesis

`.secondConfirm` treats every activation as the on-screen button. `holdingSince` is a `Date` and is not tied to the request id. Confidence: high.
