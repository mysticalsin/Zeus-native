# Voice QA comparison

Each row is one rendered script. Time to first audio uses the timing JSON when it records `first_audio_s`; otherwise it is the first non-silent sample in the WAV. Barge-in stop latency is present only when the timing JSON records both the request and the stop.

| provider | script | ttfa_s | wav_onset_s | integrated_lufs | true_peak_dbtp | clipping_count | inter_chunk_gaps_s | speech_rate_wps | pitch_std_hz | barge_in_stop_latency_s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| kokoro | 01-short-ack | 0.23 | 0.03 | -20.55 | -6.23 | 0 |  | 1.02 | 48.91 |  |
| kokoro | 02-long-answer | 5.31 | 0.04 | -21.78 | -4.86 | 0 | 0.52, 0.11, 0.43, 0.32, 0.12, 0.66, 0.14, 0.33, 0.58, 0.26, 0.29, 0.45, 0.10, 0.19, 0.37, 0.40, 0.26, 0.33, 0.61, 0.11, 0.47, 0.21, 0.20, 0.57, 0.44, 0.13, 0.39 | 3.61 | 34.19 |  |
| kokoro | 03-numbers-dates-currency-code | 1.89 | 0.04 | -21.71 | -4.98 | 0 | 0.14, 0.26, 0.61, 0.38, 0.37 | 2.07 | 26.68 |  |
| kokoro | 04-question | 0.43 | 0.03 | -21.10 | -5.35 | 0 | 0.11 | 3.30 | 44.54 |  |
| kokoro | 05-error | 0.90 | 0.02 | -21.69 | -5.23 | 0 | 0.49, 0.36, 0.11, 0.16 | 2.65 | 36.10 |  |
| kokoro | 06-markdown-url | 1.88 | 0.03 | -21.70 | -6.04 | 0 | 0.13, 0.43, 0.63, 0.29, 0.31, 0.42, 0.27, 0.32, 0.11, 0.10 | 0.94 | 39.40 |  |
| kokoro | 07-french | 0.87 | 0.04 | -21.49 | -5.93 | 0 | 0.18, 0.38, 0.32 | 3.07 | 37.46 |  |
| kokoro | 08-barge-in | 0.77 | 0.04 | -21.57 | -5.38 | 0 | 0.19, 0.45, 0.19, 0.17 | 3.64 | 34.56 |  |
