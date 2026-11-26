# Plan: privacy and motion hygiene

## Done when

The command log drops bearer tokens, password-like arguments, env assignments and URL credentials, and the log file is mode 0600. Old dictation audio is pruned again while the app is open, on a turn end and at most once each 15 minutes. Overlay and avatar animations go through `Motion.reducible`. Reduce Motion off keeps the same durations.

## Failing test

`aRecordedCommandHasItsTokenRedacted` in `Tests/ZeusCoreTests/HandsGateTests.swift`. On `d6d45dde` the recorded line still contains the token.

TEST COMMAND: `swift test --filter aRecordedCommandHasItsTokenRedacted`

Also `aRecordedCommandKeepsNonSecretArgs`, `aRecordedCommandLogIsPrivateToItsOwner`, and `qa/closed-loop/tests/test_motion_bypass_lint.py`.

TEST COMMAND: `python3 -m unittest discover -s qa/closed-loop/tests -p 'test_motion_bypass_lint.py' -v`

## Out of scope

Preferences.swift. The system Reduce Motion setting is never written.
