#!/usr/bin/env python3
"""Safety regressions for the Echo soak harness. Each test names the sweep that found it."""
from __future__ import annotations

import json
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

SOAK = Path(__file__).resolve().parent
HARNESS = SOAK / "haru_soak.py"


class ShortRunTests(unittest.TestCase):
    def test_warmup_only_run_writes_metrics_and_exits_0(self):
        """A run whose frames never pass the warm-up cutoff (k > 16) must still
        finish: metrics.json and replies.jsonl exist, and the process exits 0.
        0.03 min is about 13 frames, all inside the warm-up window."""
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "short"
            proc = subprocess.run(
                [sys.executable, str(HARNESS), "run", "--backend", "fake", "--fake-audio",
                 "--out", str(out), "--minutes", "0.03", "--sample-seconds", "0"],
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr[-800:] + proc.stdout[-400:])
            metrics = json.loads((out / "metrics.json").read_text())
            self.assertEqual(metrics["frames_logged"] > 0, True)
            self.assertTrue((out / "replies.jsonl").is_file())


class SignalTests(unittest.TestCase):
    def test_sigterm_flushes_frames_and_exits_143(self):
        """SIGTERM mid-run must be caught: frames.jsonl is flushed, events.jsonl
        records the signal and a closing end event, and the exit code is 143
        (128+SIGTERM) rather than an uncaught death."""
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "sig"
            proc = subprocess.Popen(
                [sys.executable, str(HARNESS), "run", "--backend", "fake", "--fake-audio",
                 "--out", str(out), "--minutes", "2", "--sample-seconds", "0", "--pace", "realtime"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            deadline = time.time() + 5
            while time.time() < deadline and proc.poll() is None:
                ev = out / "events.jsonl"
                if ev.exists() and "start" in ev.read_text(errors="replace"):
                    break
                time.sleep(0.05)
            time.sleep(0.35)  # a couple of realtime frames land in the stdio buffer
            proc.send_signal(signal.SIGTERM)
            try:
                rc = proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                rc = proc.wait()
            proc.stdout.close()
            self.assertEqual(rc, 128 + signal.SIGTERM)
            frames = (out / "frames.jsonl").read_text(errors="replace").splitlines()
            parsed = [json.loads(line) for line in frames if line.strip()]
            self.assertGreater(len(parsed), 0)
            events = [json.loads(line)["event"] for line in (out / "events.jsonl").read_text().splitlines() if line.strip()]
            self.assertIn("signal", events)
            self.assertIn("end", events)

    def test_sigint_exits_130(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "sigint"
            proc = subprocess.Popen(
                [sys.executable, str(HARNESS), "run", "--backend", "fake", "--fake-audio",
                 "--out", str(out), "--minutes", "2", "--sample-seconds", "0", "--pace", "realtime"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            deadline = time.time() + 5
            while time.time() < deadline and proc.poll() is None:
                ev = out / "events.jsonl"
                if ev.exists() and "start" in ev.read_text(errors="replace"):
                    break
                time.sleep(0.05)
            proc.send_signal(signal.SIGINT)
            try:
                rc = proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                rc = proc.wait()
            proc.stdout.close()
            self.assertEqual(rc, 128 + signal.SIGINT)
            events = [json.loads(line)["event"] for line in (out / "events.jsonl").read_text().splitlines() if line.strip()]
            self.assertIn("signal", events)
            self.assertIn("end", events)


if __name__ == "__main__":
    unittest.main()
