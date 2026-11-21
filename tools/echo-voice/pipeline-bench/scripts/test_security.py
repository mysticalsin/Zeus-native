#!/usr/bin/env python3
"""ARTEX items E-01, E-03, and E-05. Non-soak only."""
from __future__ import annotations

import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PIPE = Path(__file__).resolve().parents[1] / "python" / "pipe.py"
RUN_BENCH = Path(__file__).resolve().parent / "run_bench.py"
GO_MOD = Path(__file__).resolve().parents[1] / "go" / "go.mod"


def wav_pcm() -> bytes:
    fmt = struct.pack("<HHIIHH", 1, 1, 24000, 48000, 2, 16)
    data = b"\x00\x00\x00\x40"

    def chunk(tag: bytes, body: bytes) -> bytes:
        return tag + struct.pack("<I", len(body)) + body

    body = chunk(b"fmt ", fmt) + chunk(b"data", data)
    return b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WAVE" + body


class ManifestPathTests(unittest.TestCase):
    def test_dotdot_and_absolute_are_refused(self):
        wav = wav_pcm()
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            wl = root / "a" / "b" / "c" / "wl"
            out = root / "a" / "b" / "out"
            (wl / "subdir").mkdir(parents=True)
            (out / "reply_subdir").mkdir(parents=True)
            (root / "a" / "keep").mkdir(parents=True)
            (root / "keep").mkdir()
            (root / "a" / "keep" / "SENTINEL").write_bytes(wav)
            sentinel = root / "keep" / "SENTINEL"
            sentinel.write_bytes(b"stay")
            abs_wav = root / "abs.wav"
            abs_wav.write_bytes(wav)

            def run_case(file: str) -> None:
                man = {"files": [{"file": file}], "stream": {"file": "unused.f32"}}
                (wl / "manifest.json").write_text(json.dumps(man))
                proc = subprocess.run(
                    [sys.executable, str(PIPE), "bench", "--workload", str(wl), "--out", str(out), "--mode", "file"],
                    capture_output=True, text=True,
                )
                self.assertEqual(proc.returncode, 2, proc.stderr + proc.stdout)
                self.assertIn("refusing manifest path", proc.stderr)
                self.assertEqual(sentinel.read_bytes(), b"stay")

            run_case("subdir/../../../../keep/SENTINEL")
            run_case(str(abs_wav))
            run_case("")


class RunBenchShellTests(unittest.TestCase):
    def test_sh_uses_an_argv_list(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("run_bench_under_test", RUN_BENCH)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        self.assertEqual(mod.sh(["echo", "hello"]), "hello")
        self.assertNotIn("shell=True", RUN_BENCH.read_text(encoding="utf-8"))


class GoToolchainTests(unittest.TestCase):
    def test_go_directive_is_at_least_1_23_10(self):
        text = GO_MOD.read_text(encoding="utf-8")
        go_line = next(line for line in text.splitlines() if line.startswith("go "))
        toolchain = next((line for line in text.splitlines() if line.startswith("toolchain ")), "")
        got = tuple(int(p) for p in go_line.split()[1].split("."))
        self.assertGreaterEqual(got, (1, 23, 10))
        self.assertIn("go1.23.10", toolchain)


if __name__ == "__main__":
    unittest.main()
