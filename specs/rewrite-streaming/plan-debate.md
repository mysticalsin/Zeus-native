# Plan debate: rewrite streaming

Status: pending challenger. Rounds used: 0 of 3.

## Plan

Read both pipes on background readers before the process runs. The process budget stays 45 seconds. The notch phase is the existing rewriting phase, entered before the await. A plain mode still has an empty prompt and does not call the rewrite.

Failing test: `aLargeOutputIsReadWhileTheProcessRuns`.

TEST COMMAND: `swift test --filter ClaudeRewriterTests`

## Author position

The readers start first, so a 1 MB write is taken off the pipe as it arrives. Stderr is read the same way, because a full error pipe stalls a process too. The 45 second kill stays on the process wait. No new window and no animation change.

## Open challenge questions

1. Can the last chunk of stdout be dropped if the process exits in the gap between the reader loop and the wait, or can a slow stderr reader hold the 45 second budget open after the process has already finished?

## Challenger: Devin the Dev
