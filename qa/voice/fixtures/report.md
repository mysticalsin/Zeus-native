# OFFLINE ENGINE COMPARISON

OFFLINE ENGINE COMPARISON of Kokoro, ElevenLabs non-streaming, and Google Cloud TTS. This is not the live Zeus provider order (ElevenLabs > OpenAI > Gemini). It does not drive Murmure or Scribe.

Each row is one rendered script. Time to first audio uses the timing JSON when it records `first_audio_s`; otherwise it is the first non-silent sample in the WAV. Barge-in stop latency is present only when the timing JSON records both the request and the stop. FAIL and WARN are not ordinary rows.

| provider | script | ttfa_s | wav_onset_s | integrated_lufs | true_peak_dbtp | clipping_count | inter_chunk_gaps_s | speech_rate_wps | pitch_std_hz | barge_in_stop_latency_s | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| kokoro | 01-short-ack | 0.23 | 0.03 | -20.55 | -6.23 | 0 |  | 1.02 | 48.91 | not measured | PASS |
| kokoro | 02-long-answer | 5.31 | 0.04 | -21.78 | -4.86 | 0 | 27 gaps, longest 0.66s | 3.61 | 34.19 | not measured | WARN |
| kokoro | 03-numbers-dates-currency-code | 1.89 | 0.04 | -21.71 | -4.98 | 0 | 5 gaps, longest 0.61s | 2.07 | 26.68 | not measured | PASS |
| kokoro | 04-question | 0.43 | 0.03 | -21.10 | -5.35 | 0 | 1 gap, longest 0.11s | 3.30 | 44.54 | not measured | PASS |
| kokoro | 05-error | 0.90 | 0.02 | -21.69 | -5.23 | 0 | 4 gaps, longest 0.49s | 2.65 | 36.10 | not measured | PASS |
| kokoro | 06-markdown-url | 1.88 | 0.03 | -21.70 | -6.04 | 0 | 10 gaps, longest 0.63s | 0.94 | 39.40 | not measured | PASS |
| kokoro | 07-french | 0.87 | 0.04 | -21.49 | -5.93 | 0 | 3 gaps, longest 0.38s | 3.07 | 37.46 | not measured | PASS |
| kokoro | 08-barge-in | 0.77 | 0.04 | -21.57 | -5.38 | 0 | 4 gaps, longest 0.45s | 3.64 | 34.56 | not measured | PASS |
