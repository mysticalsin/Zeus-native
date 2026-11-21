#!/usr/bin/env python3
"""Haru host-side pipeline, Python reference (= what haru-speech-mlx 0.1.0 runs).

It calls the UPSTREAM functions unchanged (haru_mlx.audio.load_audio /
save_audio, haru_mlx.native.upsample_2x / downsample_2x, imported from the
pinned sdist; no MLX needed) and copies run_inference.main()'s and
NativeServer._serve()'s framing logic line for line. The model is replaced by
a deterministic stand-in: model frame t+1 = clip(0.5 * user frame t), frame 0
is silence (what start() would return before the user speaks). In `e2e` the
stand-in additionally waits a fixed SIMULATED model time.

    pipe.py bench --workload DIR --out DIR [--mode all|file|stream]
    pipe.py e2e   --workload DIR --model-ms 86.55 --frames 40
"""
from __future__ import annotations

import argparse, json, os, struct, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "upstream" / "haru_speech_mlx-0.1.0"))

import numpy as np  # noqa: E402


def manifest_path(base: Path, name: str) -> Path:
    """Reject absolute paths, empty names, and '..', then keep the resolved path inside base."""
    rel = Path(name)
    root = Path(base).resolve()
    if name == "" or rel.is_absolute() or ".." in rel.parts:
        print(f"haru-pipe: refusing manifest path {name!r}", file=sys.stderr)
        raise SystemExit(2)
    full = (root / rel).resolve()
    if not full.is_relative_to(root):
        print(f"haru-pipe: refusing manifest path {name!r}", file=sys.stderr)
        raise SystemExit(2)
    return full

SR, FRAME = 24_000, 3200
FRAME_MSG, CLIENT_BLOCK = 0x11, 480  # 10 ms speaker callback at 48 kHz
now = time.perf_counter_ns


class XorShift32:
    """Shared chunk-size sequence (identical in the Rust and Go ports)."""
    def __init__(self, seed=0x9E3779B9): self.s = seed
    def next(self):
        s = self.s
        s ^= (s << 13) & 0xFFFFFFFF; s ^= s >> 17; s ^= (s << 5) & 0xFFFFFFFF
        self.s = s
        return s


def chunk_samples(rng):  # 5..40 ms of 48 kHz audio per socket read
    return 240 + rng.next() % 1681


class Ring:
    """Fixed-capacity float32 ring buffer (jitter buffer)."""
    def __init__(self, cap):
        cap = max(1, int(cap))  # a zero-length buffer makes `% cap` raise
        self.buf = np.zeros(cap, dtype=np.float32); self.cap = cap; self.r = 0; self.n = 0
    def push(self, x):
        k = len(x)
        if k > self.cap - self.n: raise OverflowError("ring overflow")
        w = (self.r + self.n) % self.cap; first = min(k, self.cap - w)
        self.buf[w:w + first] = x[:first]; self.buf[:k - first] = x[first:]; self.n += k
    def pop(self, k, out=None):
        if k > self.n: raise ValueError("ring underflow")
        out = np.empty(k, dtype=np.float32) if out is None else out
        first = min(k, self.cap - self.r)
        out[:first] = self.buf[self.r:self.r + first]; out[first:] = self.buf[:k - first]
        self.r = (self.r + k) % self.cap; self.n -= k
        return out


def sim_model(user_frame):
    return np.clip(0.5 * user_frame, -1.0, 1.0).astype(np.float32)


