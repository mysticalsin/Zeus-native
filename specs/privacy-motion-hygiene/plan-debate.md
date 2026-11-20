# Plan debate: privacy and motion hygiene

Status: pending challenger. Rounds used: 0 of 3.

## Plan

Redact secrets in the command log, create that file as mode 0600, prune old dictation audio on turn end at most once each 15 minutes, and send overlay and avatar animations through `Motion.reducible`.

Failing test: `aRecordedCommandHasItsTokenRedacted`.

TEST COMMAND: `swift test --filter aRecordedCommandHasItsTokenRedacted`

## Author position

`record` replaces the secret and keeps the rest of the line. The file mode is set on create and again after every write. Prune uses the existing store function. No new timer. `Motion.reducible` returns the same animation when Reduce Motion is off, and nil when it is on. Preferences.swift is not edited, and the system setting is not written.

## Open challenge questions

1. Can a secret still reach the log inside a second command, a quoted value, or a header the patterns do not name?

## Challenger: Devin the Dev
