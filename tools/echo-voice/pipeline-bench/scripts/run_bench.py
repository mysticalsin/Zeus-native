#!/usr/bin/env python3
"""Run python / rust / go pipelines on the fixed workload, N runs each, interleaved.

Every run is wrapped in GNU `/usr/bin/time -v` (CPU user+sys, peak RSS). `e2e`
runs measure, from the harness, process spawn -> the child's FIRST_AUDIO line
(cold first audio, SIMULATED model stage) and, inside the child, per-frame
user-frame-complete -> FRAME-bytes-ready latency with the SIMULATED model wait.

    run_bench.py --runs 7 --out results/
"""
import argparse, hashlib, json, os, platform, random, re, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WL = ROOT / "workload"
IMPLS = {
    "python": [str(ROOT / ".venv/bin/python"), str(ROOT / "python/pipe.py")],
    "rust": [str(ROOT / "rust/target/release/haru-pipe")],
    "go": [str(ROOT / "go/haru-pipe")],
}


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def tree_sha(paths):
    h = hashlib.sha256()
    for p in sorted(paths):
        h.update(str(Path(p).relative_to(ROOT)).encode()); h.update(sha(p).encode())
    return h.hexdigest()


def parse_time(stderr):
    g = lambda k: re.search(rf"{k}: (.+)", stderr).group(1).strip()
    return {"user_s": float(g("User time \\(seconds\\)")), "sys_s": float(g("System time \\(seconds\\)")),
            "max_rss_kb": int(g("Maximum resident set size \\(kbytes\\)")), "wall": g("Elapsed \\(wall clock\\) time .*?\\)")}


def run_bench(impl, out):
    cmd = ["/usr/bin/time", "-v"] + IMPLS[impl] + ["bench", "--workload", str(WL), "--out", str(out)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode: raise SystemExit(f"{impl} failed: {p.stderr[-2000:]}")
    r = json.loads(p.stdout.strip().splitlines()[-1]); r["time"] = parse_time(p.stderr); return r


def run_e2e(impl, model_ms, frames):
    cmd = ["/usr/bin/time", "-v"] + IMPLS[impl] + ["e2e", "--workload", str(WL), "--model-ms", str(model_ms), "--frames", str(frames)]
    t0 = time.perf_counter()
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    line = p.stdout.readline(); cold = (time.perf_counter() - t0) * 1000
    assert line.strip() == "FIRST_AUDIO", line
    rest, err = p.communicate()
    r = json.loads(rest.strip().splitlines()[-1]); r["cold_first_audio_ms"] = cold; r["time"] = parse_time(err); return r


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--runs", type=int, default=7); ap.add_argument("--e2e-runs", type=int, default=7)
    ap.add_argument("--model-ms", type=float, default=86.55); ap.add_argument("--frames", type=int, default=40)
    ap.add_argument("--out", default=str(ROOT / "results")); a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    srcs = {
        "python": [ROOT / "python/pipe.py"] + sorted((ROOT / "upstream/haru_speech_mlx-0.1.0/haru_mlx").glob("*.py")),
        "rust": sorted((ROOT / "rust/src").rglob("*.rs")) + [ROOT / "rust/Cargo.toml"],
        "go": sorted((ROOT / "go").rglob("*.go")) + [ROOT / "go/go.mod"],
    }
    env = {
        "date": time.strftime("%Y-%m-%d %H:%M:%S %Z"), "host": platform.node(), "kernel": platform.release(),
        "cpu": sh("lscpu | grep 'Model name' | sed 's/.*: *//'"), "nproc": os.cpu_count(),
        "mem_total": sh("free -m | awk '/Mem/{print $2\" MiB\"}'"), "loadavg_start": open("/proc/loadavg").read().strip(),
        "toolchains": {"python": sh(f"{IMPLS['python'][0]} -V"),
                       "numpy/scipy/soundfile/libsndfile": sh(f"{IMPLS['python'][0]} -c \"import numpy,scipy,soundfile;print(numpy.__version__,scipy.__version__,soundfile.__version__,soundfile.__libsndfile_version__)\""),
                       "rustc": sh("rustc -V"), "cargo": sh("cargo -V"), "go": sh("go version")},
        "rust_profile": "release, opt-level=3, lto=fat, codegen-units=1, no target-cpu flag (portable x86-64)",
        "go_build": "go build -trimpath (default GOAMD64=v1)",
        "source_sha256": {k: tree_sha(v) for k, v in srcs.items()},
        "binary_sha256": {"rust": sha(IMPLS["rust"][0]), "go": sha(IMPLS["go"][0])},
        "upstream": {"package": "haru-speech-mlx==0.1.0", "sdist_sha256": sha(ROOT / "upstream/sdist/haru_speech_mlx-0.1.0.tar.gz")},
        "workload_manifest_sha256": sha(WL / "manifest.json"),
        "simulated_model_ms": a.model_ms,
    }
    rng = random.Random(42); raw = []
    for run in range(a.runs):
        order = list(IMPLS); rng.shuffle(order)
        for impl in order:
            r = run_bench(impl, out / "outputs" / impl); r.update(run=run, kind="bench", loadavg=open("/proc/loadavg").read().split()[0])
            raw.append(r); print(impl, run, round(r["file"]["wall_s"], 3), round(r["stream"]["wall_s"], 3), file=sys.stderr)
    for run in range(a.e2e_runs):
        order = list(IMPLS); rng.shuffle(order)
        for impl in order:
            r = run_e2e(impl, a.model_ms, a.frames); r.update(run=run, kind="e2e"); raw.append(r)
            print(impl, "e2e", run, round(r["cold_first_audio_ms"], 1), file=sys.stderr)
    env["loadavg_end"] = open("/proc/loadavg").read().strip()
    (out / "env.json").write_text(json.dumps(env, indent=2))
    with open(out / "raw.jsonl", "w") as f:
        for r in raw: f.write(json.dumps(r) + "\n")
    print(json.dumps(env, indent=2))


if __name__ == "__main__":
    main()
