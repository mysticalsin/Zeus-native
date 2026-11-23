# Plan debate: talk shortcut and scribe expiry

Status: round 1 of 3, pending challenger.

This file is the author's plan and the questions for the challenger. The challenger section is empty until Devin the Dev writes in it.

## Plan

A Record tap after the offer has left, or after a newer offer replaced it, does not start Scribe. A tap on the offer that is still up does start it.

Failing test: `x5ALateTapOnAnExpiredOrReplacedOfferDoesNotStartRecording` (marker X5) in `Tests/ZeusCoreTests/ScribeAutoStartTests.swift`. On `347fef29` the tap starts recording. The no-tick cases are `aTapPastThePromptingDeadlineWithoutATickDoesNotStart`, `aTapPastTheUpcomingDeadlineWithoutATickDoesNotStart`, and `aTapPastTheHeadsUpOfferUntilWithoutATickDoesNotStart`.

TEST COMMAND: `swift test --filter x5ALateTapOnAnExpiredOrReplacedOfferDoesNotStartRecording`

`liveOffer(matching:now:)` in `Sources/ZeusCore/Scribe/ScribeAutoStart.swift` returns the meeting only when the key matches and the pointer is inside, or `now` is still before the deadline or `offerUntil`.

## Author position

The tap carries the offer. Start requires that offer to still be live. The shipped ask timeout stays 20 seconds. "Start automatically" is unchanged. The no-tick tests keep the state at prompting, upcoming, or armed and tap past the deadline with the pointer outside. A pointer resting on the card still keeps that offer live after the deadline. That is the existing hover grace, not a second search. Native QA of a late tap on the built app is still pending. Risk is high: a late tap can start a microphone capture.

## Open challenge questions

1. `pointerInside || now < deadline` still returns the meeting after the deadline when the pointer is inside. Is that grace, or a late tap that still starts recording?
2. The failing test sets `askTimeout` to 10. The shipped ask timeout is 20 seconds. Does the test pin the shipped timeout, or only a fixture clock?
3. Is the pending late-tap run on the built app a merge blocker for this head?
4. `TalkHold.swift` and `ScribePopupLifecycle.swift` still have no production caller. Are they in this change, or out of it?

## Challenger: Devin the Dev

Round 1, on head 501b5225290404b4e18d582ef0337088dbdf4316 (tree f447801f). CONSENSUS (Devin): OBJECTIONS.

1. Hover grace: a pointer resting on the card can count as grace only if it's bounded. As written, a card left under the pointer keeps its offer live forever, so a tap minutes later starts the microphone. Change: cap the grace (for example deadline + N seconds, with N named in decision.md) and end it when the pointer leaves. Add tests for the pointer inside past the cap (no start), inside within the cap (start), and a replaced offer with the pointer inside (no start, because the key doesn't match).
2. The fixture timeout of 10 doesn't pin the shipped 20 seconds. Add a test that reads the production default and asserts 20. Run one late-tap case on that default, not on a fixture value.
3. Yes, the native late-tap run on the built app is a merge blocker. This is HIGH risk and involves microphone capture. A non-author runs it on the Mac within the limits: at least 6 GiB free, /Applications/Zeus.app untouched (run from the build output), and no ci_motion_profile.py. Record it with a screenshot or log showing no recording starts.
4. TalkHold.swift and ScribePopupLifecycle.swift stay out of this change. Open a ticket to wire them or delete them. Don't grow this PR.
5. Factory: plan.md isn't in the tree, and the body has no rollback target and no unslop table. Add all three.

Linux gate on this head: PASS. Suites 466/16/49 and 118 scribe tests, twice. The always-true and plus-one-second mutants are killed. The H-1 walk blob is identical to #19's.

## Author response, round 1

N is `ScribeAutoStartTiming.hoverGrace`, 4 seconds, named in `decision.md`. A pointer inside the card can start a recording only until deadline + N. When the pointer leaves, that extra grace ends and a tap uses the offer's own deadline. `aPointerInsidePastTheHoverCapDoesNotStart`, `aPointerInsideWithinTheHoverCapStarts`, `aPointerInsideOnAReplacedOfferDoesNotStart`, and `aPointerThatLeavesEndsTheHoverGrace` are the tests. The ask timeout stays 20 seconds. `theProductionAskTimeoutIsTwentySeconds` reads the default, and `aLateTapOnTheProductionAskTimeoutDoesNotStart` uses that default.

The native late-tap run is still pending. It is a merge blocker. `docs/late-tap-qa.md` is the recipe. Nobody has run it on this head.

`TalkHold.swift` and `ScribePopupLifecycle.swift` are not wired or deleted here. The ticket is `specs/talk-shortcut-scribe-expiry/ticket-talkhold.md`. The 45 s slow-start is unchanged.
