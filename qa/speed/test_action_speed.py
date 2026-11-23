"""Synthetic fixtures for the action-speed harness. No Zeus process is launched."""

import importlib.util
import json
import pathlib
import subprocess
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
drive = action_speed.drive
group_turns = action_speed.group_turns
load_fixture = action_speed.load_fixture
main = action_speed.main
measurement_exit = action_speed.measurement_exit
parse_trace_line = action_speed.parse_trace_line
percentile = action_speed.percentile
reference_only = action_speed.reference_only
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
        self.assertEqual(capital["reference_ms"], 2400)
        self.assertEqual(capital["delta_p50_ms"], -300)
        self.assertEqual(capital["versus_reference"], "faster")
        self.assertIn("faster", table)
        self.assertIn("-300", table)
        self.assertIn("reference app: not launched", table)
        audio_p50 = [
            row for row in payload["target_verdicts"]
            if row["kind"] == "capital" and row["stage"] == "firstTtsAudio" and row["stat"] == "p50_ms"
        ][0]
        audio_p95 = [
            row for row in payload["target_verdicts"]
            if row["kind"] == "capital" and row["stage"] == "firstTtsAudio" and row["stat"] == "p95_ms"
        ][0]
        paint = [
            row for row in payload["target_verdicts"]
            if row["kind"] == "capital" and row["stage"] == "firstOverlayPaint"
        ][0]
        self.assertEqual(audio_p50["status"], "over")
        self.assertEqual(audio_p50["ceiling_ms"], 2000)
        self.assertEqual(audio_p95["status"], "inside")
        self.assertEqual(paint["status"], "unmeasured")
        self.assertTrue(paint["applicable"])
        self.assertFalse(payload["score"]["passed"])
        self.assertGreater(payload["score"]["unmeasured"], 0)
        self.assertIn("score: fail", table)
        self.assertFalse(payload["measurement"]["reference_app_launched"])
        self.assertFalse(payload["measurement"]["zeus_launched"])
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

    def test_missing_binary_does_not_launch(self):
        code = main(["--zeus", "/tmp/zeus-does-not-exist-action-speed", "--n", "1"])
        self.assertEqual(code, 2)

    def test_a_missing_key_release_is_refused(self):
        lines = [json.dumps(event("firstTtsAudio", 10))]
        with self.assertRaises(ValueError):
            group_turns(lines)

    def test_same_and_slower_than_the_reference(self):
        samples = [
            {"kind": "capital", "offsets": {"keyRelease": 0, "firstTtsAudio": 2400}},
            {"kind": "percent", "offsets": {"keyRelease": 0, "firstTtsAudio": 5000}},
        ]
        _table, payload = report(samples)
        capital = [row for row in payload["rows"] if row["kind"] == "capital" and row["stage"] == "firstTtsAudio"][0]
        percent = [row for row in payload["rows"] if row["kind"] == "percent" and row["stage"] == "firstTtsAudio"][0]
        window = [row for row in payload["rows"] if row["kind"] == "window" and row["stage"] == "firstTtsAudio"][0]
        self.assertEqual(capital["versus_reference"], "same")
        self.assertEqual(capital["delta_p50_ms"], 0)
        self.assertEqual(percent["versus_reference"], "slower")
        self.assertEqual(percent["delta_p50_ms"], 1100)
        self.assertEqual(percent["reference_ms"], 3900)
        self.assertEqual(window["versus_reference"], "unmeasured")
        self.assertEqual(window["reference_ms"], 2800)
        self.assertIsNone(window["delta_p50_ms"])

    def test_reference_only_marks_stay_in_the_comparison(self):
        notes = {(note["kind"], note["mark"]): note["reference_ms"] for note in reference_only()}
        self.assertEqual(notes[("capital", "filler")], 2000)
        self.assertEqual(notes[("capital", "answerDone")], 14800)
        self.assertEqual(notes[("wallpaper", "pointerBox")], 4300)
        self.assertEqual(notes[("router", "drawingEnd")], 68900)
        self.assertNotIn(("wallpaper", "pointerArrival"), notes)

    def test_a_missed_prompt_is_an_incomplete_measurement(self):
        def runner(_command, _env, timeout):
            raise subprocess.TimeoutExpired(_command, timeout)

        with tempfile.TemporaryDirectory() as directory:
            samples, missed = drive("/bin/true", 1, pathlib.Path(directory) / "trace.jsonl", runner=runner)
        self.assertEqual(samples, [])
        self.assertEqual(len(missed), 6)
        self.assertTrue(all(item["reason"] == "timeout" for item in missed))
        self.assertNotIn("prompt", json.dumps(missed))
        self.assertEqual(measurement_exit(missed), 3)
        self.assertEqual(measurement_exit([]), 0)
        self.assertEqual(measurement_exit([], False), 4)
        self.assertEqual(measurement_exit([{"kind": "capital", "reason": "timeout"}], False), 3)

    def test_one_trace_turn_keeps_its_prompt_kind(self):
        by_text = {text: kind for kind, text in PROMPTS}
        ids = {
            "capital": "00000000-0000-0000-0000-000000000001",
            "window": "00000000-0000-0000-0000-000000000002",
            "percent": "00000000-0000-0000-0000-000000000003",
            "router": "00000000-0000-0000-0000-000000000004",
            "wallpaper": "00000000-0000-0000-0000-000000000005",
            "shorter": "00000000-0000-0000-0000-000000000006",
        }

        def runner(command, env, _timeout):
            kind = by_text[command[-1]]
            path = pathlib.Path(env["ZEUS_ACTION_SPEED_TRACE_FILE"])
            line = json.dumps({"turn": ids[kind], "stage": "keyRelease", "monoNs": 10})
            with path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")

        with tempfile.TemporaryDirectory() as directory:
            samples, missed = drive(
                "/bin/true", 1, pathlib.Path(directory) / "trace.jsonl", runner=runner,
            )
        self.assertEqual(missed, [])
        self.assertEqual([sample["kind"] for sample in samples], [kind for kind, _text in PROMPTS])


