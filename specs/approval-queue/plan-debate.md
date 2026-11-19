# Plan debate: approval queue

Status: pending challenger. Rounds used: 0 of 3.

This file is the author's plan and the questions for the challenger. The challenger section is empty until Devin the Dev writes in it.

## Plan

A press stays on its own card. After a swap, Allow does not approve the next card, including once the quiet interval has passed.

Failing test: `theProductionAllowClosureCarriesTheRequestID` in `Tests/ZeusAppTests/ApprovalHighPathTests.swift`. It fails when the allow closure at the request-approval site does not carry the card id.

TEST COMMAND: `swift test --filter theProductionAllowClosureCarriesTheRequestID`

Mac mutant, exactly one file: in `Sources/Zeus/Notch/NotchController.swift`, delete `cardID != card.id` from `if let cardID, cardID != card.id { return nil }`. Expected result: that test command FAILS on the Mac. The Linux selftest stays green, so the Mac log is the evidence.

Related: `aVoiceOverActionAcrossASwapDoesNotApproveTheNextCardOnceTheQuietIntervalHasPassed`.

## Author position

The production allow path has to carry the card id, and the quiet interval has to block every risk, including high. This head is that behavior. Answering in the terminal still does not withdraw the card. That gap is spec 003, not this change. Risk is high: a wrong allow approves a command the person did not mean.

## Open challenge questions

1. If the production closure carries the id but another allow path does not, does `theProductionAllowClosureCarriesTheRequestID` still pass? Is that one test enough?
2. Is leaving the terminal-answer withdraw to spec 003 acceptable on a high-risk approval change, or does this head have to close that hole?
3. Does the quiet interval cover a double-click, a VoiceOver action, and the allow shortcut, or can one of those still land on the next card?
4. The mutant deletes only `cardID != card.id` in that one `if`. Confirm the named test fails for that deletion alone, and that no other file has to change for the red result.

## Challenger: Devin the Dev
