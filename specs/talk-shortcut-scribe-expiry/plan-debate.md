# Plan debate: talk shortcut and scribe expiry

Status: pending challenger. Rounds used: 0 of 3.

This file is the author's plan and the questions for the challenger. The challenger section is empty until Devin the Dev writes in it.

## Plan

A Record tap after the offer has left, or after a newer offer replaced it, does not start Scribe. A tap on the offer that is still up does start it.

Failing test: `aLateTapOnAnExpiredOrReplacedOfferDoesNotStartRecording` in `Tests/ZeusCoreTests/ScribeAutoStartTests.swift`. On `347fef29` the tap starts recording. The no-tick cases are `aTapPastThePromptingDeadlineWithoutATickDoesNotStart`, `aTapPastTheUpcomingDeadlineWithoutATickDoesNotStart`, and `aTapPastTheHeadsUpOfferUntilWithoutATickDoesNotStart`.

TEST COMMAND: `swift test --filter aLateTapOnAnExpiredOrReplacedOfferDoesNotStartRecording`

`liveOffer(matching:now:)` in `Sources/ZeusCore/Scribe/ScribeAutoStart.swift` returns the meeting only when the key matches and the pointer is inside, or `now` is still before the deadline or `offerUntil`.

## Author position

The tap carries the offer. Start requires that offer to still be live. The shipped ask timeout stays 20 seconds. "Start automatically" is unchanged. The no-tick tests keep the state at prompting, upcoming, or armed and tap past the deadline with the pointer outside. A pointer resting on the card still keeps that offer live after the deadline. That is the existing hover grace, not a second search. Native QA of a late tap on the built app is still pending. Risk is high: a late tap can start a microphone capture.

## Open challenge questions

1. `pointerInside || now < deadline` still returns the meeting after the deadline when the pointer is inside. Is that grace, or a late tap that still starts recording?
2. The failing test sets `askTimeout` to 10. The shipped ask timeout is 20 seconds. Does the test pin the shipped timeout, or only a fixture clock?
3. Is the pending late-tap run on the built app a merge blocker for this head?
4. `TalkHold.swift` and `ScribePopupLifecycle.swift` still have no production caller. Are they in this change, or out of it?

## Challenger: Devin the Dev
