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

## Sweeps 6–23

Non-soak files only. A sweep with no defect is still listed.

### 6. Seeded chunk parity

- Lens: random splits of one 48 kHz frame, Rust and Go.
- Checked: `seeded_chunkings_match_one_read` and `TestSeededChunkingsMatchOneRead`, LCG splits of 1–17 bytes against one read.
- Finding: none. The byte carry from EV-STREAM-1 holds.
- Test: `fa5b9b6`. Fix: none.

### 7. WAV headers

- Lens: truncated headers, odd chunk order, non-PCM, 8-bit, 24-bit, 32-bit integer, float, zero channels, zero rate.
- Checked: both decoders. 8-bit and non-PCM return an error. Float32 works in both. Data-before-fmt is accepted because both scan every chunk. A short header returns an error.
- Finding: Go rejected 24-bit and 32-bit integer PCM that Rust decodes. Both accepted sample rate 0. Go accepted zero channels, and `ToMono` then divided by zero.
- Test: `TestDecode24And32BitPCM`, `TestDecodeRejectsZeroChannelsAndRate`, `wav_rejects_zero_rate`. Commit `2238fba`.
- Fix: `861dd13`.

### 8. CLI arguments and exit codes

- Lens: `haru-pipe` bench/e2e/convert/info.
- Checked: unknown mode, bad `--frames`, bad `--model-ms`, empty audio, compact JSON, a path with a space.
- Finding: unknown `--mode` exited 0. Rust `--frames nope` panicked (exit 101). An empty stream printed `rtf: inf`. Rust's manifest splitter required a space after `"file":`, so compact JSON died with "no stream".
- Test: `bad_mode_and_bad_numbers_exit_2`, `TestBadModeAndEmptyAudioExit2`. Commit `36248b9`.
- Fix: `9df74b9`.

### 9. EOF mid-frame

- Lens: a read that ends before 3200 samples at 24 kHz.
- Checked: `eof_mid_frame_emits_no_frame` feeds 100 bytes.
- Finding: none. Index stays 1 and the frame callback does not run. The CLIs do not read stdin; the socket path is the library.
- Test: `fa5b9b6`. Fix: none.

### 10. Benchmark seeds

- Lens: the shared xorshift32 chunk sequence.
- Checked: Python, Go, and Rust. First eight chunks are 1575, 1505, 999, 908, 752, 1875, 851, 404.
- Finding: none.
- Test: `xorshift_chunks_match_the_shared_sequence` in `fa5b9b6`. Fix: none.

### 11. Percentiles against numpy

- Lens: linear percentile for n=1, n=2, ties, and a five-point sample.
- Checked: `numpy.percentile(..., method="linear")` against `percentile` in `stats.rs`. p50 of `[1,2,3,4,10]` is 3, p95 is 8.8, ties stay 1, n=2 p95 is 3.85, n=1 p50 is 1.
- Finding: none.
- Test: `percentile_matches_numpy_linear` in `fa5b9b6`. Fix: none.

### 12. Clock source

- Lens: whether the harness times with a monotonic clock.
- Checked: Rust `bench.rs` uses `std::time::Instant`. Go `StreamRun` uses `time.Now` and `time.Since`, which subtract the monotonic reading. Python `pipe.py` uses `time.perf_counter_ns`.
- Finding: none.
- Test: none (source inspection). Fix: none.

### 13. One-hour stream and RSS

- Lens: a 60-minute synthetic 48 kHz stream after EV-MEM-1.
- Checked: one Go `Stream`, fed one minute at a time, 60 times. That first exposed a second bug: a read larger than eight frames panics in Go (`ring overflow`) and grows the Rust ring (25600 → 28800 on a 9-frame read).
- Finding: the input ring did not emit frames while a large read was still being pushed.
- Test: `TestLargeReadDoesNotOverflow`, `large_read_keeps_a_bounded_input_ring`. Commit `b4678a3`.
- Fix: `d2dcb6e`.
- After the fix, the same 60-minute feed (27000 frames, `index` 27001, one stored message of 25613 bytes, 691551000 bytes emitted) measured VmRSS: minute 1 = 64260 KiB, minute 30 = 58980 KiB, minute 60 = 59604 KiB. Minute 60 is 4656 KiB under minute 1, inside the 20 MB band.

### 14. Concurrent writers

- Lens: two bench runs creating `stream_frames.bin` in one directory.
- Checked: both CLIs use `File::create` / `os.Create`, which truncates the destination immediately.
- Finding: a second writer can tear the file a reader is scanning. Not fixed. A non-flaky test needs a hook in the middle of the write, and the bench is a single writer. Last completed rename would be the safe shape; it is not in this pass.

### 15. Paths with spaces

- Lens: `info` and `convert` on `a dir/clip.wav` and `a dir/out clip.wav`.
- Checked: the debug `haru-pipe` binary. Both exited 0 and wrote the output.
- Finding: none.
- Test: manual, not committed. Fix: none.

### 16. README and REPORT commands

