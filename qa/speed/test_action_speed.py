"""Synthetic fixtures for the action-speed harness. No Zeus process is launched."""

import importlib.util
import json
import pathlib
import tempfile
import unittest

_PATH = pathlib.Path(__file__).resolve().parent / "action_speed.py"
_SPEC = importlib.util.spec_from_file_location("action_speed", _PATH)
action_speed = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(action_speed)

BASELINE_S = action_speed.BASELINE_S
DEFAULT_REPEATS = action_speed.DEFAULT_REPEATS
PROMPTS = action_speed.PROMPTS
TARGETS_S = action_speed.TARGETS_S
group_turns = action_speed.group_turns
load_fixture = action_speed.load_fixture
main = action_speed.main
parse_trace_line = action_speed.parse_trace_line
percentile = action_speed.percentile
report = action_speed.report

TURN = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"


def event(stage, mono_ns, turn=TURN):
    return {"turn": turn, "stage": stage, "monoNs": mono_ns}


class PercentileTests(unittest.TestCase):
    def test_nearest_rank_p50_and_p95(self):
        values = list(range(1, 21))
        self.assertEqual(percentile(values, 50), 10)
        self.assertEqual(percentile(values, 95), 19)
        self.assertIsNone(percentile([], 50))

    def test_single_value_is_both_ranks(self):
        self.assertEqual(percentile([7], 50), 7)
        self.assertEqual(percentile([7], 95), 7)


class TraceLineTests(unittest.TestCase):
    def test_production_line_keeps_three_keys(self):
        parsed = parse_trace_line(
            '{"turn":"%s","stage":"keyRelease","monoNs":10}' % TURN
        )
        self.assertEqual(parsed["stage"], "keyRelease")
        self.assertEqual(parsed["monoNs"], 10)

    def test_transcript_text_is_refused(self):
        line = json.dumps({
            "turn": TURN,
            "stage": "keyRelease",
            "monoNs": 1,
            "transcript": "What's the capital of Australia?",
        })
        with self.assertRaises(ValueError):
            parse_trace_line(line)

    def test_prompt_key_is_refused(self):
        line = '{"turn":"%s","stage":"keyRelease","monoNs":1,"prompt":"18%% of 240"}' % TURN
        with self.assertRaises(ValueError):
            parse_trace_line(line)


class FixtureReportTests(unittest.TestCase):
    def test_fixture_percentiles_and_baseline(self):
        runs = []
        for index in range(4):
            runs.append({
                "kind": "capital",
                "events": [
                    event("keyRelease", 0, turn=f"00000000-0000-0000-0000-00000000000{index}"),
                    event("firstTtsAudio", (2_000 + index * 100) * 1_000_000,
                          turn=f"00000000-0000-0000-0000-00000000000{index}"),
                ],
            })
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "fixture.json"
            path.write_text(json.dumps({"runs": runs}), encoding="utf-8")
            samples = load_fixture(path)
        table, payload = report(samples)
        capital = [row for row in payload["rows"] if row["kind"] == "capital" and row["stage"] == "firstTtsAudio"][0]
        self.assertEqual(capital["n"], 4)
        self.assertEqual(capital["p50_ms"], 2100)
        self.assertEqual(capital["p95_ms"], 2300)
        self.assertEqual(capital["baseline_s"], 2.4)
        self.assertIn("capital", table)
        self.assertEqual(payload["baseline_s"]["router"]["firstOverlayPaint"], 29.8)
        self.assertEqual(payload["baseline_s"]["router"]["drawingEnd"], 68.9)
        self.assertEqual(payload["baseline_s"]["wallpaper"]["pointerArrival"], 5.1)
        self.assertEqual(payload["baseline_s"]["wallpaper"]["pointerBox"], 4.3)
        self.assertEqual(payload["baseline_s"]["capital"]["filler"], 2.0)
        self.assertEqual(payload["baseline_s"]["capital"]["answerDone"], 14.8)
        self.assertEqual(payload["baseline_s"]["percent"]["firstTtsAudio"], 3.9)
        self.assertEqual(payload["baseline_s"]["window"]["firstTtsAudio"], 2.8)
        self.assertEqual(payload["baseline_s"]["shorter"]["firstTtsAudio"], 4.9)
        self.assertEqual(payload["targets_s"], TARGETS_S)
        self.assertEqual(len(payload["prompts"]), 6)
        self.assertEqual([item[0] for item in PROMPTS], [
            "capital", "window", "percent", "router", "wallpaper", "shorter",
        ])

    def test_group_turns_offsets_from_key_release(self):
        lines = [
            json.dumps(event("keyRelease", 1_000_000_000)),
            json.dumps(event("firstTtsAudio", 3_400_000_000)),
        ]
        turns = group_turns(lines)
        self.assertEqual(turns[0]["offsets"]["firstTtsAudio"], 2400)

    def test_default_repeat_count_is_at_least_20(self):
        self.assertGreaterEqual(DEFAULT_REPEATS, 20)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "empty.json"
            path.write_text(json.dumps({"runs": []}), encoding="utf-8")
            code = main(["--fixture", str(path), "--n", "20"])
        self.assertEqual(code, 0)

    def test_missing_zeus_does_not_launch(self):
        code = main([])
        self.assertEqual(code, 2)


class BaselineLockTests(unittest.TestCase):
    def test_reference_baseline_matches_the_frame_times(self):
        self.assertEqual(BASELINE_S["capital"], {
            "firstTtsAudio": 2.4, "firstOverlayPaint": 9.4, "answerDone": 14.8, "filler": 2.0,
        })
        self.assertEqual(BASELINE_S["wallpaper"]["pointerBox"], 4.3)
        self.assertEqual(BASELINE_S["wallpaper"]["pointerArrival"], 5.1)
        self.assertEqual(BASELINE_S["router"]["firstTtsAudio"], 5.9)


if __name__ == "__main__":
    unittest.main()
