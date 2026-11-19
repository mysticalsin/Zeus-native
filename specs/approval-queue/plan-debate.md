# Plan debate: approval queue

Status: round 1 of 3, pending challenger.

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

Round 1, on head 813e072d8102d6ee6019cf1c6c91256f8332041b (tree 98aaea2b). CONSENSUS (Devin): OBJECTIONS.

1. One test isn't enough. The guard is `if let cardID, cardID != card.id { return nil }`, so a nil cardID passes straight through. Any allow path that sends no id approves whatever card is up. Change: make the card id non-optional at the request-approval site, or refuse when it's nil. Add one test per allow path (button, allow shortcut, VoiceOver action, double-click) that sends a stale id and expects no approval, plus one that sends a nil id and expects no approval.
2. Deferring the terminal-answer withdraw to spec 003 is acceptable on three conditions. It gets a named ticket. A test pins today's behaviour: Allow on a card already answered in the terminal must not approve a different command. And decision.md lists it as a residual.
3. The quiet interval needs a test for each input: a double-click, a VoiceOver action, and the allow shortcut, each landing just after a swap and once the interval has passed. The existing VoiceOver test covers one of the three.
4. The Linux selftest SURVIVES the named mutant (Ran 1, OK). So the Mac v3b mutant-v2 log on this exact head is the only proof. It must show `theProductionAllowClosureCarriesTheRequestID` FAIL with only NotchController.swift changed. Until that log exists, the mutant counts as not run.
5. Blocking from the gate, apart from the debate: `./scripts/typecheck-voice-key-walk.sh` exits 1 with `invalid redeclaration of 'FullWalkCache'` (lines 1720 and 1843). Keep only the H-1 version, the same blob as #19 and #15.
6. Factory: plan.md isn't in the tree, and the body has no rollback target and no unslop table. Add all three.

## Author response, round 1

A nil card id now returns without a verdict. The button, the allow shortcut, VoiceOver, and a double-click each have a stale-id test, and `aNilCardIDDoesNotApprove` sends no id. `releaseDisplayedPlan` and `commitDisplayedAnswers` pass the card id they are acting on.

`anAllowOnACardTheTerminalAlreadyAnsweredDoesNotApproveADifferentCommand` pins that an Allow aimed at a card the terminal already answered does not approve another command. Withdrawing that card stays in spec 003. The ticket is `specs/approval-queue/ticket-terminal-withdraw.md`, and `decision.md` lists it as a residual.

`aDoubleClickAfterTheQuietIntervalDoesNotApproveTheNextCard` and `anAllowShortcutAfterTheQuietIntervalDoesNotApproveTheNextCard` cover the two inputs the VoiceOver test did not. The VoiceOver case stays `aVoiceOverActionAcrossASwapDoesNotApproveTheNextCardOnceTheQuietIntervalHasPassed`.

`VoiceKeyWalkTests.swift` is the H-1 blob from `c1194abb`. `./scripts/typecheck-voice-key-walk.sh` exits 0 on this head. The Mac mutant log is still not run. The 45 s slow-start is unchanged.
