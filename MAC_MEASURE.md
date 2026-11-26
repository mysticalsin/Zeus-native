# Speech-to-text measurement (Mac)

This is the physical repro for the talk hold and the Murmur tap. It runs in a detached clone. It does not open the live microphone and it does not play a recording of a person. The clip is the Mac's own speech synthesizer (`say`).

PR #98 has to merge before the packaged app builds. Until then the script still prints the injected-clock before and after numbers, then exits 2.

```sh
bash scripts/stt-latency-mac.sh
```

## What it prints

For each path (`talk-hold`, `murmur-tap`) and each scenario (`release`, `silence`), before then after:

```
path=talk-hold key_down=0
capture: capture_start=15
vad: speech_start=40 silence_detected=- endpoint_fired=600
asr: model_ready=0 first_partial=40 final_transcript=1050
delivery: delivered_to_ui=1100
failure=none
```

`key_down` is milliseconds zero. The other numbers are milliseconds after that.

- capture: `capture_start`
- vad: `speech_start`, `silence_detected`, `endpoint_fired`
- asr: `model_ready`, `first_partial`, `final_transcript`
- delivery: `delivered_to_ui`

Then a failure rate per path:

```
BEFORE failure_rate path=talk-hold attempts=4 failures=4 rate=1.000
AFTER failure_rate path=talk-hold attempts=4 failures=0 rate=0.000
```

A failure is no text, empty text, a hang, or a timeout. A partial that is delivered inside the budget counts as success.

The injected clock is the harness (`zeus-cli stt-latency`). Key down and key up are events on that clock. The packaged section, once the app builds, feeds `stt-synthetic.wav` through `debug dictate-file` and prints any new `stt-latency` / `stt-failure` log lines. Those lines are the same fields, measured on the running app, and they do not contain transcript text.

## Budgets (after)

On-device stays the default. Both paths use the same recognition budget. Murmur has a slightly longer handoff because the text lands in the dictation controller.

| Stage | Talk hold | Murmur tap |
| --- | --- | --- |
| key_down → capture_start | 80 ms | 80 ms |
| speech_start (one input buffer) | 40 ms | 40 ms |
| silence_detected → endpoint_fired | 400 ms | 400 ms |
| model_ready | once, at key down when prewarmed | once, at key down when prewarmed |
| endpoint_fired → final_transcript | 450 ms | 450 ms |
| final_transcript → delivered_to_ui | 50 ms | 80 ms |
| recognizer never calls back | cancel by 800 ms, batch cap 2 s | same |

The 8 s, 20 s and 45 s timeouts belong to other subsystems and are unchanged.

## Before, from the source (not a Mac run)

| Stage | Before | How it was derived |
| --- | --- | --- |
| endpoint → final | 2500 ms, and the task was not cancelled | `SpeechInput.stop` waited `2.5` and `finish(ifSession:)` did not cancel the task |
| batch recognizer give-up | at least 30000 ms | `AppleSpeechEngine` used `max(30, 3 × audio seconds)` |
| file recognition with no final | no timeout | `OffMainAudioCallbacks.recognizeFinal` returned only on `isFinal` or an error |
| silence endpoint | 1000 ms, reset by an unchanged partial | hands-free used `1000` ms and `onPartial` ran for every callback |
| model | loaded again per utterance, not at launch | no prewarm on the talk path; `beginUtterance` had no warm gate |
| Apple on-device, warm, whole clip | median 338 ms, p90 402 ms | `docs/dictation-bench.md`, M1 Pro, 2026-10-31. Not re-measured here |

The harness labels the 2500 ms / hang row `BEFORE` and the budget row `AFTER`.
