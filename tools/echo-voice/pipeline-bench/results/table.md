# Pipeline medians

Host pipeline medians. The header row names the metric and the three implementations.

| metric (median of runs) | Python (upstream code) | Rust | Go |
|---|---|---|---|
| Stream path per-frame p50 (ms) | 0.1246 | 0.0181 | 0.0358 |
| Stream path per-frame p95 (ms) | 0.1607 | 0.0215 | 0.0443 |
| File path per-frame p50 (ms) | 0.0085 | 0.0029 | 0.0050 |
| File path per-frame p95 (ms) | 0.0126 | 0.0069 | 0.0090 |
| File mode wall, 600 s audio (s) | 0.924 | 0.540 | 0.680 |
| Stream mode wall, 600 s audio (s) | 0.595 | 0.086 | 0.172 |
| Pipeline-only RTF, both modes | 0.00127 | 0.00052 | 0.00071 |
| CPU user+sys per run (s) | 3.90 | 0.71 | 0.99 |
| Peak RSS per run (MB) | 431 | 223 | 291 |
| First audio, warm, SIMULATED 86.55 ms model, p50 (ms) | 86.979 | 86.593 | 86.608 |
| First audio, warm, SIMULATED model, p95 (ms) | 87.050 | 86.617 | 86.633 |
|   pipeline overhead on top of model, p50 (ms) | 0.429 | 0.043 | 0.058 |
| Cold first audio: spawn -> first frame, SIMULATED model (ms) | 202.8 | 90.0 | 91.2 |
| Stream per-frame p50 as % of Mac 80.81 ms frame | 0.154 | 0.022 | 0.044 |
| Speed-up vs Python, stream wall | 1 | 6.9x | 3.5x |
| Speed-up vs Python, file wall | 1 | 1.7x | 1.4x |
