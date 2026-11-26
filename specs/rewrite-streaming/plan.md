# Plan: rewrite streaming

## Done when

The rewrite reads stdout while the process is running, so a large reply cannot fill the pipe and stall. The notch uses the existing rewriting phase, set before the process returns. The timeout stays 45 seconds. A mode with an empty prompt never asks for a rewrite.

## Failing test

`aLargeOutputIsReadWhileTheProcessRuns` in `Tests/ZeusCoreTests/ClaudeRewriterTests.swift`. On `d6d45dde` `RewriterStream` does not exist, so the test does not compile.

TEST COMMAND: `swift test --filter ClaudeRewriterTests`

Also `theTimeoutStaysFortyFiveSeconds`.

## Out of scope

Speech capture, the voice-key machine, and new windows or animations.
