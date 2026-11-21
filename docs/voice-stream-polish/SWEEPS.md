# Voice stream polish sweep

2026-11-21. Branch `zeus-bot/voice-stream-polish-v2`. Lens: clicks at joins, primer length, pause at clause boundaries, French chunking, cancellation tails.

This branch does not carry the parked non-commercial companion stack. `speakKokoro` is the clause writer: it accepts only `zeus.synthetic`, renders one clause at a time through `ClauseSpeechScheduler`, and schedules the first clause before the rest of the reply.

## Findings

1. **Clicks on short joins.** A buffer shorter than the 20 ms crossfade was concatenated. A step from +0.8 to -0.8 was 1.6. The join now crossfades over the overlap both sides can spare. The short-buffer step stays under 0.25. Long sines still use the full 20 ms fade.
2. **Primer.** 60 ms of silence plus a 10 ms fade-in, inside the 40-80 ms window. Left as-is. A Bluetooth route can need longer than 60 ms; that sits outside this cap.
3. **Clause pause.** The scheduler fades a clause out over 10 ms, inserts 90 ms of silence, and fades in every later clause. Contiguous PCM frames from the feeder are still not overlap-added.
4. **French and English edges.** A narrow no-break space before `?` already split, and that case is now locked. `1.` in English and French was its own chunk; a bare number is a list marker, not a sentence end. `U.S.A.` before a lowercase word stays in the sentence. `No.` stays with the number. `。` ends a sentence. Periods inside URLs, emails, and decimals such as `3.14` do not. A period after a URL still ends the sentence.
5. **Cancellation.** A cancel during the first render schedules nothing. Once any clause audio is scheduled, a later cancel does not fall through to the next engine.
6. **Loudness on Kokoro speech.** A single gain cannot hold both -16 LUFS and -1 dBTP on this file. The long-answer crest is about 17 dB, so the limiter lands near -17.8 LUFS on the full reply and -16.8 LUFS on the first clause, with the true peak at -1.0 dBTP. Sine and noise fixtures that sit under the ceiling still measure -16 LUFS. The limiter stays the last stage.

## Time to first audio

Proposed budget: **1.0 s** for a warm Kokoro first clause (40-90 characters) on an M-series Mac. That number was not measured on a Mac.

The injected-clock test spreads a 5.31 s full-render cost across the long answer by character count. The first clause (43 characters) is scheduled at about 0.32 s on that clock, before the rest of the render, and under the 1.0 s budget.

Linux harness numbers are in `qa/voice/clause-ttfa-linux.json`, from `qa/voice/measure_clause_ttfa.py` (kokoro-onnx 0.4.9, `bm_george`, speed 0.88, `en-gb`). They are not an M-series result.

| path | ttfa_s | integrated_lufs | true_peak_dbtp |
| --- | ---: | ---: | ---: |
| #145 fixture, full reply, before chunking | 5.313 | -21.784 | -4.856 |
| this host, full reply, before chunking | 4.645 | -21.847 | -5.044 |
| this host, first clause only, after chunking | 0.419 | -21.625 | -5.851 |
| this host, full reply after -16 LUFS then -1 dBTP |  | -17.803 | -1.000 |
| this host, first clause after -16 LUFS then -1 dBTP |  | -16.774 | -1.000 |

The 8 s, 20 s, 45 s, 700 ms, and 90 s wake timeouts were not changed. `VoiceTTSChain.firstAudioTimeout + 30` still covers every clause of the utterance, not only the first.
