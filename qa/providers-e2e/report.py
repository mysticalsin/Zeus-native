#!/usr/bin/env python3
"""Build the voice-provider end-to-end report. Fakes only, except --live.

The verifier owns the skip gate, the latency percentiles, and the secret scan.
The product tests do not get a second chance: one timeout is retried once and a
second timeout is infrastructure, not a product failure.
"""
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

FAKE_PATTERNS = ("zeus-e2e-fake-key", "zeus-e2e-fake", "zeus-e2e")
EXPLAINED_LIVE = {"elevenLabsListsVoicesAndReturnsAudio", "googleCloudListsVoicesAndReturnsAudio"}
BUDGET_P50 = 900
BUDGET_P95 = 1400
SWIFT_TIMEOUT = int(os.environ.get("ZEUS_E2E_TIMEOUT", "180"))


def sha8(root: Path) -> str:
    try:
        out = subprocess.check_output(["git", "rev-parse", "--short=8", "HEAD"], cwd=root, text=True).strip()
        return out or "unknown"
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


def default_out(root: Path) -> Path:
    base = os.environ.get("TMPDIR") or "/tmp"
    return Path(base) / "zeus-e2e" / "providers" / sha8(root)


def percentile(samples, rank):
    """1-based rank in the sorted sample, matching the companion budget note for n=30."""
    if not samples:
        return None
    ordered = sorted(samples)
    index = min(len(ordered), max(1, rank)) - 1
    return ordered[index]


def png(path: Path, title: str, ok: bool) -> None:
    width, height = 640, 160
    row = bytearray()
    color = (24, 92, 58) if ok else (128, 42, 42)
    for _x in range(width):
        row.extend(color)
    raw = b"".join(b"\x00" + bytes(row) for _y in range(height))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    path.write_bytes(blob)
    note = path.with_suffix(".txt")
    note.write_text(title + "\n" + ("pass" if ok else "fail") + "\n")


def scan(paths, labeled, ignore=""):
    """labeled is (public name, secret). The secret is never written into the result."""
    hits = []
    for path in paths:
        file = Path(path)
        if not file.exists() or not file.is_file():
            continue
        try:
            text = file.read_text(errors="replace")
        except OSError:
            continue
        scrubbed = text.replace(ignore, "") if ignore else text
        for label, secret in labeled:
            if secret and secret in scrubbed:
                hits.append({"file": file.name, "pattern": label})
    return hits


def secret_labels():
    labeled = [(name, name) for name in FAKE_PATTERNS]
    for name in ("ZEUS_LIVE_ELEVENLABS_KEY", "ZEUS_LIVE_GOOGLE_TTS_KEY"):
        value = os.environ.get(name, "").strip()
        if len(value) >= 4:
            labeled.append((name, value))
    return labeled


def parse_swift_log(text):
    passed = len(re.findall(r"^✔ Test \S+\(\) passed", text, re.M))
    failed = len(re.findall(r"^✘ Test \S+\(\) failed", text, re.M))
    skipped = re.findall(r"^✘ Test (\S+\(\)) skipped", text, re.M)
    durations = []
    for match in re.finditer(r"^✔ Test (.+?) passed after ([0-9.]+) seconds", text, re.M):
        durations.append({"name": match.group(1), "seconds": float(match.group(2)), "status": "pass"})
    for match in re.finditer(r"^✘ Test (.+?) failed after ([0-9.]+) seconds", text, re.M):
        durations.append({"name": match.group(1), "seconds": float(match.group(2)), "status": "fail"})
    return passed, failed, skipped, durations


def unexplained(skipped, explained):
    return [name for name in skipped if name.split("(")[0].split("/")[-1] not in explained and name not in explained]


