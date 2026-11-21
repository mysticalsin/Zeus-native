# Echo voice sweeps

Each hunter item below is sweep `H-external`. The test is committed red, then the fix. Soak files under `tools/echo-voice/soak/` were not edited for these items.

## H-external

### EV-STAT-1

- Lens: empty Go percentile.
- Checked: `Percentile` and `Summary` in `pipeline-bench/go/harupipe/harupipe.go` on a nil slice.
- Finding: `Summary(nil)` indexed the sorted slice and panicked.
- Test: `TestEmptySummaryIsFinite` in `pipeline-bench/go/harupipe/sweeps_test.go`. Commit `c17a92b`.
- Fix: commit `3c25c92`. An empty summary returns `n == 0` and zeros, and does not panic.

### EV-STAT-2

- Lens: empty Rust summary JSON.
- Checked: `summary_json(&[])` in `pipeline-bench/rust/src/stats.rs`.
- Finding: percentiles and max were `NaN`, and the mean was `-0`. That text is not JSON.
- Test: `empty_summary_percentiles_are_null` in `pipeline-bench/rust/tests/sweeps.rs`. Commit `aff3345`.
- Fix: commit `7e1fd90`. Percentiles and max are `null`. The mean is `0`.

### EV-STREAM-1

- Lens: short socket reads.
- Checked: `Ingest::feed_bytes` (`native.rs`) and `Stream.Feed` (`harupipe.go`) when the payload length is not a multiple of 4.
- Finding: both dropped the trailing 1–3 bytes. A read split after 5 bytes did not match one read (Rust pending 8 vs 7; Go kept the count but the samples differed).
- Test: `five_byte_split_matches_single_read` and `TestFiveByteSplitMatchesSingleRead`. Commit `ec93f2a`.
- Fix: commit `fd16164`. The leftover bytes are carried into the next read.

### EV-RS-1

- Lens: resample ratios below 1.
- Checked: `resample_poly` and `NewPolyphase` for `(up, down)` of `(0, 2)`, `(2, 0)`, and `(0, 0)`.
- Finding: `up = 0` returned an empty buffer. `down = 0` and `(0, 0)` divided by zero.
- Test: `bad_resample_ratio_is_an_error` and `TestBadRatioIsAnError`. Commit `cb55b5a`.
- Fix: commit `ffeacb5`. Both constructors return `BadRatio` before building the filter.

### EV-MEM-1

- Lens: stream message retention.
- Checked: `Stream.emit` in `bench.rs` and `harupipe.go`, which appended every FRAME payload.
- Finding: 16 frames already stored 409808 bytes. An hour of audio would keep the reported hundreds of megabytes.
- Test: `stream_messages_stay_bounded` and `TestStreamMsgsStayBounded`. Commit `35c9da3`.
- Fix: commit `08634ee`. The struct keeps the latest message. `stream_run_to` / `StreamRunTo` hand each message to a sink so the bench file is still complete.

### EV-NUM-1

- Lens: parity bound in `pipeline-bench/REPORT.md`.
- Checked: `results/parity_python_vs_rust.json` and `parity_python_vs_go.json`. The worst `frac_samples_differing` is 0.001737326388888889 (0.1737%) on `reply_user_16k_mono.wav`. Rust vs Go is 0.
- Finding: the report said ≤ 0.17%, which is below that fraction. `max |diff| ≤ 3e-7` is not in the parity files.
- Test: `test_sample_fraction_covers_the_parity_files` in `pipeline-bench/scripts/test_reported_numbers.py`. Commit `04a44a4`.
- Fix: commit `18b8f94`. The bound is ≤ 0.174%, in `REPORT.md` and `README.md`. The unsourced 3e-7 sentences are removed.

### EV-NUM-2

- Lens: stage sums in `bench/results/summary.md`.
- Checked: the sum of the printed stage cells, and `0.04 / 80.81`.
- Finding: bf16 French printed 133.3 against 123.27. bf16 English printed 147.4 against 146.43. q8 English printed 82.0 against 81.98. The host share was written as 0.06%; 0.04 / 80.81 is 0.0495%, which is 0.05%.
- Test: `test_stage_sums_and_host_share` in `pipeline-bench/scripts/test_reported_numbers.py`. Commit `8c69d31`.
- Fix: commit `f1d9f1d`. Sums are 123.27, 146.43, and 81.98. The host share is 0.05%. The note says the per-item `report.json` files are not in this tree and that the sum column is derived from the stage cells. The M5 bandwidth floor stays labelled as an estimate.

### ruff, haru_soak.py:932

- Lens: dead assignment reported at `tools/echo-voice/soak/haru_soak.py:932` on `5a0d5249`.
- Checked: the path is under `soak/`.
- Finding: not fixed here. That file is owned by a separate soak copy.
- Test: none.
- Fix: none.

## Earlier sweeps on this branch

These landed before the hunter list. Soak edits in that set are left as they were.

| Sweep | Lens | Test | Fix | Result |
|---|---|---|---|---|
| 1 | Warm-up-only `analyze` (`per_turn` unbound) | `eaaff6e` `test_warmup_only_run_writes_metrics_and_exits_0` | `d9a27c6` | fixed |
| 2 | SIGINT / SIGTERM mid-run | `f22487f` `test_sigint_exits_130`, `test_sigterm_flushes_frames_and_exits_143` | `2525bbc` | fixed |
| 3 | Go ring capacity 0 | `4598fd4` `TestZeroCapacityRingAcceptsEmptyPush` | `3c25c92` | fixed |
| 4 | Python ring capacity 0 | `970777d` `test_zero_capacity_empty_push_is_noop` | `0c77842` | fixed |
| 5 | `FirwinKaiser(1)` NaN loop | `0a5668c` `TestFirwinSingleTapIsUnity` | `238a0f5` | fixed |
