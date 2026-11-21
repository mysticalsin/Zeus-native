# Plan: talk shortcut and scribe expiry

## Done when

A Record tap after the offer's own deadline does not start Scribe, including when the pointer has rested on the card for longer than the hover grace, and including when the pointer has left. A tap inside that grace, on the offer that is still the one on screen, does start it. The production ask timeout is 20 seconds.

## Failing test

`aPointerInsidePastTheHoverCapDoesNotStart` in `Tests/ZeusCoreTests/ScribeAutoStartTests.swift`. On `501b5225` a pointer left on the card keeps the offer tappable with no cap.

TEST COMMAND: `swift test --filter aPointerInsidePastTheHoverCapDoesNotStart`

## Also required

- `aPointerInsideWithinTheHoverCapStarts`
- `aPointerInsideOnAReplacedOfferDoesNotStart`
- `aPointerThatLeavesEndsTheHoverGrace`
- `theProductionAskTimeoutIsTwentySeconds`
- `aLateTapOnTheProductionAskTimeoutDoesNotStart`

The native late-tap run on the built app is still pending. It blocks merge.
