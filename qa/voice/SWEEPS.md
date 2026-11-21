# Sweeps for PR #145

Root `SWEEPS.md` is added by other open pull requests. This log stays under `qa/voice/`.

## 2026-11-21T05:20:34Z

- Lens: UX polish and motion.
- Findings: The comparison table printed every inter-chunk gap. The failing render of three gaps was `0.11, 0.52, 0.20`, and the barge-in cell was empty. A reserve of 20 characters with 9 remaining said only `character cap reached`. A mocked HTTP 503 after a charge said only `HTTP 503: busy`. Two processes racing for the last 500 characters left the loser with `character cap reached` and no remaining count. There is no animated view in this harness, so Reduce Motion does not apply. Z-1 and Z-2 were already fixed on this branch and were not reopened. No review comments were open. CI on `6bf3643795fc4d8b2a71316498060c7e3cbbc756` was still queued, not failing.
- Fixes: A gap cell now reads `N gaps, longest X.XXs`. The JSON report still stores every gap. An absent barge-in latency reads `not measured`. The cap refusal reads `character cap reached: 20 requested, 9 remaining`. A corrupt ledger reads `ledger corrupt: no call made` and the file is left as it was. A failed render after a charge adds `characters stayed counted`.
- Red: `4222f1340857a742f3584ff06461d9fde1db9b5e`. That file was 4 failed in 0.82s.
- Green: `6a0770e0016caebc99525fa8e17f632d7cc48f43`.
- Tests after the fix: `qa/voice/tests` 30 passed in 1.79s.
