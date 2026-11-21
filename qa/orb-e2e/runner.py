#!/usr/bin/env python3
"""Deep orb end-to-end suite. Fakes only: injected audio bands, no microphone, no model, no TTS provider.

One command: qa/orb-e2e/run.sh
Output: $ZEUS_E2E_OUT or $TMPDIR/zeus-e2e/orb/<sha8>/
"""

import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import reportlib
import spec_oracle

COMMANDS = """qa/orb-e2e/run.sh
python3 qa/orb-e2e/test_runner.py
swiftc -O -o \"$ZEUS_E2E_OUT/orb-bench\" Sources/ZeusCore/Companion/*.swift qa/orb-e2e/BenchMain.swift
\"$ZEUS_E2E_OUT/orb-bench\" \"$ZEUS_E2E_OUT/bench.json\"
"""


def sha():
    return subprocess.check_output(["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True).strip()


def output_dir(commit):
    chosen = os.environ.get("ZEUS_E2E_OUT")
    if chosen:
        path = pathlib.Path(chosen)
    else:
        tmp = os.environ.get("TMPDIR", "/tmp")
        path = pathlib.Path(tmp) / "zeus-e2e" / "orb" / commit[:8]
    path.mkdir(parents=True, exist_ok=True)
    return path


def compile_bench(out, swift):
    companion = sorted((REPO / "Sources/ZeusCore/Companion").glob("*.swift"))
    sources = companion + [HERE / "BenchMain.swift"]
    binary = out / "orb-bench"
    log = out / "swiftc.log"
    command = [swift, "-O", "-o", str(binary)] + [str(path) for path in sources]
    with log.open("w", encoding="utf-8") as handle:
        completed = subprocess.run(command, cwd=REPO, stdout=handle, stderr=subprocess.STDOUT, text=True)
    if completed.returncode != 0:
        tail = log.read_text(encoding="utf-8", errors="replace")[-2000:]
        raise AssertionError(tail)
    return binary


def run_bench(binary, destination):
    completed = subprocess.run([str(binary), str(destination)], cwd=REPO, capture_output=True, text=True)
    if completed.returncode != 0:
        raise AssertionError((completed.stderr or completed.stdout or "bench failed")[-2000:])
    return json.loads(destination.read_text(encoding="utf-8"))


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)


def case_edges(bench):
    def run():
        swift_edges = {(item["from"], item["event"], item["to"], tuple(item["effects"])) for item in bench["edges"]}
        oracle = {(edge[0], edge[1], edge[2], tuple(edge[3])) for edge in spec_oracle.legal_applications()}
        require(swift_edges == oracle, f"swift {len(swift_edges)} oracle {len(oracle)}")
        require(bench["illegal_count"] == 111, str(bench["illegal_count"]))
        require(len(spec_oracle.illegal_pairs()) == 111, "oracle illegal count")
        for phase, event in spec_oracle.illegal_pairs():
            require(spec_oracle.step(phase, event) is None, f"{phase} {event}")
        return "29 legal, 111 illegal"
    return run


def case_hold(bench):
    def run():
        require(bench["hold"] == ["idle", "listening", "transcribing", "thinking", "speaking", "idle"], " ".join(bench["hold"]))
        return "idle listening transcribing thinking speaking idle"
    return run


def case_interrupt(bench):
    def run():
        edge = spec_oracle.step("speaking", "key_down")
        require(edge is not None and edge[2] == "interrupted", "missing interrupt")
        require(list(edge[3]) == ["stop speech", "stop flight", "stop capture"], str(edge[3]))
        require(spec_oracle.step("interrupted", "cleanup_key_up")[2] == "idle", "no return to idle")
        ok = _assertion(bench, "interrupt_effects") and _assertion(bench, "interrupt_then_idle")
        require(ok, "swift interrupt assertions failed")
        return "stop speech, stop flight, stop capture"
    return run


def case_error(bench):
    def run():
        denied = spec_oracle.step("listening", "capture_denied_at_start")
        require(denied[2] == "error", denied[2])
        require(spec_oracle.step("error", "line_spoken")[2] == "idle", "no recovery")
        require(_assertion(bench, "error_has_no_orb_color"), "orb invented an error color")
        require(_assertion(bench, "spoken_lines_ten_words"), "spoken line over ten words")
        return "error then idle, no error color in orb.ts"
    return run


def case_compacting(bench):
    def run():
        require(_assertion(bench, "compacting_targets"), "compacting targets")
        points = bench["particles"]["compacting"]
        require(points and all(_finite(pair) for pair in points), "non-finite compacting particles")
        return f"{len(points)} plotted particles"
    return run


def case_reduce_motion(bench):
    def run():
        motion = bench["motion"]
        require(motion["frozen"] is True and motion["electrons"] == 0, str(motion))
        return "positions frozen, no electrons"
    return run


def case_monitors(bench):
    def run():
        for count in (1, 2, 3):
            top_bars, extra = _surface(count)
            require(top_bars == count and extra == 0, f"{count} -> {top_bars}, {extra}")
        require(_assertion(bench, "surface_two_displays"), "swift surface")
        text = (REPO / "Sources/Zeus/Notch/NotchController.swift").read_text(encoding="utf-8")
        require("One borderless window per display" in text, "notch controller no longer says one window per display")
        return "one top bar per display, no extra window"
    return run


def case_voice(bench):
    def run():
        persona = bench["persona"]
        require(persona["voice_flag"] is False, "flag defaulted on")
        require(persona["voice_resolved"] == "zeusDefault", persona["voice_resolved"])
        return "flag off, Zeus voice"
    return run


def case_persona(bench):
    def run():
        persona = bench["persona"]
        require(persona["classic_identical"] is True, "classic changed the prompt")
        require(persona["orb_adds"] is True, "orb did not add the addendum")
        require(persona["relaunch_orb"] is True and persona["relaunch_classic"] is True, "relaunch lost the choice")
        return "classic identical, orb addendum, relaunch persisted"
    return run


def case_llm_only(bench):
    def run():
        require(_assertion(bench, "persona_scope"), "scope flags")
        return "prompt overlay is the only LLM surface"
    return run


def case_face_and_core(bench):
    def run():
        face = (REPO / "Sources/ZeusCore/FacePresence/FacePresenceMachine.swift").read_text(encoding="utf-8")
        instant = (REPO / "Sources/ZeusCore/Intent/InstantTable.swift").read_text(encoding="utf-8")
        for token in ("PersonaCatalog", "JarvisPersona", "URLSession", "ClaudeCLI"):
            require(token not in face, f"face source contains {token}")
            require(token not in instant, f"instant source contains {token}")
        require("never calls a model" in instant, "instant table lost its no-model comment")
        route = instant.split("public static func route", 1)[1].split("public static func spokenAnswer", 1)[0]
        require("spokenAnswer" in route and route.find("spokenAnswer") < route.find("return .brain"), "time answers are not local")
        return "face and instant sources do not consult the persona or a model"
    return run


def case_attribution():
    license_path = REPO / "LICENSES/jarvis2.0-LICENSE"
    data = license_path.read_bytes()
    require(len(data) == 1677 and sum(data) == 138619, f"license bytes {len(data)} sum {sum(data)}")
    notices = (REPO / "Resources/NOTICES.txt").read_text(encoding="utf-8")
    require("Copyright (c) 2026 Ethan Rogers" in notices, "About notices missing the copyright")
    require("COMMERCIAL USE PROHIBITED WITHOUT LICENSE" in notices, "About notices missing the license body")
    about = (REPO / "Sources/Zeus/Settings/GSAboutPage.swift").read_text(encoding="utf-8")
    require("AboutInfo.notices" in about and "Acknowledgements" in about, "About page does not show notices")
    bundle = (REPO / "scripts/bundle.sh").read_text(encoding="utf-8")
    require("LICENSES/jarvis2.0-LICENSE" in bundle and "NOTICES.txt" in bundle, "bundle.sh does not ship the license")
    header = (REPO / "Sources/ZeusCore/Companion/OrbSimulation.swift").read_text(encoding="utf-8")
    require("16e37bd801eb797798e02540665f8b3804b0fe14" in header, "simulation header missing the source commit")
    return "license text is in NOTICES for About and is copied by bundle.sh"


def case_frames(bench, hertz):
    def run():
        block = bench["frames"][str(hertz)]
        require(bench["frames"]["rates_match"] is True, "60 Hz and 120 Hz states diverged")
        summary = {}
        for state, samples in block.items():
            require(len(samples) == 30, f"{state} has {len(samples)} samples")
            p50, p95 = spec_oracle.percentile_30(samples)
            drops, limit = spec_oracle.dropped(samples, hertz)
            require(drops == 0, f"{state} dropped {drops} at {hertz} Hz (limit {limit:.2f} ms, p95 {p95:.2f})")
            summary[state] = {"p50_ms": p50, "p95_ms": p95, "dropped": drops}
        return summary
    return run


def case_properties(bench):
    def run():
        for state, points in bench["particles"].items():
            require(points, state)
            for pair in points:
                require(_finite(pair), f"{state} non-finite")
        return f"{len(bench['particles'])} states finite"
    return run


def case_no_skip_markers():
    banned = ("XCTSkip", "XCTExpectFailure", "pytest.mark.skip", "pytest.mark.xfail")
    paths = [
        REPO / "Tests/ZeusCoreTests/OrbE2EJourneyTests.swift",
        HERE / "test_runner.py",
        HERE / "BenchMain.swift",
        HERE / "spec_oracle.py",
    ]
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for token in banned:
            require(token not in text, f"{path.name} contains {token}")
    return "no skip or xfail markers"


def case_idle():
    def run():
        percent, memory, subject = reportlib.sample_idle(10)
        require(percent < 1.0, f"cpu {percent:.3f}%")
        require(memory < 150.0, f"memory {memory:.1f} MB")
        return {"percent": percent, "memory_mb": memory, "subject": subject}
    return run


def _assertion(bench, name):
    for item in bench["assertions"]:
        if item["name"] == name:
            return item["ok"] is True
    return False


def _finite(pair):
    return all(value == value and abs(value) != float("inf") for value in pair)


def _surface(count):
    return (max(0, count), 0)


def build_cases(bench):
    return [
        ("spec.transitions", 10, case_edges(bench)),
        ("journey.hold_to_talk", 10, case_hold(bench)),
        ("journey.interrupt_speaking", 10, case_interrupt(bench)),
        ("journey.error_and_recovery", 10, case_error(bench)),
        ("journey.compacting", 10, case_compacting(bench)),
        ("journey.reduce_motion", 10, case_reduce_motion(bench)),
        ("journey.multiple_monitors", 10, case_monitors(bench)),
        ("journey.voice_flag", 10, case_voice(bench)),
        ("journey.persona_relaunch", 10, case_persona(bench)),
        ("journey.persona_llm_only", 10, case_llm_only(bench)),
        ("journey.face_and_core_without_llm", 10, case_face_and_core(bench)),
        ("journey.attribution_about_and_bundle", 10, case_attribution),
        ("forge.property_particles", 10, case_properties(bench)),
        ("forge.no_skip_markers", 10, case_no_skip_markers),
        ("frames.60", 10, case_frames(bench, 60)),
        ("frames.120", 10, case_frames(bench, 120)),
        ("budget.idle_cpu_and_memory", 30, case_idle()),
    ]


def main():
    started = time.time()
    commit = sha()
    out = output_dir(commit)
    (out / "commands.txt").write_text(COMMANDS, encoding="utf-8")
    swift = shutil.which("swiftc") or str(pathlib.Path.home() / "swift/usr/bin/swiftc")
    results = []

    def add(name, status, detail, duration, attempts):
        if not isinstance(detail, str):
            detail = json.dumps(detail)
        results.append({
            "name": name,
            "status": status,
            "detail": detail,
            "duration_s": round(duration, 3),
            "attempts": attempts,
        })

    bench = None
    bench_path = out / "bench.json"
    t0 = time.perf_counter()
    try:
        binary = compile_bench(out, swift)
    except AssertionError as error:
        add("swift.bench", "fail", str(error), time.perf_counter() - t0, 1)
    else:
        status, detail, attempts = reportlib.execute(lambda: run_bench(binary, bench_path), 120)
        if status == "pass":
            bench = json.loads(bench_path.read_text(encoding="utf-8"))
            detail = "bench.json"
        add("swift.bench", status, detail, time.perf_counter() - t0, attempts)

    if bench is not None:
        png_dir = out / "png"
        png_dir.mkdir(exist_ok=True)
        for state, points in bench["particles"].items():
            reportlib.plot_particles(png_dir / f"{state}.png", points, reportlib.STATE_COLORS.get(state, (255, 255, 255)))
        # The error phase uses the idle orb pose: orb.ts has no error color.
        reportlib.plot_particles(png_dir / "error.png", bench["particles"]["idle"], reportlib.STATE_COLORS["error"])
        reportlib.plot_particles(
            png_dir / "reduce-motion.png", bench["particles"]["idle"], reportlib.STATE_COLORS["reduce_motion"])
        for name, timeout, fn in build_cases(bench):
            t0 = time.perf_counter()
            status, detail, attempts = reportlib.execute(fn, timeout)
            add(name, status, detail, time.perf_counter() - t0, attempts)
    else:
        add("suite.followups", "fail", "bench did not produce JSON", 0.0, 1)

    try:
        reportlib.skip_xfail_gate(results)
        add("forge.skip_xfail_gate", "pass", "no skip or xfail", 0.0, 1)
    except AssertionError as error:
        add("forge.skip_xfail_gate", "fail", str(error), 0.0, 1)

    counts = {"pass": 0, "fail": 0, "skip": 0, "infra": 0}
    frames = {}
    cpu = {}
    for item in results:
        counts[item["status"]] = counts.get(item["status"], 0) + 1
        if item["name"] in ("frames.60", "frames.120") and item["status"] == "pass":
            frames[item["name"].split(".")[1]] = json.loads(item["detail"])
        if item["name"] == "budget.idle_cpu_and_memory" and item["status"] == "pass":
            cpu = json.loads(item["detail"])
    overall = "pass" if counts["fail"] == 0 and counts["skip"] == 0 and counts["infra"] == 0 else "fail"
    summary = {
        "sha": commit,
        "sha8": commit[:8],
        "result": overall,
        "counts": counts,
        "duration_s": round(time.time() - started, 3),
        "tests": results,
        "frames": frames,
        "cpu": cpu,
        "pngs": sorted(path.name for path in (out / "png").glob("*.png")) if (out / "png").exists() else [],
        "png_source": "simulation_plot",
        "fakes": "injected bass 0.35 mid 0.55 for speaking; other states silent; no microphone; no LLM; no TTS provider",
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    reportlib.write_junit(out / "junit.xml", results)
    print(f"orb-e2e: {overall}")
    print(f"output: {out}")
    print(json.dumps(counts))
    return 0 if overall == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
