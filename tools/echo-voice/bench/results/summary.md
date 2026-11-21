# Haru-4B MLX benchmark: Apple M5 32 GB, macOS 27.2 (run 2026-11-20, 17:40–17:50 BRT, Mac clock)

- Software: haru_mlx 0.1.0 (commit 7fe6b7665f8bf035998f401f8cb779fbe53f2751), mlx 0.32.4, Python 3.12.13, HF revision 8d6e83bcd3701a76fc27a764965665da1df7da78.
- Model: model.safetensors sha256 ad2c3534…c0fa, 10,540,113,510 bytes.
- Set: 5 FR + 5 EN items (s1, s2, m1, m2, l1). Settings: `--mode both`, seed 0, 16 warm-up frames.
- Audio: synthetic built-in `say` voices (Thomas, Samantha), no voice reference.
- Evidence: `echo-haru-results.tgz`, sha256 `7e7f32685a7ec6d761946a97fa26524bd1a61d17e648eca4df75dbfa460f911c`, extracted to `pkg/`. The stage cells were re-read from `pkg/<run>/report.json`. Those per-item files are not in this tree. The sum column is the sum of the stage cells in this table, not a separate measurement.

| run | plain p50 ms/frame | plain RTF | instr. p50 ms | instr. RTF | glue (median) | peak MLX GB | peak RSS GB | load s | TTFA p50 ms | p95/p50 max |
|---|---|---|---|---|---|---|---|---|---|---|
| q8 FR | 80.81 | 0.609 | 87.29 | 0.648 | 0.063 % | 7.41 | 2.36 | 3.84 | 443.5 | 1.28 |
| q8 EN | 79.59 | 0.604 | 82.39 | 0.653 | 0.081 % | 7.35 | 2.89 | 3.31 | 412.9 | 1.43 |
| bf16 FR | 121.49 | 0.917 | 123.51 | 0.984 | 0.046 % | 11.28 | 3.67 | 3.17 | 459.1 | 1.35 |
| bf16 EN | 135.61 | 1.058 | 147.08 | 1.116 | 0.043 % | 11.15 | 3.90 | 3.40 | 417.9 | 1.29 |

Median stage p50, in ms:

| run | encode | embed | lm | sample | head | decode | host | sum |
|---|---|---|---|---|---|---|---|---|
| q8 FR | 10.26 | 0.77 | 48.44 | 8.68 | 8.23 | 10.13 | 0.04 | 86.55 |
| q8 EN | 9.87 | 0.76 | 45.65 | 8.10 | 7.80 | 9.76 | 0.04 | 81.98 |
| bf16 FR | 9.97 | 0.81 | 80.70 | 14.23 | 7.79 | 9.73 | 0.04 | 123.27 |
| bf16 EN | 11.67 | 0.88 | 96.11 | 17.01 | 9.23 | 11.49 | 0.04 | 146.43 |

Cross-check against the figures in the brief (q8 p50 ~80 ms, RTF ~0.60, peak 7.4 GB, host 0.04 ms ≈ 0.05 % of the 80.81 ms q8 frame, q8 FR stages): **all match**. The 0.05 % figure is 0.04 / 80.81. The M5 bandwidth floor in the last section is an estimate from public specs, not a per-item measurement from this run.

Notes:
- The q8 French stage sum (86.55 ms) is higher than the plain p50 (80.81 ms) because instrumentation forces a sync after each stage.
- TTFA is time to first audio: prompt prefill plus frame 0.

**Verdict**
- **8-bit is the usable setting.** Real time with 40 % headroom (RTF ~0.60). bf16 English is not real time (RTF 1.06).
- **The LM step is 56 % of the q8 frame.** Python glue is under 0.1 %.
- **Rewriting the host loop in Rust is not justified for latency.** Confirmed by the pipeline benchmark: `/workspace/echo/pipeline-bench/REPORT.md`.

**Why the M5 is slower than the published 65 ms (M1 Max)**
- The published "34.2 ms per step" was measured on an M1 Max (400 GB/s, 32-core GPU) with the native Swift app.
- The base M5 has ~153 GB/s. A single-position step reads every weight once (~4.5 GB at q8), so the bandwidth floor alone is ~29 ms for the LM. We measured 45–48 ms.
- This is an estimate from public specs, not a measurement.
