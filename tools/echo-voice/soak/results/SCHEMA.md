# summary.json schema (`echo-soak/2`)

Produced on the box by `python3 haru_soak.py summarize --results /workspace/echo/soak/results`. The command re-runs
`analyze` on every `<run-id>/` directory, then writes summary.json, report.md, blind/ and MANIFEST.sha256.
Times are box-local ISO-8601 with an offset. Latencies are in ms unless the key ends in `_s`. RTF is compute time ÷ audio time
(below 1 means faster than real time). Retries are 0: a failed run or case is reported as failed and never re-run.

## Layout
```
results/
  summary.json          this schema
  SCHEMA.md             this file
  report.md             human-readable tables rendered from summary.json
  MANIFEST.sha256       sha256 of every file under results/ ("<hex>  <relative path>")
  STATUS.tsv            run_all.sh ledger: id, exit, wall_s, start, end, note (SKIP ... = skipped)
  <run-id>/             one soak run: meta.json frames.jsonl mem.jsonl events.jsonl metrics.json replies.jsonl
                        sample_{start,middle,end}.wav  (stereo PCM16 24 kHz, L = synthetic user, R = Haru)
  <run-id>.log          stdout/stderr of the run
  faults/faults.json    error/recovery cases; faults/<case>/ holds each case's run dir; faults/<case>.log
  blind/S01..Snn.wav    shuffled copies of every sample for blind listening; blind/KEY.json unblinds them
```

## Top level
| key | type | meaning |
|---|---|---|
| schema_version | str | `echo-soak/2` |
| generated | str | when summarize ran |
| model | obj | repo, revision, model_safetensors_sha256, quantize |
| policy | obj | retries (0), voices (synthetic only), naturalness (proxies, not MOS) |
| totals | obj | runs, ok, failed, skipped, fault_cases, fault_pass, fault_fail |
| runs | [Run] | one per run dir, plus planned runs from STATUS.tsv that have no dir (status skipped/missing) |
| faults | [Fault] | the explicit error/recovery cases |
| verdict | null/str | filled in by the report author (which mitigation set to adopt) |

## Run
| key | meaning |
|---|---|
| run_id, kind | dir name; `soak` or `smoke` |
| status | `ok` (exit 0 and a clean `end` event) / `failed` / `skipped` / `missing` |
| exit_code, wall_s, started | from STATUS.tsv and meta.json |
| config | temperature, top_k, top_p, guidance_scale, eop_bias, dry, kv_window, reanchor_minutes, watchdog, quantize, seed, minutes, barge_in_every, backend, haru_mlx, mlx |
| frames_logged, load_seconds | frames written (one per 133.3 ms); model load time |
| latency.overall | p50_ms, p95_ms, p99_ms, max_ms of per-frame model step time (frames > 16), drift_ms_per_min (OLS slope) |
| latency.windows_5min[] | per 5-min window: t0_min, t1_min, frames, p50/p95/p99/max_ms, wall_p50_ms, wall_p99_ms, rtf_model, rtf_wall, frames_over_133ms, first_audio_s{n,p50,p90,p95,max,mean}, no_reply_turns, garbage_ratio, voiced_ratio, mlx_active_gb_end, rss_mb_end, restarts |
| latency.first_audio_latency_s | distribution of the reply gap: time from the end of the user's speech to Haru's first voiced 16.7 ms sub-window. Replies cut by a scripted barge-in are excluded. 0 means Haru was already speaking |
| latency.first_min_p50_ms / last_min_p50_ms | median step time in the first vs the last minute |
| latency.rtf_model / rtf_wall | whole run |
| memory | rss_mb_per_min, mlx_active_mb_per_min (OLS slopes), rss_mb_start, rss_mb_end, mlx_active_gb_end, mlx_peak_gb, kv_positions_end |
| stability.repetition | repeated_3gram_ratio_median/max, loop_events, consecutive_reply_4gram_overlap_median |
| stability.on_topic | keyword_hit_rate (+ first/second half), tfidf_margin_positive_rate |
| stability.responsiveness | answered_turn_rate (>= 1 s voiced reply; cut replies excluded), talk_over_ratio |
| stability.audio | garbage_frame_ratio, nonfinite_frames, voiced_frame_ratio |
| stability.restarts[] | restart events: k, min, wall_s, reason (watchdog / re-anchor / step error), turn, prompt_seconds, wall_seconds, session_frames |
| stability.events | count per event kind |
| stability.checkpoints | at 10/30/60 min (and the end): p50/p95/p99_ms, loop_events, keyword_hit_rate, answered_turn_rate, garbage_frame_ratio, restarts |
| naturalness_proxies.{whole_run, first_third, middle_third, last_third} | see below |
| samples[] | position (start/middle/end), path, from_min, to_min, sha256, channels |
| artifacts_dir | `<run-id>` |
| error | present only when analysis itself failed |

## Naturalness proxies (objective proxies, NOT a MOS or listening score)
Computed with numpy only (no ASR, no torch) from Haru's output audio and its own text channel.
| key | meaning |
|---|---|
| pause_s | distribution of silent runs (>= 100 ms) inside a reply; per_min_speech; long_pause_gt_1_5s_rate |
| speaking_rate_wps | words in Haru's text channel ÷ voiced seconds, per reply with >= 1 s of voiced audio |
| f0 | autocorrelation F0 (60-400 Hz, 40 ms windows, Boersma normalisation): median_hz, range_st_p5_p95, std_st, per_turn_range_st_median, voiced_frames_with_f0. A flat (monotone) voice shows as a range near 0 |
| energy | voiced_db_p10/p95, dynamic_range_db, voiced_db_std, per_turn_std_db_median |
| clipping_frame_ratio | frames where more than 0.1 % of samples are at full scale |
| silence_ratio, garbage_ratio | frames <= -45 dBFS; frames that are noise-like (spectral flatness > 0.5), non-finite, or clipped > 1 % |
| turn_taking | reply_gap_s distribution, no_reply_turns, overlap_start_turns, barge_ins, barge_ins_model_talking, barge_yield_s (time from the user barging in until Haru has been silent for >= 200 ms), barge_yield_rate_le_2s |

## Fault
| key | meaning |
|---|---|
| case | bad_frame, bad_frame_raw, garbage_input, truncated_input, stall, watchdog_loop, watchdog_latency, disk_low, process_kill |
| expected | the expected state and behaviour, as text |
| observed | measured facts for the case (events, errors, restarts, exit codes, latencies) |
| pass | observed matches expected |
| recovery_s | wall seconds from the injection (or its end) until the first normal frame; for process_kill, from the SIGKILL until the fresh process's first frame; for disk_low, from the injection until the clean stop |
| exit_code, wall_s, started, run_dir | the case's run |
| note | `kept from the first attempt (retries 0)` when an invocation found the case already recorded |