- Lens: copy the documented commands.
- Ran, exit 0: `python3 tools/echo-voice/bench/haru_bench.py selftest` (`selftest ok`), `go test ./...` in `pipeline-bench/go`, `cargo test` in `pipeline-bench/rust`.
- Finding: `REPORT.md` section 7 said `cd /workspace/echo/pipeline-bench` and `cargo test` inside `package/haru-pipe`. Those paths are not in this tree.
- Test: `test_report_commands_use_this_tree`. Commit `0177c17`.
- Fix: `3ab0133`. The full `gen_workload.py` plus seven-run bench was not repeated here; it needs the gitignored ~170 MB workload and a scipy install, and the checked-in `raw.jsonl` is what sweep 23 re-derives.

### 17. Licence notice

- Lens: Apache-2.0 named for Haru and Kokoro.
- Checked: `pipeline-bench/rust/Cargo.toml` already says `license = "Apache-2.0"`. There was no NOTICE.
- Finding: missing notice.
- Test: `test_notice_names_apache_haru_and_kokoro`. Commit `d6db05a`.
- Fix: `c4f571b` adds `tools/echo-voice/NOTICE`.

### 18. Synthetic-only fixtures

- Lens: real-person audio in the tree.
- Checked: `find` for wav, mp3, flac, ogg, and aiff under `tools/echo-voice`. `*.wav` is gitignored. No audio files are tracked.
- Finding: none.

### 19. Clippy pedantic

- Lens: `cargo clippy --all-targets -- -W clippy::pedantic`.
- Checked: the warnings are `must_use`, doc backticks, and integer/float casts in the resampler and timing code. No `unwrap` on a library error path that the tests don't already cover. Exit code of clippy was 0 (warnings, not errors).
- Finding: none that change behaviour. No `allow` attributes were added; silencing the cast lints would hide a future bad cast. The existing `allow(clippy::should_implement_trait)` on `XorShift32::next` stays, because `next` is the shared port name rather than `Iterator::next`.

### 20. go vet and staticcheck

- Lens: `go vet ./...` and `staticcheck` 0.8.2 (built with Go 1.26.11 because that module asks for Go ≥ 1.26).
- Checked: `pipeline-bench/go`.
- Finding: none. Both commands printed nothing and exited 0.

### 21. ruff on non-soak Python

- Lens: `ruff` 0.17.6 on `pipeline-bench` and `bench/haru_bench.py`.
- Checked: findings are shebang/executable, import order, a redundant `int(math.ceil(...))` (Python 3 `ceil` already returns int), and `subprocess.run` without `check=`.
- Finding: no behaviour bug. Not changed. pyright is not installed here.

### 22. Dead files

- Lens: unused sources under `tools/echo-voice` outside `soak/`.
- Checked: the tree. `pipeline-bench/rust/RED.log` and `GREEN.log` are the original red-then-green evidence, not unused code. Every `.py`, `.go`, and `.rs` file is a bench, a port, or a test.
- Finding: none.

### 23. Numbers re-derived from raw.jsonl

- Lens: `summary.json` versus `statistics.median` of `results/raw.jsonl`.
- Checked: stream p50, p95, and wall seconds for Python, Rust, and Go.
- Finding: none. They match to 6 decimal places.
- Test: `test_summary_medians_match_raw_jsonl`. Commit `527daef`. Fix: none.

## 24. Security (Hammer ARTEX at 2e9f0d56)

Checked against `ee9de8e`. Soak files were not edited. Red commit `71fdbc0`. Fix commit `955a377`.

### E-01

- Status: fixed.
- Lens: manifest `file` entries joined onto the workload and output directories.
- Checked: Go `filepath.Join`, Python `Path /`, and Rust `Path::join` on a `../` name and an absolute name, for the read and the `reply_` write. A temp-dir sentinel sat outside `--out`.
- Finding: the `../` name was read and the reply was written outside `--out` (Go exit 0, Rust exit 0). An absolute name is also accepted by Python and Rust (`Path /` and `Path::join` replace the base). Go `filepath.Join` does not replace an absolute name, but it still trusted the string.
- Test: `TestManifestEscapeRefused`, `manifest_escape_is_refused`, `test_dotdot_and_absolute_are_refused`. Commit `71fdbc0`.
- Fix: commit `955a377`. Each implementation rejects an empty name, an absolute name, and a `..` element, then checks the cleaned path stays inside the base (`filepath.IsLocal` plus a prefix check after `Clean`; Rust refuses `ParentDir`, `RootDir`, and `Prefix`; Python uses `resolve()` and `is_relative_to`). The Python refusal runs before the haru import.

### E-03

- Status: fixed.
- Lens: `pipeline-bench/scripts/run_bench.py` toolchain probe.
- Checked: `sh()` at the old line 23.
- Finding: `subprocess.run(..., shell=True)`.
- Test: `test_sh_uses_an_argv_list`. Commit `71fdbc0`.
- Fix: commit `955a377`. `sh()` takes an argv list. `lscpu` and `free` are parsed in Python. The source no longer contains `shell=True`.

