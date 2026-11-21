"""Unit tests for the orb end-to-end runner. qa/orb-e2e/run.sh runs this module first."""

import pathlib
import sys
import time
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import reportlib
import spec_oracle


def _sleep_past_budget():
    time.sleep(2)


def _fail_once():
    raise AssertionError("assertion failed")


class ForgeChecks(unittest.TestCase):
    def test_percentile_uses_the_15th_and_29th_of_30(self):
        samples = list(range(1, 31))
        p50, p95 = spec_oracle.percentile_30(samples)
        self.assertEqual(p50, 15)
        self.assertEqual(p95, 29)

    def test_timeout_is_infra_after_one_retry(self):
        status, detail, attempts = reportlib.execute(_sleep_past_budget, 0.2)
        self.assertEqual(status, "infra")
        self.assertEqual(attempts, 2)
        self.assertIn("exceeded", detail)

    def test_assertion_failure_is_not_retried(self):
        status, detail, attempts = reportlib.execute(_fail_once, 2)
        self.assertEqual(status, "fail")
        self.assertEqual(attempts, 1)
        self.assertIn("assertion failed", detail)

    def test_skip_xfail_gate_rejects_either_status(self):
        with self.assertRaises(AssertionError):
            reportlib.skip_xfail_gate([{"name": "a", "status": "skip"}])
        with self.assertRaises(AssertionError):
            reportlib.skip_xfail_gate([{"name": "b", "status": "xfail"}])
        reportlib.skip_xfail_gate([{"name": "c", "status": "pass"}, {"name": "d", "status": "fail"}])

    def test_illegal_pairs_are_the_complement_of_the_table(self):
        legal = {(edge[0], edge[1]) for edge in spec_oracle.legal_applications()}
        illegal = spec_oracle.illegal_pairs()
        self.assertEqual(len(legal), 29)
        self.assertEqual(len(illegal), 111)
        for phase, event in illegal:
            self.assertIsNone(spec_oracle.step(phase, event))
        self.assertIsNone(spec_oracle.step("speaking", "not_an_event"))


if __name__ == "__main__":
    unittest.main()
