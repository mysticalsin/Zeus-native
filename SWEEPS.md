# STT latency sweeps

Branch `zeus-bot/stt-latency`. Draft PR #249.

## 2026-11-21 05:22 UTC — UX polish and motion (listening indicator and endpoint feel)

No open review comments, review threads, or failing checks were on head `2d6e059` when this sweep started. `release-scripts` and `extension` had succeeded. `app` and `feature-map` were still queued. This lens was not logged before.

### Findings

1. A pause in the middle of a phrase became the endpoint silence. `STTLatencyTrace.mark` keeps the first time, and speech resuming only cleared the local silence flag. On the injected clock, silence stayed at 200 ms and the key-up endpoint at 900 ms was 700 ms later, past the 400 ms silence budget. The listening indicator itself still leaves "listening" at key-up (`VoiceTurnController.release` sets think). The bad feel was the VAD stage, not a stuck orb.
2. A deliver for an older press wrote `delivered_to_ui` on the utterance that had replaced it. Cancel of the old press did not stop that write after the next begin. Rapid start/stop (20 cycles, alternating talk-hold and murmur-tap) showed the same cross-talk.
3. A long quiet stretch already endpoints at silence plus 400 ms, not at the late sample. Silence at 100 ms, next sample at 10_000 ms, endpoint at 500 ms. That case passed before the fix.

### Fixes

Speech that resumes before the endpoint clears `silence_detected`, so the next quiet stretch is the one that counts. `STTUtteranceBook.deliver` accepts only the open generation, and `SpeechInput.noteDelivered` uses that rule. A stop captured its generation and does not mark the replacement turn.

The 8 s, 20 s, and 45 s timeouts were not changed. No new dependencies.

### Evidence

Red `d88e83d`. `python3 qa/portable-core/prepare.py --group regressions --output /tmp/zeus-stt-ux-red2 --run` on Linux, Swift 6.0.3: `Test run with 89 tests failed after 0.017 seconds with 44 issues.` Failing: `aMidPhrasePauseDoesNotBecomeTheEndpointSilence` (silence 200, gap 700), `aLateDeliveryDoesNotCloseTheNextUtterance`, `rapidStartStopCyclesDoNotCrossDeliver` (38 issues), `cancelDropsALateDeliver`. `aLongSilenceEndpointsAtTheBudgetNotAtTheLateSample` passed.

Green `2e1c380`. Same command, output `/tmp/zeus-stt-ux-green`: `Test run with 89 tests passed after 0.015 seconds.` Suite "STT latency" passed after 0.012 seconds.
