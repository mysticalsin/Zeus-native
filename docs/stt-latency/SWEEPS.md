# STT latency sweeps

Branch `zeus-bot/stt-latency`. Draft PR #249.

## 2026-11-21 05:22 UTC — UX polish and motion (listening indicator and endpoint feel)

No open review comments, review threads, or failing checks were on head `2d6e059` when this sweep started. `release-scripts` and `extension` had succeeded. `app` and `feature-map` were still queued. This lens was not logged before.

### Findings

1. A pause in the middle of a phrase became the endpoint silence. `STTLatencyTrace.mark` keeps the first time, and speech resuming only cleared the local silence flag. On the injected clock, silence stayed at 200 ms and the key-up endpoint at 900 ms was 700 ms later, past the 400 ms silence budget. The listening indicator itself still leaves "listening" at key-up (`VoiceTurnController.release` sets think). The bad feel was the VAD stage, not a stuck orb.
2. A deliver for an older press wrote `delivered_to_ui` on the utterance that had replaced it. Cancel of the old press did not stop that write after the next begin. Rapid start/stop (20 cycles, alternating talk-hold and murmur-tap) showed the same cross-talk.
3. A long quiet stretch endpoints at the crossing sample, silence plus the 400 ms budget. Silence at 100 ms, next observed sample at 10_000 ms, measured endpoint 500 ms. The stamp is not the late clock.

### Fixes

Speech that resumes before the endpoint clears `silence_detected`, so the next quiet stretch is the one that counts. `STTUtteranceBook.deliver` accepts only the open generation, and `SpeechInput.noteDelivered` uses that rule. A stop captured its generation and does not mark the replacement turn.

The 8 s, 20 s, and 45 s timeouts were not changed. No new dependencies.

### Evidence

Red `d88e83d`. `python3 qa/portable-core/prepare.py --group regressions --output /tmp/zeus-stt-ux-red2 --run` on Linux, Swift 6.0.3: `Test run with 89 tests failed after 0.017 seconds with 44 issues.` Failing: `aMidPhrasePauseDoesNotBecomeTheEndpointSilence` (silence 200, gap 700), `aLateDeliveryDoesNotCloseTheNextUtterance`, `rapidStartStopCyclesDoNotCrossDeliver` (38 issues), `cancelDropsALateDeliver`. `aLongSilenceEndpointsAtTheBudgetNotAtTheLateSample` passed.

Green `2e1c380`. Same command, output `/tmp/zeus-stt-ux-green`: `Test run with 89 tests passed after 0.015 seconds.` Suite "STT latency" passed after 0.012 seconds.

## 2026-11-21 06:10 UTC — Inspector APP-FIT at be52c054

Inspector FAILed head `be52c054` (APP-FIT STALE, report sha 6c4d2ba5). No push until this round. The 450 ms final wait was not changed. The 8 s, 20 s, 45 s, 700 ms, and 90 s timeouts were not changed.

### Findings

1. `SpeechInput.noteDelivered` passed `traceCancelled`, but `aCancelledDeliverIsRefused` called `accepts` with literal Bools. Hardcoding true or false stayed green.
2. The hands-free poll called `STTQuiet.reached` with a threshold chosen in the app, so a poll-local `>` stayed green. Effective silence was the legacy 1000 ms, not the 400 ms production budget.
3. A late sample stamped `clock.nowMs`. Silence at 100 ms and the next sample at 10_000 ms recorded 10_000 ms. The crossing sample is 500 ms. SWEEPS line 13 said 500 ms while the test expected 10_000 ms.
4. The quiet comment still said hands-free stays at 1000 ms. The eight gate tests were not bound on `F01.stt-latency`.
5. `endpoint!` at the budget test crashed if the stamp was missing. A stale tap updated `onLevel` after the loudness gate refused the buffer.

### Fixes

`noteDelivered` calls `STTLiveDelivery.allowed`, which reads the stored flag. Non-wake hands-free calls `STTHandsFree.quietEnded` (`>=` against `STTSessionPolicy.production.silenceToEndpointMs`, 400). The legacy policy still records 1000 ms and is not effective. Pending Tony. One-line revert of that decision: `git revert --no-edit 3f885233f938584e6ed41a74c4a54eff7f692747`. The endpoint stamp is silence plus the budget. The level meter uses the same owner check as loudness. The eight tests are on `F01.stt-latency`.

### Evidence

Red `f3c0b03897caa7120496830b5a41507948d85f6c`. `python3 qa/portable-core/prepare.py --group regressions --output /tmp/zeus-stt-inspector-red --run --jobs 4` on Linux, Swift 6.0.3: `Test run with 98 tests failed after 0.020 seconds with 10 issues.` Failing: `quietReachesExactlyAtTheHandsFreeThreshold` (threshold 1000, exact 400 did not count), `endpointBoundariesKillComparisonMutants` (late stamp 501), `aLongSilenceEndpointsAtTheBudgetNotAtTheLateSample` (stamp 10000), `aCancelledDeliverIsRefused`, `aStaleTapDoesNotPublishLevel`.

Green `3f885233f938584e6ed41a74c4a54eff7f692747`. Same command, output `/tmp/zeus-stt-inspector-green`: `Test run with 98 tests passed after 0.020 seconds.` Suite "STT latency" passed after 0.012 seconds.

## 2026-11-21 06:14 UTC — Devin gate r31fb46ae on be52c054

Folded into the inspector round. The 450 ms final wait and the 8 s, 20 s, 45 s, 700 ms, and 90 s timeouts were not changed. Hands-free silence stays the 400 ms production budget, pending Tony. The 450 ms final wait is pending Tony confirmation.

### Findings

1. `batchGiveUpMs` for 1 s of audio was only bounded by `<= 2000`. An `audio * 2` mutant returns 2000 ms and still passed.
2. Deleting the `hangGiveUpMs >= 30_000` branch still passed. The 30000 ms floor was measured on red `c880bb0` and not on the green suite.
3. `STTUtteranceBook.mark` without `!cancelled` still passed. The stale-generation test does not cancel the open utterance.
4. `OffMainAudioCallbacks.recognizeFinal` scheduled its cancel from an inline expression. Linux cannot run the Speech task. The wait itself is a pure function of the production budget.
5. SWEEPS line 13 now states the measured crossing sample: silence at 100 ms, next sample at 10_000 ms, endpoint 500 ms.

### Fixes

The production formula is `min(2_000, max(hangGiveUpMs, audio / 2))`. One second of audio is 800 ms. The legacy floor is `max(30_000, audio * 3)`. A cancelled utterance refuses `mark`. `STTFileGiveUp.seconds` is what the file timer calls. For the 4_000 ms stand-in that is 2 s.

### Evidence

Red `b8ccf6ccb033a4a6b99d3f88f2aa844ff6dcd2eb`. `python3 qa/portable-core/prepare.py --group regressions --output /tmp/zeus-stt-devin-red --run --jobs 4` on Linux, Swift 6.0.3: `Test run with 102 tests failed after 0.020 seconds with 9 issues.` Failing: `batchGiveUpPinsTheExactFormula` (1 s audio gave 2000), `legacyBatchGiveUpKeepsTheThirtySecondFloor` (short 2000, long 2000), `aCancelledMarkDoesNotWriteTheOpenUtterance` (mark wrote speech at 40 ms), `fileRecognitionGiveUpUsesTheProductionBudget` (30 s).

Green `67ae56755af96b6f3f92392785cb7326fb0ffce7`. Same command, output `/tmp/zeus-stt-devin-green`: `Test run with 102 tests passed after 0.016 seconds.` Suite "STT latency" passed after 0.014 seconds.