def _turn(kind, **stages):
    offsets = {"keyRelease": 0}
    offsets.update(stages)
    return {"kind": kind, "offsets": offsets}


def _inside_turns():
    """One sample per prompt, on the ceiling. p50 and p95 are that sample."""
    return [
        _turn("capital", firstTtsAudio=2000, firstOverlayPaint=4000),
        _turn("window", firstTtsAudio=2000),
        _turn("percent", firstTtsAudio=2000),
        _turn("router", firstTtsAudio=2000, firstOverlayPaint=4000),
        _turn("wallpaper", firstTtsAudio=2000, pointerArrival=3000),
        _turn("shorter", firstTtsAudio=2000),
    ]


class BudgetScoreTests(unittest.TestCase):
    def test_samples_on_the_ceiling_pass(self):
        table, payload = report(_inside_turns())
        self.assertEqual(payload["score"]["checks"], 15)
        self.assertEqual(payload["score"]["inside"], 15)
        self.assertEqual(payload["score"]["over"], 0)
        self.assertEqual(payload["score"]["unmeasured"], 0)
        self.assertTrue(payload["score"]["passed"])
        self.assertIn("score: pass", table)
        window_pointer = [
            row for row in payload["target_verdicts"]
            if row["kind"] == "window" and row["stage"] == "pointerArrival"
        ][0]
        self.assertFalse(window_pointer["applicable"])
        self.assertEqual(window_pointer["status"], "unmeasured")

    def test_one_millisecond_over_each_ceiling_fails(self):
        audio = _inside_turns()
        audio[1] = _turn("window", firstTtsAudio=2001)
        _table, payload = report(audio)
        self.assertFalse(payload["score"]["passed"])
        self.assertEqual(payload["score"]["over"], 1)

        pointer = _inside_turns()
        pointer[4] = _turn("wallpaper", firstTtsAudio=2000, pointerArrival=3001)
        _table, payload = report(pointer)
        self.assertFalse(payload["score"]["passed"])
        self.assertEqual(payload["score"]["over"], 1)
        row = [
            item for item in payload["target_verdicts"]
            if item["kind"] == "wallpaper" and item["stage"] == "pointerArrival"
        ][0]
        self.assertEqual(row["status"], "over")
        self.assertEqual(row["ceiling_ms"], 3000)
        self.assertTrue(row["applicable"])

        visual = _inside_turns()
        visual[0] = _turn("capital", firstTtsAudio=2000, firstOverlayPaint=4001)
        _table, payload = report(visual)
        self.assertFalse(payload["score"]["passed"])
        self.assertEqual(payload["score"]["over"], 1)
        paint = [
            item for item in payload["target_verdicts"]
            if item["kind"] == "capital" and item["stage"] == "firstOverlayPaint"
        ][0]
        self.assertEqual(paint["status"], "over")
        self.assertEqual(paint["ceiling_ms"], 4000)

    def test_audio_p95_over_fails_while_p50_stays_inside(self):
        samples = [
            _turn("capital", firstTtsAudio=2000, firstOverlayPaint=4000),
            _turn("capital", firstTtsAudio=3001, firstOverlayPaint=4000),
        ]
        samples.extend(_turn(kind, firstTtsAudio=2000) for kind in ("window", "percent", "shorter"))
        samples.append(_turn("router", firstTtsAudio=2000, firstOverlayPaint=4000))
        samples.append(_turn("wallpaper", firstTtsAudio=2000, pointerArrival=3000))
        _table, payload = report(samples)
        audio_p50 = [
            row for row in payload["target_verdicts"]
            if row["kind"] == "capital" and row["stage"] == "firstTtsAudio" and row["stat"] == "p50_ms"
        ][0]
        audio_p95 = [
            row for row in payload["target_verdicts"]
            if row["kind"] == "capital" and row["stage"] == "firstTtsAudio" and row["stat"] == "p95_ms"
        ][0]
        self.assertEqual(audio_p50["ms"], 2000)
        self.assertEqual(audio_p50["status"], "inside")
        self.assertEqual(audio_p95["ms"], 3001)
        self.assertEqual(audio_p95["status"], "over")
        self.assertFalse(payload["score"]["passed"])

    def test_a_missing_pointer_sample_fails_the_score(self):
        samples = _inside_turns()
        samples[4] = _turn("wallpaper", firstTtsAudio=2000)
        table, payload = report(samples)
        self.assertFalse(payload["score"]["passed"])
        self.assertEqual(payload["score"]["unmeasured"], 1)
        self.assertEqual(payload["score"]["over"], 0)
        self.assertIn("score: fail", table)
        self.assertIn("unmeasured 1", table)

    def test_an_empty_trace_fails_the_score(self):
        table, payload = report([])
        self.assertFalse(payload["score"]["passed"])
        self.assertEqual(payload["score"]["checks"], 15)
        self.assertEqual(payload["score"]["unmeasured"], 15)
        self.assertEqual(payload["score"]["inside"], 0)
        self.assertIn("score: fail", table)

    def test_a_slow_pointer_tail_fails_when_the_median_is_inside(self):
        samples = [turn for turn in _inside_turns() if turn["kind"] != "wallpaper"]
        samples.append(_turn("wallpaper", firstTtsAudio=2000, pointerArrival=3000))
        samples.append(_turn("wallpaper", firstTtsAudio=2000, pointerArrival=3001))
        _table, payload = report(samples)
        row = [
            item for item in payload["target_verdicts"]
            if item["kind"] == "wallpaper" and item["stage"] == "pointerArrival"
        ][0]
        self.assertEqual(row["p50_ms"], 3000)
        self.assertEqual(row["p95_ms"], 3001)
        self.assertEqual(row["status"], "over")
        self.assertFalse(payload["score"]["passed"])


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