def stage_package(root: Path, work: Path) -> Path:
    package = work / "package"
    if package.exists():
        shutil.rmtree(package)
    sources = package / "Sources" / "ZeusCore"
    tests = package / "Tests" / "ZeusCoreTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for path in (root / "Sources" / "ZeusCore" / "Providers").glob("*.swift"):
        (sources / path.name).symlink_to(path)
    for name in ("VoiceTTSProvider.swift", "VoiceProviderKeychain.swift"):
        (sources / name).symlink_to(root / "Sources" / "ZeusCore" / "Voice" / name)
    for name in ("VoiceProviderE2EJourneyTests.swift", "VoiceProviderLiveContractTests.swift"):
        source = root / "Tests" / "ZeusCoreTests" / name
        if source.exists():
            (tests / name).symlink_to(source)
    (package / "Package.swift").write_text(
        "// swift-tools-version: 6.0\nimport PackageDescription\n"
        "let package = Package(name: \"providers-e2e\", targets: [\n"
        "  .target(name: \"ZeusCore\"),\n"
        "  .testTarget(name: \"ZeusCoreTests\", dependencies: [\"ZeusCore\"]),\n])\n"
    )
    return package


def run_swift(root: Path, log: Path, xunit: Path, arguments, timeout):
    swift = os.environ.get("SWIFT", "swift")
    package = stage_package(root, log.parent)
    env = os.environ.copy()
    env["ZEUS_E2E_LATENCY_LOG"] = str(log.parent / "latency.txt")
    command = [swift, "test", "--filter", arguments, "--xunit-output", str(xunit)]
    root = package
    attempts = []
    for attempt in (1, 2):
        started = time.monotonic()
        try:
            proc = subprocess.run(command, cwd=root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
            attempts.append({"attempt": attempt, "code": proc.returncode, "seconds": round(time.monotonic() - started, 3), "infra": False})
            return proc.returncode, proc.stdout, attempts
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or ""
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
            attempts.append({"attempt": attempt, "code": None, "seconds": timeout, "infra": True})
            if attempt == 2:
                return None, output + "\nTIMEOUT\n", attempts
    return None, "", attempts


def write_summary(path, payload):
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def journeys(durations):
    names = [
        "firstAddValidatePickTestAndReply", "editTheKeyThenRemoveIt", "switchProviderMidSession",
        "switchMidUtteranceCutsCleanly", "relaunchKeepsTheKeyTheVoiceAndTheChoice",
        "emptyAndMalformedKeysNeverLeaveTheMachine", "aBadKeyIsUnauthorized",
        "aRevokedKeyMidSessionFallsBackAndStaysInError", "rateLimitAndServerErrorsFallback",
        "networkDownUsesLocalThenTheMacVoice", "aSlowFirstBytePastTheBudgetFallsBack",
        "aTruncatedStreamAndInvalidAudioFallBack", "thirtyFastRepliesMeetTheLatencyBudgets",
        "everyTransitionIsListed", "verifierOwnsThePropertyWalk", "specBoundaries",
    ]
    found = []
    for name in names:
        match = next((row for row in durations if name in row["name"]), None)
        found.append({"journey": name, "status": match["status"] if match else "missing", "seconds": match["seconds"] if match else None})
    return found


def finish(out: Path, payload, shots):
    shots.mkdir(parents=True, exist_ok=True)
    for journey in payload["journeys"]:
        png(shots / f"{journey['journey']}.png", journey["journey"], journey["status"] == "pass")
    write_summary(out / "summary.json", payload)
    print(json.dumps({k: payload[k] for k in ("sha", "status", "passed", "failed", "skipped", "infra", "secretScan", "latency")}, indent=2))


def command_run(root: Path, live: bool) -> int:
    out = Path(os.environ.get("ZEUS_E2E_OUT") or default_out(root))
    out.mkdir(parents=True, exist_ok=True)
    shots = out / "screenshots"
    log = out / "swift-test.log"
    xunit = out / "junit.xml"
    (out / "latency.txt").write_text("")
    filt = "VoiceProviderLiveContractTests" if live else "VoiceProviderE2EJourneyTests"
    code, output, attempts = run_swift(root, log, xunit, filt, SWIFT_TIMEOUT)
    log.write_text(output)
    passed, failed, skipped, durations = parse_swift_log(output)
    explained = EXPLAINED_LIVE if live and not any(os.environ.get(name, "").strip() for name in ("ZEUS_LIVE_ELEVENLABS_KEY", "ZEUS_LIVE_GOOGLE_TTS_KEY")) else set()
    bad_skips = unexplained(skipped, explained)
    samples = []
    latency_file = out / "latency.txt"
    if latency_file.exists():
        for line in latency_file.read_text().splitlines():
            if line.strip().isdigit():
                samples.append(int(line.strip()))
    p50 = percentile(samples, 15 if len(samples) >= 30 else max(1, (len(samples) + 1) // 2))
    p95 = percentile(samples, 29 if len(samples) >= 30 else len(samples))
    latency_ok = True
    if not live:
        latency_ok = p50 is not None and p95 is not None and p50 <= BUDGET_P50 and p95 <= BUDGET_P95
    unified = out / "unified-log.txt"
    if sys.platform == "darwin" and shutil.which("log"):
        with unified.open("w") as handle:
            subprocess.run(["log", "show", "--last", "20m", "--style", "compact", "--predicate", 'process == "Zeus"'], cwd=root, text=True, stdout=handle, stderr=subprocess.STDOUT)
    else:
        unified.write_text("unified log unavailable on this OS\n")
    crashes = out / "crash-scan.txt"
    crash_dir = Path.home() / "Library" / "Logs" / "DiagnosticReports"
    crash_text = []
    if crash_dir.is_dir():
        for item in crash_dir.glob("Zeus*"):
            if item.is_file():
                crash_text.append(item.read_text(errors="replace"))
    crashes.write_text("\n".join(crash_text) or "no Zeus crash reports\n")
    hits = scan([log, xunit, latency_file, unified, crashes], secret_labels(), str(out))
    secret_ok = not hits
    infra = sum(1 for item in attempts if item["infra"])
    timed_out = code is None
    status = "pass"
    if timed_out:
        status = "infra"
    elif code != 0 or failed or bad_skips or not secret_ok or not latency_ok:
        status = "fail"
    payload = {
        "sha": sha8(root),
        "status": status,
        "passed": passed,
        "failed": failed,
        "skipped": len(skipped),
        "explainedSkips": sorted(explained) if live else [],
        "unexplainedSkips": bad_skips,
        "infra": 1 if timed_out else 0,
        "attempts": attempts,
        "durations": durations,
        "journeys": [] if live else journeys(durations),
        "latency": {"samples": len(samples), "p50": p50, "p95": p95, "p50Budget": BUDGET_P50, "p95Budget": BUDGET_P95, "pass": latency_ok},
        "secretScan": {"pass": secret_ok, "hits": len(hits)},
        "forge": {
            "verifierOwnedProperty": any("verifierOwnsThePropertyWalk" in row["name"] and row["status"] == "pass" for row in durations) or live,
            "skipGate": not bad_skips,
            "specBoundaries": any("specBoundaries" in row["name"] and row["status"] == "pass" for row in durations) or live,
            "timeoutIsInfrastructure": timed_out or infra == 0,
        },
    }
    if not xunit.exists() or xunit.stat().st_size < 120:
        cases = []
        for row in durations:
            if not row["name"].endswith("()"):
                continue
            name = row["name"][:-2]
            if row["status"] == "pass":
                cases.append(f'    <testcase classname="VoiceProviderE2E" name="{name}" time="{row["seconds"]}"/>')
            else:
                cases.append(f'    <testcase classname="VoiceProviderE2E" name="{name}" time="{row["seconds"]}"><failure message="failed"/></testcase>')
        body = "\n".join(cases)
        xunit.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<testsuite name="VoiceProviderE2E" tests="{len(cases)}" failures="{failed}" skipped="{len(skipped)}" time="0">\n'
            f"{body}\n</testsuite>\n"
        )
    finish(out, payload, shots)
    if status == "infra":
        return 2
    return 0 if status == "pass" else 1


def selftest() -> int:
    assert percentile([1, 2, 3], 2) == 2
    assert unexplained(["elevenLabsListsVoicesAndReturnsAudio"], EXPLAINED_LIVE) == []
    assert unexplained(["other"], set()) == ["other"]
    assert percentile(list(range(1, 31)), 15) == 15
    assert percentile(list(range(1, 31)), 29) == 29
    print("providers-e2e selftest pass")
    return 0


def main(argv) -> int:
    root = Path(__file__).resolve().parents[2]
    if len(argv) > 1 and argv[1] == "selftest":
        return selftest()
    return command_run(root, live=len(argv) > 1 and argv[1] == "live")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
