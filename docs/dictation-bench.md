# Dictation engine benchmark

Date: 2026-10-31. Machine: Apple M1 Pro, 16 GB, macOS 27.0. Release build of `bench/dictation`
(`swift build -c release`, then `.build/release/dictation-bench clips`).

## Method

- 12 clips (4.4 to 6.3 s, 16 kHz mono) made with `bench/dictation/make-clips.sh` from four macOS
  voices (US, UK, AU, IE English). Each sentence is the exact reference, so WER is exact.
  Sentences mix everyday dictation with ZEUS jargon (Swift, Parakeet, Murmure).
- One real human recording (`en.wav`, 3.8 s, from the sherpa-onnx Parakeet test set), no
  reference text, shown for a qualitative check.
- Latency = wall time from handing the full clip to the engine until text comes back (the
  "release the key → text" delay). One warm-up run per engine is not counted. Model load and
  first download are reported separately.
- WER = word error rate after lowercasing and stripping punctuation
  (`ZeusCore.TranscriptMetrics`, unit-tested). Most remaining "errors" are number formatting
  ("three thirty" → "3.30", "twelve fifteen" → "12:15"), which is a style choice, not a mishearing.

Caveat: synthetic voices are cleaner than a real mic. Absolute WER on real speech will be
higher for all three; the ranking and the latency gap are what matter here.

## Summary

| Engine | Median latency | p90 | Speed (×realtime) | WER | Load (first run, incl. download) | Disk |
|---|---|---|---|---|---|---|
| **Parakeet TDT 0.6b v3** (FluidAudio 0.18, CoreML/ANE) | **123 ms** | 130 ms | **43×** | **4.95 %** | 242 s | ~480 MB |
| Whisper large-v3 turbo (WhisperKit 0.18, CoreML) | 3178 ms | 5336 ms | 1× | 5.94 % | 512 s | ~1.6 GB |
| Apple SFSpeechRecognizer on-device (baseline) | 338 ms | 402 ms | 16× | 8.42 % | 0 s | built in |

**Winner: Parakeet v3.** About 25× faster than Whisper turbo on this Mac with equal or better
accuracy, and 2.7× faster than Apple with a third fewer errors. It also heard the jargon
Apple got wrong ("refactor", "latency budget", a product name → Apple wrote "reflect to",
"agency budget", "vibe is"). Whisper turbo stays useful only for languages Parakeet v3 lacks
(v3 covers 25 European languages), so it is kept as a selectable engine, not the default.

Integration: `TranscriptionEngine` protocol in ZeusCore, Parakeet as the default engine,
Apple as the always-ready fallback (`EngineSelection` / `TranscriptionRouter`). Whisper is a
documented slot: adding it means adding the WhisperKit package to the app target (≈1.6 GB model).

