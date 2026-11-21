# Voice stream polish sweep

2026-11-21. Branch `zeus-bot/voice-stream-polish`. Lens: clicks at joins, primer length, pause at clause boundaries, French chunking, cancellation tails.

## Merge

PR #229 (`0cb57f7a`, `zeus-bot/fix-speaker-persona-voice`) merged with `git merge --no-ff`. Git auto-merged `Speaker.swift`. There was no conflict to resolve. `speechOutput` stayed `VoiceStreamPolish()`. `PersonaSpeakRoute` and the other #229 files were not edited after the merge.

`Speaker.speakKokoro` still renders the whole line to one WAV and then schedules it. That function lives in a #229 file, so this sweep did not change it. The clause path is `VoiceStreamPolish.speakClauses` / `ClauseSpeechScheduler`, which runs each clause through the `SpeechOutputProcessing` seam and schedules it before the next clause renders.

## Findings

1. **Clicks on short joins.** A buffer shorter than the 20 ms crossfade was concatenated. A step from +0.8 to -0.8 was 1.6. The join now crossfades over the overlap both sides can spare. The short-buffer step stays under 0.25. Long sines still use the full 20 ms fade.
2. **Primer.** 60 ms of silence plus a 10 ms fade-in, inside the 40–80 ms window. Left as-is. A Bluetooth route can need longer than 60 ms; that sits outside this cap.
3. **Clause pause.** An equal-power crossfade across a clause boundary smears the last phoneme into the next word. The scheduler fades the clause out over 10 ms, inserts 90 ms of silence, and fades the next clause in. Contiguous PCM frames from the feeder are still not overlap-added.
4. **French and English edges.** A narrow no-break space before `?` already split, and that case is now locked. `1.` in English and French was its own chunk; a bare number is a list marker, not a sentence end. A period glued to the end of a URL was swallowed, so the next sentence stuck to the link; that trailing `.` `!` `?` is peeled off. `c.-à-d.`, `M.`, the decimal comma, and guillemets still pass.
5. **Cancellation.** `process` still stops at the cut and the next buffer is empty, with no fade appended after the cut. The scheduler does not schedule a clause that was cancelled while it rendered.
6. **Loudness on Kokoro speech.** A single gain cannot hold both -16 LUFS and -1 dBTP on this file. The long-answer crest is about 17 dB, so the limiter lands near -17.8 LUFS on the full reply and -16.8 LUFS on the first clause, with the true peak at -1.0 dBTP. Sine and noise fixtures that sit under the ceiling still measure -16 LUFS. The limiter stays the last stage.

## Time to first audio

Proposed budget: **1.0 s** for a warm Kokoro first clause (40–90 characters) on an M-series Mac. That number was not measured on a Mac.

The injected-clock test spreads a 5.31 s full-render cost across the long answer by character count. The first clause (43 characters) is scheduled at about 0.32 s on that clock, before the rest of the render, and under the 1.0 s budget.

Linux harness numbers are in `qa/voice/clause-ttfa-linux.json`, from `qa/voice/measure_clause_ttfa.py` (kokoro-onnx 0.4.9, `bm_george`, speed 0.88, `en-gb`). They are not an M-series result.

| path | ttfa_s | integrated_lufs | true_peak_dbtp |
| --- | ---: | ---: | ---: |
| #145 fixture, full reply, before chunking | 5.313 | -21.784 | -4.856 |
| this host, full reply, before chunking | 4.645 | -21.847 | -5.044 |
| this host, first clause only, after chunking | 0.419 | -21.625 | -5.851 |
| this host, full reply after -16 LUFS then -1 dBTP |  | -17.803 | -1.000 |
| this host, first clause after -16 LUFS then -1 dBTP |  | -16.774 | -1.000 |

The 8 s, 20 s, 45 s, and 700 ms provider timeouts were not changed.
