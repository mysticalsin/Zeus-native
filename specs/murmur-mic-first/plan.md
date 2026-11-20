# Plan: Murmur starts listening when Right Command goes down

## Done when

Key down plays the start cue, then opens the microphone, then reads the focused app, the focused field, the mode and any selection. Those reads stay on the same turn generation and the same `DictationTurnContext`. A failed open reads none of them and leaves no turn.

## Failing test

`theContextIsReadAfterTheMicrophoneOpens` in `Tests/ZeusCoreTests/DictationCueRuleTests.swift`. On `d6d45dde` the call `beginCapture(cue:open:afterOpen:)` does not exist, so the test does not compile.

TEST COMMAND: `swift test --filter theContextIsReadAfterTheMicrophoneOpens`

Also `aFailedOpenReadsNoContext`, and `keyDownOpensTheMicBeforeReadingTheFocusedField` in `Tests/ZeusAppTests/DictationBeginOrderTests.swift`.

## Out of scope

Speech engine reuse, Apple recognition, level redraws, and the voice-key machine.
