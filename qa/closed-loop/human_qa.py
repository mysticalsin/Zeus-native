#!/usr/bin/env python3
"""Evidence folder, report and receipt writer for the human-style QA harness (scripts/human-qa.sh).

The Swift driver writes results-<phase>.json; this module merges them, adds crash reports and the log
stream, and writes report.md and receipt.json. A pass needs every expected step to have a result, no FAIL,
no new crash report and a clean driver exit. MANUAL steps never fail a run; they are listed for a human.

    human_qa.py check-app <Zeus.app>                      refuse an app inside the repo or not a bundle
    human_qa.py new-dir <base>                            create <base>/<timestamp>, print its path
    human_qa.py crashes <since-epoch> [<reports dir>]     list Zeus crash reports newer than the start
    human_qa.py finalize --evidence DIR --app APP --started EPOCH --driver-rc N [--only J] [--crash FILE]...
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[2]
STATUSES = ("PASS", "FAIL", "MANUAL")
FREEZE_SECONDS = 2.0
SETTINGS_PAGES = ["general", "appearance", "sounds", "notifications", "shortcuts", "insomnia", "integrations",
                  "murmure", "polyglot", "dictation", "voice", "engine", "features", "beamer", "license",
                  "permissions", "privacy", "diagnostics", "about"]

# Every step id the Swift driver must report, per journey. A missing id is a failure, not a silent skip.
JOURNEYS = {
    "launch": ["launch.process", "launch.window", "launch.topbar", "launch.nocrash"],
    "topbar": ["topbar.more-menu", "topbar.settings-open", "topbar.screenshare-flip", "topbar.screenshare-flip-back",
               "topbar.screenshare-settings-agrees", "topbar.position-slider", "topbar.persist-prep"],
    "settings": ["settings.sidebar-complete"] + ["settings.page." + p for p in SETTINGS_PAGES]
    + ["settings.dictation-sound-picker", "settings.dictation-sound-preview", "settings.jev-limit-default",
       "settings.about-credit", "settings.about-version", "settings.cards"],
    "record": ["record.open", "record.main-display", "record.display-names", "record.countdown",
               "record.esc-cancel", "record.idle-no-capture"],
    "scribe": ["scribe.open", "scribe.animation-settles", "scribe.up-next-or-empty", "scribe.chips",
               "scribe.memory-open", "scribe.memory-panes", "scribe.memory-search", "scribe.memory-close",
               "scribe.start-mic"],
    "alerts": ["alerts.open", "alerts.trigger"],
    "talk": ["talk.text-answer", "talk.voice"],
    "quit": ["quit.clean"],
    "persist": ["persist.launch", "persist.screenshare", "persist.position", "persist.restore", "persist.quit"],
}
SECRET = re.compile(r"sk-[A-Za-z0-9_-]{16,}|xi-api|api[_-]?key\s*[:=]|authorization:|bearer\s+[A-Za-z0-9]", re.I)


class Refused(Exception):
    pass


def check_app(app, repo=REPO):
    """Resolve the app bundle; it must be a real .app directory outside the repository."""
    path = Path(app).expanduser()
    if not path.exists():
        raise Refused(f"{app}: no such path")
    resolved = path.resolve()
    if resolved.suffix != ".app" or not resolved.is_dir():
        raise Refused(f"{app}: not an .app bundle")
    repo = Path(repo).resolve()
    if resolved == repo or repo in resolved.parents:
        raise Refused(f"{app}: the app must live outside the repository ({repo})")
    if not (resolved / "Contents" / "MacOS" / "Zeus").exists():
        raise Refused(f"{app}: Contents/MacOS/Zeus is missing")
    if not (resolved / "Contents" / "Info.plist").exists():
        raise Refused(f"{app}: Contents/Info.plist is missing")
    return resolved


def new_evidence_dir(base, now=None):
    """Create <base>/<YYYYmmdd-HHMMSS>; never reuse a folder (a clash gets -2, -3, ...). Mode 0700."""
    base = Path(base)
    base.mkdir(parents=True, exist_ok=True)
    stamp = (now or datetime.datetime.now()).strftime("%Y%m%d-%H%M%S")
    for n in range(1, 100):
        folder = base / (stamp if n == 1 else f"{stamp}-{n}")
        try:
            folder.mkdir(mode=0o700)
            return folder
        except FileExistsError:
            continue
    raise Refused(f"could not create a fresh evidence folder under {base}")


def crash_reports_since(since_epoch, reports_dir=None):
    """Zeus crash reports (.ips, .crash) written at or after `since_epoch`, oldest first."""
    folder = Path(reports_dir) if reports_dir else Path.home() / "Library/Logs/DiagnosticReports"
    if not folder.is_dir():
        return []
    found = []
    for item in folder.iterdir():
        if item.name.startswith("Zeus") and item.suffix in (".ips", ".crash") and item.is_file():
            if item.stat().st_mtime >= since_epoch:
                found.append(item)
    return sorted(found, key=lambda p: p.stat().st_mtime)


def load_results(folder):
    """Merge results-*.json (main then persist). Returns (steps, problems)."""
    steps, problems = [], []
    for phase in ("main", "persist"):
        path = Path(folder) / f"results-{phase}.json"
        if not path.exists():
            continue
        try:
            doc = json.loads(path.read_text())
        except ValueError as error:
            problems.append(f"{path.name} is not valid JSON: {error}")
            continue
        for step in doc.get("steps", []):
            step = dict(step)
            step["phase"] = phase
            steps.append(step)
    return steps, problems


def validate_step(step):
    """Problems with one step record (shape, status, reason rules)."""
    problems = []
    sid = step.get("id", "?")
    if step.get("status") not in STATUSES:
        problems.append(f"{sid}: status {step.get('status')!r} is not PASS, FAIL or MANUAL")
    if step.get("status") in ("FAIL", "MANUAL") and not str(step.get("reason", "")).strip():
        problems.append(f"{sid}: {step.get('status')} without a reason")
    latency = step.get("latency_ms")
    if latency is not None and (isinstance(latency, bool) or not isinstance(latency, (int, float)) or latency < 0):
        problems.append(f"{sid}: latency_ms must be a non-negative number")
    return problems


def expected_ids(only=None, persist=True):
    ids = []
    for journey, items in JOURNEYS.items():
        if journey == "persist":
            if only is None and persist:
                ids += items
            continue
        if journey == "quit" and only is not None:
            continue
        if only is None or only == journey:
            ids += items
    return ids


def summarize(steps, only=None, persist=True):
    """Counts, missing ids and the freeze list."""
    seen = {}
    for step in steps:
        seen[step["id"]] = step
    counts = {s: sum(1 for step in steps if step.get("status") == s) for s in STATUSES}
    missing = [i for i in expected_ids(only, persist) if i not in seen]
    unknown = [i for i in seen if i not in {x for items in JOURNEYS.values() for x in items}]
    freezes = [s for s in steps if (s.get("max_wait_ms") or 0) > FREEZE_SECONDS * 1000]
    return {"counts": counts, "missing": missing, "unknown": unknown, "freezes": freezes, "total": len(steps)}


def verdict(summary, driver_rc, crashes, problems):
    """pass, pass-with-manual, or fail. MANUAL alone never fails; everything else listed does."""
    if summary["counts"]["FAIL"] or summary["missing"] or crashes or problems or driver_rc not in (0, 1):
        return "fail"
    if driver_rc == 1:
        return "fail"
    return "pass-with-manual" if summary["counts"]["MANUAL"] else "pass"


LOG_TIME = re.compile(r"^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})")


def log_excerpt(log_path, around_epoch, window=3.0, limit=25):
    """Log-stream lines within `window` seconds of an epoch (local time stamps); empty when unreadable."""
    path = Path(log_path)
    if not path.exists():
        return []
    out = []
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return []
    for line in lines:
        m = LOG_TIME.match(line)
        if not m:
            continue
        try:
            when = datetime.datetime.strptime(f"{m.group(1)} {m.group(2)}", "%Y-%m-%d %H:%M:%S").timestamp()
        except ValueError:
            continue
        if abs(when - around_epoch) <= window:
            out.append(line[:300])
            if len(out) >= limit:
                break
    return out


def _cell(text):
    return str(text).replace("|", "/").replace("\n", " ")


def render_report(steps, summary, verdict_text, meta, crashes, excerpts):
    """report.md: verdict, pass/fail per step with timings, log excerpts around failures."""
    lines = ["# Zeus human QA report", "",
             f"Verdict: **{verdict_text}**", "",
             f"- App: `{meta.get('app', '')}`", f"- Started: {meta.get('started', '')}",
             f"- macOS: {meta.get('macos', 'unknown')}",
             f"- Steps: {summary['total']} ({summary['counts']['PASS']} PASS, {summary['counts']['FAIL']} FAIL, "
             f"{summary['counts']['MANUAL']} MANUAL)",
             f"- Driver exit code: {meta.get('driver_rc')}", f"- New crash reports: {len(crashes)}", ""]
    if summary["missing"]:
        lines += ["## Steps that never ran", ""] + [f"- `{i}`" for i in summary["missing"]] + [""]
    if crashes:
        lines += ["## Crash reports", ""] + [f"- `{c}`" for c in crashes] + [""]
    if summary["freezes"]:
        lines += ["## Waits over 2 s (freeze evidence)", ""]
        for s in summary["freezes"]:
            ev = ", ".join(f"`{Path(e).name}`" for e in s.get("evidence", []) if "sample" in e)
            lines.append(f"- `{s['id']}`: {s['max_wait_ms']} ms. {ev}")
        lines.append("")
    current = None
    for step in steps:
        if step["journey"] != current:
            current = step["journey"]
            lines += ["", f"## {current}", "", "| Step | Result | Latency ms | Longest wait ms | Detail |", "|---|---|---|---|---|"]
        lat = step.get("latency_ms", "")
        lines.append(f"| {_cell(step['name'])} (`{step['id']}`) | {step['status']} | {lat} | {step.get('max_wait_ms', '')} | {_cell(step.get('reason', ''))} |")
    manual = [s for s in steps if s["status"] == "MANUAL"]
    if manual:
        lines += ["", "## Needs a human", ""] + [f"- `{s['id']}`: {s['reason']}" for s in manual]
    failed = [s for s in steps if s["status"] == "FAIL"]
    if failed:
        lines += ["", "## Log excerpts around failures", ""]
        for s in failed:
            lines += [f"### {s['id']}", "", "```"] + (excerpts.get(s["id"]) or ["(no log lines in this window)"]) + ["```", ""]
    lines.append("")
    return "\n".join(lines)


def _sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_receipt(folder, steps, summary, verdict_text, meta, crashes):
    """receipt.json: machine-readable result plus hashes of the files it summarizes."""
    folder = Path(folder)
    files = {}
    for name in ("report.md", "results-main.json", "results-persist.json", "zeus-log.txt"):
        if (folder / name).exists():
            files[name] = _sha(folder / name)
    receipt = {
        "schema_version": 1, "verdict": verdict_text, "app": meta.get("app"), "started_at": meta.get("started"),
        "finished_at": datetime.datetime.now().isoformat(timespec="seconds"), "macos": meta.get("macos"),
        "driver_rc": meta.get("driver_rc"), "counts": summary["counts"], "missing_steps": summary["missing"],
        "crash_reports": [str(c) for c in crashes], "freeze_steps": [s["id"] for s in summary["freezes"]],
        "steps": [{k: s.get(k) for k in ("id", "journey", "status", "reason", "latency_ms", "max_wait_ms")} for s in steps],
        "files": files,
    }
    text = json.dumps(receipt, indent=2, sort_keys=True)
    if SECRET.search(text):
        raise Refused("receipt would contain something that looks like a credential")
    (folder / "receipt.json").write_text(text + "\n")
    return receipt


def finalize(folder, app, started, driver_rc, only=None, crashes=(), log_path=None):
    folder = Path(folder)
    steps, problems = load_results(folder)
    for step in steps:
        problems += validate_step(step)
    persist_expected = (folder / "results-persist.json").exists() or only is None
    summary = summarize(steps, only, persist_expected)
    crash_paths = [Path(c) for c in crashes]
    verdict_text = verdict(summary, driver_rc, crash_paths, problems)
    info = {}
    info_path = folder / "driver-info-main.json"
    if info_path.exists():
        try:
            info = json.loads(info_path.read_text())
        except ValueError:
            pass
    meta = {"app": str(app), "started": datetime.datetime.fromtimestamp(float(started)).isoformat(timespec="seconds"),
            "macos": info.get("macos", "unknown"), "driver_rc": driver_rc}
    excerpts = {}
    log_file = log_path or (folder / "zeus-log.txt")
    for step in steps:
        if step["status"] == "FAIL":
            excerpts[step["id"]] = log_excerpt(log_file, step.get("ended_at", 0))
    report = render_report(steps, summary, verdict_text, meta, crash_paths, excerpts)
    if problems:
        report += "\n## Problems with the results files\n\n" + "\n".join(f"- {p}" for p in problems) + "\n"
    (folder / "report.md").write_text(report)
    write_receipt(folder, steps, summary, verdict_text, meta, crash_paths)
    return verdict_text


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check-app").add_argument("app")
    sub.add_parser("new-dir").add_argument("base")
    p = sub.add_parser("crashes")
    p.add_argument("since")
    p.add_argument("dir", nargs="?")
    p = sub.add_parser("finalize")
    p.add_argument("--evidence", required=True)
    p.add_argument("--app", required=True)
    p.add_argument("--started", required=True)
    p.add_argument("--driver-rc", type=int, required=True)
    p.add_argument("--only")
    p.add_argument("--crash", action="append", default=[])
    args = parser.parse_args(argv)
    try:
        if args.cmd == "check-app":
            print(check_app(args.app))
        elif args.cmd == "new-dir":
            print(new_evidence_dir(args.base))
        elif args.cmd == "crashes":
            for item in crash_reports_since(float(args.since), args.dir):
                print(item)
        else:
            result = finalize(args.evidence, args.app, args.started, args.driver_rc, args.only, args.crash)
            print(result)
            return 0 if result.startswith("pass") else 1
    except Refused as error:
        print(f"human-qa: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
