#!/usr/bin/env python3
"""Compare outputs of two implementations: reply WAVs (int16 LSB diff) and stream FRAME bytes (sha256)."""
import hashlib, json, sys
from pathlib import Path
import numpy as np

ref, other = Path(sys.argv[1]), Path(sys.argv[2])
res = {"files": {}, "stream": {}}
for f in sorted(ref.glob("reply_*.wav")):
    a = np.frombuffer(f.read_bytes()[44:], dtype="<i2").astype(np.int32)
    g = other / f.name
    b = np.frombuffer(g.read_bytes()[44:], dtype="<i2").astype(np.int32)
    same_hdr = f.read_bytes()[:44] == g.read_bytes()[:44]
    d = np.abs(a - b) if a.shape == b.shape else None
    res["files"][f.name] = {"header_identical": same_hdr, "same_len": a.shape == b.shape,
                            "bit_identical": bool(d is not None and d.max() == 0),
                            "max_lsb_diff": int(d.max()) if d is not None else None,
                            "frac_samples_differing": float((d > 0).mean()) if d is not None else None}
for name in ("stream_frames.bin",):
    h = [hashlib.sha256((p / name).read_bytes()).hexdigest() for p in (ref, other)]
    res["stream"] = {"sha256_ref": h[0], "sha256_other": h[1], "bit_identical": h[0] == h[1]}
print(json.dumps(res, indent=1))
