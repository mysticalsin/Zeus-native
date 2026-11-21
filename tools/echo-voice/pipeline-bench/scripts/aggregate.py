#!/usr/bin/env python3
"""results/raw.jsonl -> results/summary.json + results/table.md (medians across runs)."""
import json, statistics as S, sys
from pathlib import Path
R = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "results")
raw = [json.loads(l) for l in open(R / "raw.jsonl")]
MAC_FRAME_MS = 80.81   # measured q8 FR plain p50 on Apple M5 (echo-haru-results.tgz)
MAC_HOST_MS = 0.04     # measured Python host stage p50 on the Mac, same run
med = S.median
out = {}
for impl in ("python", "rust", "go"):
    b = [r for r in raw if r["impl"] == impl and r["kind"] == "bench"]
    e = [r for r in raw if r["impl"] == impl and r["kind"] == "e2e"]
    audio = b[0]["file"]["audio_s"] + b[0]["stream"]["audio_s"]
    o = {
        "runs": len(b), "e2e_runs": len(e),
        "file_wall_s": med(r["file"]["wall_s"] for r in b), "file_rtf": med(r["file"]["rtf"] for r in b),
        "file_frame_p50_ms": med(r["file"]["per_frame"]["p50_ms"] for r in b), "file_frame_p95_ms": med(r["file"]["per_frame"]["p95_ms"] for r in b),
        "file_read_resample_ms_per_120s": {f["file"]: med(r2["read_resample_ms"] for r in b for r2 in r["file"]["files"] if r2["file"] == f["file"]) for f in b[0]["file"]["files"]},
        "stream_wall_s": med(r["stream"]["wall_s"] for r in b), "stream_rtf": med(r["stream"]["rtf"] for r in b),
        "stream_frame_p50_ms": med(r["stream"]["per_frame"]["p50_ms"] for r in b), "stream_frame_p95_ms": med(r["stream"]["per_frame"]["p95_ms"] for r in b),
        "stream_frame_p99_ms": med(r["stream"]["per_frame"]["p99_ms"] for r in b),
        "total_rtf": med((r["file"]["wall_s"] + r["stream"]["wall_s"]) / audio for r in b),
        "cpu_s": med(r["time"]["user_s"] + r["time"]["sys_s"] for r in b),
        "peak_rss_mb": med(r["time"]["max_rss_kb"] / 1024 for r in b),
        "e2e_first_audio_p50_ms": med(r["first_audio"]["p50_ms"] for r in e), "e2e_first_audio_p95_ms": med(r["first_audio"]["p95_ms"] for r in e),
        "e2e_overhead_p50_ms": med(r["first_audio"]["overhead_p50_ms"] for r in e),
        "cold_first_audio_ms": med(r["cold_first_audio_ms"] for r in e),
        "cold_first_audio_min_max_ms": [min(r["cold_first_audio_ms"] for r in e), max(r["cold_first_audio_ms"] for r in e)],
        "e2e_peak_rss_mb": med(r["time"]["max_rss_kb"] / 1024 for r in e),
        "lazy_import_ms": med(r["lazy_import_ms"] for r in b) if impl == "python" else 0.0,
    }
    o["stream_frame_pct_of_mac_frame"] = 100 * o["stream_frame_p50_ms"] / MAC_FRAME_MS
    out[impl] = o
for impl in ("rust", "go"):
    p, x = out["python"], out[impl]
    x["speedup_vs_python"] = {"file_wall": p["file_wall_s"] / x["file_wall_s"], "stream_wall": p["stream_wall_s"] / x["stream_wall_s"],
                              "stream_frame_p50": p["stream_frame_p50_ms"] / x["stream_frame_p50_ms"], "cpu": p["cpu_s"] / x["cpu_s"]}
    x["box_saving_per_frame_ms"] = p["stream_frame_p50_ms"] - x["stream_frame_p50_ms"]
    x["box_saving_pct_of_mac_frame"] = 100 * x["box_saving_per_frame_ms"] / MAC_FRAME_MS
    x["mac_projected_saving_upper_bound_ms"] = MAC_HOST_MS
    x["mac_projected_saving_upper_bound_pct"] = 100 * MAC_HOST_MS / MAC_FRAME_MS
(R / "summary.json").write_text(json.dumps(out, indent=2))
f = lambda v, d=3: f"{v:.{d}f}"
rows = [("Stream path per-frame p50 (ms)", "stream_frame_p50_ms", 4), ("Stream path per-frame p95 (ms)", "stream_frame_p95_ms", 4),
        ("File path per-frame p50 (ms)", "file_frame_p50_ms", 4), ("File path per-frame p95 (ms)", "file_frame_p95_ms", 4),
        ("File mode wall, 600 s audio (s)", "file_wall_s", 3), ("Stream mode wall, 600 s audio (s)", "stream_wall_s", 3),
        ("Pipeline-only RTF, both modes", "total_rtf", 5),
        ("CPU user+sys per run (s)", "cpu_s", 2), ("Peak RSS per run (MB)", "peak_rss_mb", 0),
        ("First audio, warm, SIMULATED 86.55 ms model, p50 (ms)", "e2e_first_audio_p50_ms", 3),
        ("First audio, warm, SIMULATED model, p95 (ms)", "e2e_first_audio_p95_ms", 3),
        ("  pipeline overhead on top of model, p50 (ms)", "e2e_overhead_p50_ms", 3),
        ("Cold first audio: spawn -> first frame, SIMULATED model (ms)", "cold_first_audio_ms", 1),
        ("Stream per-frame p50 as % of Mac 80.81 ms frame", "stream_frame_pct_of_mac_frame", 3)]
lines = ["| metric (median of runs) | Python (upstream code) | Rust | Go |", "|---|---|---|---|"]
for name, k, d in rows:
    lines.append(f"| {name} | " + " | ".join(f(out[i][k], d) for i in ("python", "rust", "go")) + " |")
lines.append("| Speed-up vs Python, stream wall | 1 | " + " | ".join(f"{out[i]['speedup_vs_python']['stream_wall']:.1f}x" for i in ("rust", "go")) + " |")
lines.append("| Speed-up vs Python, file wall | 1 | " + " | ".join(f"{out[i]['speedup_vs_python']['file_wall']:.1f}x" for i in ("rust", "go")) + " |")
(R / "table.md").write_text("\n".join(lines) + "\n")
print("\n".join(lines)); print(json.dumps({i: out[i].get("speedup_vs_python") for i in ("rust", "go")}, indent=1))
print({i: out[i]["file_read_resample_ms_per_120s"] for i in out}); print("lazy import", out["python"]["lazy_import_ms"])
