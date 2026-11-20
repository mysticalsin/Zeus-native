# Plan debate: Murmur mic first

Status: pending challenger. Rounds used: 0 of 3.

## Plan

Key down plays the start cue, opens the microphone, then reads the focused field. The reads use the turn generation already started for that key down. A failed open skips the reads.

Failing test: `theContextIsReadAfterTheMicrophoneOpens`.

TEST COMMAND: `swift test --filter theContextIsReadAfterTheMicrophoneOpens`

## Author position

The four reads that touch the focused app and field move to after a successful open. Permission checks stay before the cue. The existing two-argument `beginCapture` remains, and calls the new overload with an empty follow-up. Risk is high because a late focus read could name a different field than the one under the cursor at key down.

## Open challenge questions

1. Can reading focus after the microphone opens pick the wrong field, if the person clicks elsewhere while the device is still starting?

## Challenger: Devin the Dev