def stats(ns):
    a = np.asarray(ns, dtype=np.float64) / 1e6
    if a.size == 0:
        return {"n": 0, "p50_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0, "max_ms": 0.0, "mean_ms": 0.0}
    return {"n": int(a.size), "p50_ms": float(np.percentile(a, 50)), "p95_ms": float(np.percentile(a, 95)),
            "p99_ms": float(np.percentile(a, 99)), "max_ms": float(a.max()), "mean_ms": float(a.mean())}


# --------------------------------------------------------------- file mode (haru-mlx-inference)
def file_one(src: Path, dst: Path):
    from haru_mlx.audio import load_audio, save_audio  # upstream, unchanged
    t0 = now()
    user = load_audio(src)                                    # read + int16->f32 + mono + resample_poly
    t1 = now()
    count = max(1, -(-len(user) // FRAME))                    # run_inference.main, verbatim logic
    user = np.pad(user, (0, count * FRAME - len(user)))
    frames, per = [np.zeros(FRAME, dtype=np.float32)], []    # frame 0 = start()
    for index in range(count - 1):
        a = now()
        u = user[index * FRAME:(index + 1) * FRAME]
        frames.append(np.array(sim_model(u), dtype=np.float32))  # session.step(...) -> Frame.audio copy
        per.append(now() - a)
    t2 = now()
    reply = np.concatenate(frames)
    out = np.stack([user, reply], axis=1)                     # --stereo
    t3 = now()
    save_audio(dst, out)                                      # soundfile, WAV PCM_16
    t4 = now()
    return {"file": src.name, "frames": count, "audio_s": count * FRAME / SR,
            "read_resample_ms": (t1 - t0) / 1e6, "frame_loop_ms": (t2 - t1) / 1e6,
            "assemble_ms": (t3 - t2) / 1e6, "write_ms": (t4 - t3) / 1e6, "total_ms": (t4 - t0) / 1e6}, per


# --------------------------------------------------------------- stream mode (haru-mlx-native)
class Stream:
    """NativeServer._serve's audio path + a client-side playback jitter buffer."""
    def __init__(self, model_ns=0):
        self.leftover = np.zeros(0, dtype=np.float32)
        self.inbuf = Ring(8 * FRAME)          # 24 kHz user audio waiting to become a frame
        self.outbuf = Ring(8 * 2 * FRAME)     # 48 kHz model audio waiting for the speaker
        self.block = np.empty(CLIENT_BLOCK, dtype=np.float32)
        self.frame = np.empty(FRAME, dtype=np.float32)
        self.index, self.model_ns, self.msgs, self.drained = 1, model_ns, [], 0

    def emit(self, user_frame):
        reply = sim_model(user_frame)
        if self.model_ns: spin_until(now() + self.model_ns)
        from haru_mlx.native import upsample_2x  # upstream, unchanged
        pcm = upsample_2x(reply).astype("<f4").tobytes()                       # send_frame, verbatim
        payload = struct.pack("<If", self.index, 0.0) + pcm
        msg = struct.pack("<BI", FRAME_MSG, len(payload)) + payload
        self.msgs.append(msg); self.index += 1
        self.outbuf.push(np.frombuffer(pcm, dtype="<f4"))
        while self.outbuf.n >= CLIENT_BLOCK:
            self.outbuf.pop(CLIENT_BLOCK, self.block); self.drained += CLIENT_BLOCK

    def feed(self, payload, on_frame):
        x = np.concatenate([self.leftover, np.frombuffer(payload, dtype="<f4")])  # _serve, verbatim
        even = len(x) // 2 * 2
        self.leftover = x[even:]
        from haru_mlx.native import downsample_2x  # upstream, unchanged
        pcm = downsample_2x(x[:even])
        if not len(pcm): return
        self.inbuf.push(pcm.astype(np.float32))
        while self.inbuf.n >= FRAME:
            self.emit(self.inbuf.pop(FRAME, self.frame)); on_frame()


def spin_until(deadline):
    left = deadline - now()
    if left > 1_000_000: time.sleep((left - 1_000_000) / 1e9)
    while now() < deadline: pass


def stream_run(raw: bytes, max_frames=0, model_ns=0, first_cb=None):
    st, rng, per, pos = Stream(model_ns), XorShift32(), [], 0
    acc, mark = 0, 0
    def on_frame():
        nonlocal acc, mark
        t = now(); per.append(acc + t - mark); acc = 0; mark = t
        if first_cb and len(per) == 1: first_cb()
    while pos < len(raw):
        k = chunk_samples(rng) * 4
        mark = now()
        st.feed(raw[pos:pos + k], on_frame)
        acc += now() - mark
        pos += k
        if max_frames and len(per) >= max_frames: break
    return st, per


def cmd_bench(a):
    wl, out = Path(a.workload), Path(a.out); out.mkdir(parents=True, exist_ok=True)
    man = json.loads((wl / "manifest.json").read_text()); res = {"impl": "python"}
    file_jobs = []
    if a.mode in ("all", "file"):
        for f in man["files"]:
            file_jobs.append((manifest_path(wl, f["file"]), manifest_path(out, "reply_" + f["file"])))
    stream_src = manifest_path(wl, man["stream"]["file"]) if a.mode in ("all", "stream") else None
    t = now(); import scipy.signal, soundfile  # noqa: F401  first-use imports, timed separately
    res["lazy_import_ms"] = (now() - t) / 1e6
    if a.mode in ("all", "file"):
        files, per_all, t0 = [], [], now()
        for src, dst in file_jobs:
            r, per = file_one(src, dst); files.append(r); per_all += per
        wall = (now() - t0) / 1e9; audio = sum(r["audio_s"] for r in files)
        res["file"] = {"files": files, "wall_s": wall, "audio_s": audio, "rtf": wall / audio, "per_frame": stats(per_all)}
    if a.mode in ("all", "stream"):
        raw = stream_src.read_bytes()
        t0 = now(); st, per = stream_run(raw); wall = (now() - t0) / 1e9
        audio = len(raw) / 4 / 48000
        (out / "stream_frames.bin").write_bytes(b"".join(st.msgs))
        res["stream"] = {"frames": len(per), "wall_s": wall, "audio_s": audio, "rtf": wall / audio,
                         "per_frame": stats(per), "drained_samples": st.drained}
    print(json.dumps(res))


def cmd_e2e(a):
    wl = Path(a.workload); man = json.loads((wl / "manifest.json").read_text())
    with open(manifest_path(wl, man["stream"]["file"]), "rb") as fh: raw = fh.read(a.frames * 2 * FRAME * 4 + 1_000_000)
    def first(): sys.stdout.write("FIRST_AUDIO\n"); sys.stdout.flush()
    _, per = stream_run(raw, a.frames, int(a.model_ms * 1e6), first)
    s = stats(per); s["overhead_p50_ms"] = s["p50_ms"] - a.model_ms
    print(json.dumps({"impl": "python", "simulated_model_ms": a.model_ms, "first_audio": s}))


def main():
    p = argparse.ArgumentParser(); sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("bench"); b.add_argument("--workload", required=True); b.add_argument("--out", required=True)
    b.add_argument("--mode", default="all", choices=("all", "file", "stream"))
    e = sub.add_parser("e2e"); e.add_argument("--workload", required=True)
    e.add_argument("--model-ms", type=float, default=86.55); e.add_argument("--frames", type=int, default=40)
    a = p.parse_args(); {"bench": cmd_bench, "e2e": cmd_e2e}[a.cmd](a)


if __name__ == "__main__":
    main()
