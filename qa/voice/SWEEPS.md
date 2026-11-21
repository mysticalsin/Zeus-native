# Sweeps for PR #145

Root `SWEEPS.md` is added by other open pull requests. This log stays under `qa/voice/`.

## 2026-11-21T05:20:34Z

- Lens: UX polish and motion.
- Findings: The comparison table printed every inter-chunk gap. The failing render of three gaps was `0.11, 0.52, 0.20`, and the barge-in cell was empty. A reserve of 20 characters with 9 remaining said only `character cap reached`. A mocked HTTP 503 after a charge said only `HTTP 503: busy`. Two processes racing for the last 500 characters left the loser with `character cap reached` and no remaining count. There is no animated view in this harness, so Reduce Motion does not apply. Z-1 and Z-2 were already fixed on this branch and were not reopened. No review comments were open. CI on `6bf3643795fc4d8b2a71316498060c7e3cbbc756` was still queued, not failing.
- Fixes: A gap cell now reads `N gaps, longest X.XXs`. The JSON report still stores every gap. An absent barge-in latency reads `not measured`. The cap refusal reads `character cap reached: 20 requested, 9 remaining`. A corrupt ledger reads `ledger corrupt: no call made` and the file is left as it was. A failed render after a charge adds `characters stayed counted`.
- Red: `4222f1340857a742f3584ff06461d9fde1db9b5e`. That file was 4 failed in 0.82s.
- Green: `6a0770e0016caebc99525fa8e17f632d7cc48f43`.
- Tests after the fix: `qa/voice/tests` 30 passed in 1.79s.

## 2026-11-21T06:06:24Z

- Lens: Inspector gate.
- Findings: `report.py` exited 0 for a silent clip, a clipped clip, a wrong transcript, and a 9.5 s time to first audio, and it printed no FAIL line. A refused voice already exited 1 and also printed no FAIL line. The Kokoro long answer at 5.31 s was an ordinary row. Z-1 and Z-2 stay closed. No key, network, or provider file is part of this delta.
- Fixes: Named thresholds now print `FAIL` with the clip, metric, value, and threshold, and the process exits 1. Silence is below -70 LUFS or RMS 0.01. Clipping is a true peak above -1.0 dBTP or any full-scale sample. Transcript word error rate fails above 0.10. Time to first audio fails above 2.5 s, or above 8 s for a long answer. The measured 5.31 s long answer prints `WARN 02-long-answer ttfa_s 5.31 8.00` and the row verdict is WARN. The report and README are labelled OFFLINE ENGINE COMPARISON of Kokoro, ElevenLabs non-streaming, and Google Cloud TTS. That is not the live Zeus order (ElevenLabs > OpenAI > Gemini), and it does not drive Murmure or Scribe.
- Red: `2a2bfae7c03dc0c6387c3a3ed93bed3ecd5bb956`. That file was 7 failed in 0.66s.
- Green: `50ae2a348f900317a68dcdf8e4f4ceecbeb11a8e`.
- Tests after the fix: `qa/voice/tests` 43 passed in 2.45s. Command: `/tmp/voice-qa-venv/bin/python -m pytest qa/voice/tests -q`.

## 2026-11-21T06:12:18Z

- Lens: Devin gate r5c865b8c.
- Findings: `render_avspeech.swift` kept rate 0.92, pitch 0.82, and the empty-text `exit(2)` where no test read or ran the file. The gap cell's `math.isfinite` and `not isinstance(item, bool)` checks had no test. Three Kokoro comments used em dashes. No key, network, provider, ledger, or meter file is part of this delta.
- Fixes: Rate, pitch, and the empty-text exit moved to `qa/voice/mac/avspeech_plan.py`, which pytest runs on Linux. The Swift script reads that plan and no longer owns the three literals. NaN, infinity, True, and False are rejected as gap lengths. The em dashes in `render_kokoro.py` are gone. A search of `qa/voice` found no em dash or en dash.
- Red: `9c266a8bf1f39b642a55550bb6d061a555051da9`. The new plan test failed because the plan file was missing. The gap test was already 1 passed.
- Green: `70b0fdc12ef5098714f0add6e8f562a11cdd6e1a`.
- Tests after the fix: `qa/voice/tests` 45 passed in 1.98s. Command: `/tmp/voice-qa-venv/bin/python -m pytest qa/voice/tests -q`.