### E-05

- Status: fixed. The minimum toolchain is go1.23.10.
- Lens: stdlib GO-2025-3750 in go 1.22 (Windows-only).
- Checked: `pipeline-bench/go/go.mod` and `go env GOVERSION` from that directory.
- Finding: the go line was `go 1.22`.
- Test: `test_go_directive_is_at_least_1_23_10`. Commit `71fdbc0`.
- Fix: commit `955a377`. The go line is `go 1.23.10`, which selects toolchain go1.23.10. `go env GOVERSION` is `go1.23.10`, and `go test ./...` plus `go vet ./...` exit 0. A separate `toolchain go1.23.10` line is not kept: go 1.23.10 treats it as implied by the go line, `go mod tidy` deletes it, and `go test` refuses to run while it is present.

## 25. UX polish and motion

- Time: 2026-11-21T05:21:17Z.
- Lens: UX polish and motion.
- Checked: `docs/stream-latency.svg` against `pipeline-bench/results/summary.json`, and `python/pipe.py bench` on a non-JSON manifest, a missing manifest, `{}`, and a file bench with an empty `files` list. No review comments and no Devin notes on PR #84. E-01, E-03, and E-05 were already fixed at `955a377`. On `839e81c`, `extension` and `release-scripts` had completed success; `app` and `feature-map` were still queued, with no failed check. Soak files and the other open PRs' paths were not edited.
- Findings:
  - The three p50 bars were `width="0"` and grew only through SMIL `<animate>`. There was no `prefers-reduced-motion` rule, so a static viewer or reduced motion showed empty bars. The measured resting widths are Python 248.1 px, Rust 36.1 px, Go 71.4 px, with 320 px equal to the Python p95 0.160699 ms. The p95 ticks were at 42.8, 88.1, and 320 px.
  - `pipe.py` exited 1 and printed a traceback for those four manifests. Go and Rust already exited 2 with a `haru-pipe:` line for the non-JSON file (`haru-pipe: invalid character...` and `haru-pipe: manifest has no stream`).
- Fixes: chart red `c1aa744`, green `f098f5f`. Manifest text red `50ef82e`, green `92e401b`. The chart's resting widths are those p50 lengths, CSS grows them, and `@media (prefers-reduced-motion: reduce)` sets `animation: none`. `pipe.py` prints one `haru-pipe:` line and exits 2.
- Tests, all exit 0: `test_stream_chart.py` 1, `test_pipe_messages.py` 1, `test_security.py` 3, `test_reported_numbers.py` 4, `test_notice.py` 1. Ten tests.

## 26. Accessibility

- Time: 2026-11-21T05:57:10Z.
- Lens: Accessibility.
- Checked: CLI and report colour, `docs/stream-latency.svg` (`role="img"`), `pipeline-bench/results/table.md`, `bench/results/summary.md`, `pipeline-bench/REPORT.md`, `README.md`, and `scripts/gen_workload.py`. No review comments on PR #84. E-01, E-03, and E-05 still pass in `test_security.py` (3 tests, exit 0). CI on `77a2283` was still queued (`app`, `feature-map`, `extension`, `release-scripts`), with no failed check.
- Findings:
  - The chart's accessible description named Python, Rust, and Go p50 only. `role="img"` hides the visible p95 labels. The missing values are Python p95 0.160699 ms, Rust p95 0.02150425 ms, Go p95 0.044256149999999994 ms.
  - `pipeline-bench/results/table.md` opened on the table row. It had column headers and no heading.
  - `bench/results/summary.md` pointed at `/workspace/echo/pipeline-bench/REPORT.md`, which is not in this tree.
- Skipped, and why:
  - `NO_COLOR` and colour-only pass/fail: the non-soak CLI and reports emit no ANSI colour. Soak prints the words `PASS` and `FAIL`. Nothing changes when colour is removed.
  - HTML reports: there are none.
  - Audio transcripts: `gen_workload.py` writes seeded formant PCM, not words, and no wav is tracked. Soak sample wavs are described in `soak/results/SCHEMA.md` as synthetic stereo. That directory was not edited.
  - Bold Rust cells in `REPORT.md`: section 1 already says "Rust wins on the pipeline" in plain text.
  - Soak `SCHEMA.md` and `MAC_RUN_PLAN.md` still cite `/workspace/echo/soak/results`. Left as they are; this branch does not edit `soak/`.
- Fixes: red `b2cf4bf`, green `8e67721`. The description now includes those three p95 values. `table.md` starts with `# Pipeline medians`. The M5 summary links to `../../pipeline-bench/REPORT.md`.
- Tests, all exit 0: `test_accessibility.py` 3, then the same file 20 times in a row (20/20). Also `test_stream_chart.py` 1, `test_security.py` 3, `test_pipe_messages.py` 1, `test_reported_numbers.py` 4, `test_notice.py` 1. Thirteen tests in the combined run.