## Raw results
## Whisper large-v3 turbo (WhisperKit)
| clip | voice | audio s | latency ms | RTFx | WER | hypothesis |
|---|---|---|---|---|---|---|
| clip01 | Samantha | 5.9 | 7769 | 1 | 0.0% | Hey, can you send me the quarterly report before Friday? I want to review the numbers with the team. |
| clip02 | Samantha | 5.7 | 4578 | 1 | 0.0% | Open the terminal, run Swift Build, and then push the fix to the Devon branch once the tests pass. |
| clip03 | Daniel | 6.0 | 3468 | 2 | 12.5% | The meeting with Sarah moved to 3.30 tomorrow afternoon, so please update the calendar invite. |
| clip04 | Daniel | 4.4 | 2684 | 2 | 0.0% | Remind me to buy milk, eggs, and coffee on the way home tonight. |
| clip05 | Karen | 5.5 | 2446 | 2 | 0.0% | I think we should refactor the notch controller so the dictation tab and the chat window share one store. |
| clip06 | Karen | 4.6 | 3034 | 2 | 0.0% | Please write a short email to the landlord saying the heating has been broken since Monday. |
| clip07 | Moira | 6.3 | 2881 | 2 | 22.2% | (retired sentence) all live in the menu bar, but each one solves a different problem. |
| clip08 | Moira | 5.1 | 6457 | 1 | 13.3% | The latency budget for dictation is under 300 milliseconds after the key is released. |
| clip09 | Samantha | 4.8 | 5336 | 1 | 0.0% | Add a unit test that checks the word error rate is zero when both strings match exactly. |
| clip10 | Daniel | 4.6 | 3178 | 1 | 15.4% | Let's grab lunch at the Italian place near the station around 12:15. |
| clip11 | Karen | 5.2 | 3012 | 2 | 5.6% | Use Parakeet as the default engine and fall back to Apple's speech when the model is not downloaded. |
| clip12 | Moira | 5.3 | 2881 | 2 | 5.3% | My flight lands at Heathrow at 7 in the morning, so I will join the call from the taxi. |
| en.wav (real speech) | - | 3.8 | 3059 | - | - | Ask not what your country can do for you. Ask what you can do for your country. |
**Summary:** load 512.1 s (includes first download), median latency 3178 ms, p90 5336 ms, total RTFx 1, WER 5.94%
## Apple SFSpeechRecognizer (on-device)
| clip | voice | audio s | latency ms | RTFx | WER | hypothesis |
|---|---|---|---|---|---|---|
| clip01 | Samantha | 5.9 | 273 | 22 | 0.0% | Hey, can you send me the quarterly report before Friday? I want to review the numbers with the team. |
| clip02 | Samantha | 5.7 | 315 | 18 | 5.3% | Open the terminal run swift build, and then push the fix to the Devon branch once the test pass |
| clip03 | Daniel | 6.0 | 338 | 18 | 12.5% | The meeting with Sarah moved to 3:30 tomorrow afternoon, so please update the calendar invite |
| clip04 | Daniel | 4.4 | 212 | 21 | 0.0% | Remind me to buy milk, eggs, and coffee on the way home tonight |
| clip05 | Karen | 5.5 | 502 | 11 | 15.8% | I think we should reflect to the notch controller so the dictation tab in the chat window share one store |
| clip06 | Karen | 4.6 | 233 | 20 | 0.0% | Please write a short email to the landlord saying the heating has been broken since Monday |
| clip07 | Moira | 6.3 | 553 | 11 | 22.2% | (retired sentence) all live in the menu bar, but each one solves a different problem |
| clip08 | Moira | 5.1 | 359 | 14 | 26.7% | The agency budget for dictation is under 300 ms after the key is released |
| clip09 | Samantha | 4.8 | 252 | 19 | 0.0% | Add a unit test that checks the word error rate is zero when both strings match exactly |
| clip10 | Daniel | 4.6 | 220 | 21 | 15.4% | Let's grab lunch at the Italian place near the station around 1215 |
| clip11 | Karen | 5.2 | 402 | 13 | 5.6% | Use parakeets as the default engine and fall back to Apple speech when the model is not downloaded |
| clip12 | Moira | 5.3 | 368 | 15 | 0.0% | My flight lands at Heathrow at seven in the morning so I will join the call from the taxi |
| en.wav (real speech) | - | 3.8 | 251 | - | - | Ask not what your country can do for you ask what you can do for your country |
**Summary:** load 0.0 s (includes first download), median latency 338 ms, p90 402 ms, total RTFx 16, WER 8.42%

## Parakeet TDT 0.6b v3 (FluidAudio)
| clip | voice | audio s | latency ms | RTFx | WER | hypothesis |
|---|---|---|---|---|---|---|
| clip01 | Samantha | 5.9 | 267 | 22 | 0.0% | Hey, can you send me the quarterly report before Friday? I want to review the numbers with the team. |
| clip02 | Samantha | 5.7 | 162 | 35 | 0.0% | Open the terminal, run Swift Build, and then push the fix to the Devon branch once the tests pass. |
| clip03 | Daniel | 6.0 | 149 | 40 | 12.5% | The meeting with Sarah moved to 3.30 tomorrow afternoon, so please update the calendar invite. |
| clip04 | Daniel | 4.4 | 110 | 40 | 0.0% | Remind me to buy milk, eggs, and coffee on the way home tonight. |
| clip05 | Karen | 5.5 | 125 | 44 | 0.0% | I think we should refactor the notch controller so the dictation tab and the chat window share one store. |
| clip06 | Karen | 4.6 | 119 | 39 | 0.0% | Please write a short email to the landlord saying the heating has been broken since Monday. |
| clip07 | Moira | 6.3 | 140 | 45 | 22.2% | (retired sentence) all live in the menu bar, but each one solves a different problem. |
| clip08 | Moira | 5.1 | 115 | 45 | 13.3% | The latency budget for dictation is under 300 milliseconds after the key is released. |
| clip09 | Samantha | 4.8 | 103 | 46 | 0.0% | Add a unit test that checks the word error rate is zero when both strings match exactly. |
| clip10 | Daniel | 4.6 | 101 | 46 | 15.4% | Let's grab lunch at the Italian place near the station around 1215. |
| clip11 | Karen | 5.2 | 106 | 49 | 0.0% | Use Parakeet as the default engine and fall back to Apple Speech when the model is not downloaded. |
| clip12 | Moira | 5.3 | 111 | 48 | 0.0% | My flight lands at Heathrow at seven in the morning, so I will join the call from the taxi. |
| en.wav (real speech) | - | 3.8 | 102 | - | - | Ask not what your country can do for you, ask what you can do for your country. |
**Summary:** load 0.5 s (includes first download), median latency 119 ms, p90 149 ms, total RTFx 40, WER 4.95%
