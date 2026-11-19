# Plan: approval queue

## Done when

A press that does not name the card on screen does not approve it. A stale id on the button, the allow shortcut, a VoiceOver action, or a double-click does not approve the next card, including after the quiet interval. An Allow aimed at a card the terminal already answered does not approve a different command.

## Failing test

`aNilCardIDDoesNotApprove` in `Tests/ZeusAppTests/ApprovalHighPathTests.swift`. On `813e072d` a missing card id allows the card that is up.

TEST COMMAND: `swift test --filter aNilCardIDDoesNotApprove`

## Also required

- `aStaleButtonIDDoesNotApprove`
- `aStaleAllowShortcutDoesNotApprove`
- `aStaleVoiceOverActionDoesNotApprove`
- `aStaleDoubleClickDoesNotApprove`
- `aDoubleClickAfterTheQuietIntervalDoesNotApproveTheNextCard`
- `anAllowShortcutAfterTheQuietIntervalDoesNotApproveTheNextCard`
- `anAllowOnACardTheTerminalAlreadyAnsweredDoesNotApproveADifferentCommand`

The Mac mutant is still not run. Linux does not prove it.
