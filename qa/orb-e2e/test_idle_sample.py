"""S07-07. The idle sample must name a real process, never sleep."""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import reportlib


class IdleSampleTests(unittest.TestCase):
    def test_refuses_to_sample_sleep_when_no_process_is_named(self):
        os.environ.pop("ZEUS_PID", None)
        os.environ.pop("ZEUS_ORB_BENCH", None)
        with self.assertRaises(RuntimeError) as caught:
            reportlib.sample_idle(0.2)
        self.assertNotIn("sleep", caught.exception.args[0].lower())
        message = str(caught.exception).lower()
        self.assertTrue("zeus" in message or "bench" in message)

    def test_samples_the_named_bench_not_sleep(self):
        hold = os.path.join(HERE, "hold.py")
        # A tiny real process stand-in when the Swift bench is not built yet.
        # The runner passes the compiled orb-bench. This test passes a python sleeper
        # only to prove the sampler records that pid's command, not /bin/sleep.
        script = os.path.join(HERE, "_hold_for_sample.py")
        with open(script, "w", encoding="utf-8") as handle:
            handle.write("import time, sys\ntime.sleep(float(sys.argv[1]))\n")
        try:
            os.environ["ZEUS_ORB_BENCH"] = sys.executable
            os.environ["ZEUS_ORB_BENCH_ARGS"] = script
            percent, _memory, subject = reportlib.sample_idle(0.4)
        finally:
            os.environ.pop("ZEUS_ORB_BENCH", None)
            os.environ.pop("ZEUS_ORB_BENCH_ARGS", None)
            try:
                os.remove(script)
            except OSError:
                pass
        self.assertNotEqual(subject, "sleep")
        self.assertGreaterEqual(percent, 0.0)
        self.assertLess(percent, 50.0)


if __name__ == "__main__":
    unittest.main()
