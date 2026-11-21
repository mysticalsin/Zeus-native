"""Receipt rules for the native hands-on QA harness.

A later Mac run fills one screenshot slot and one result slot per scripted step.
This module returns pass only when every public step is present, the result is
"passed", and the screenshot is a non-empty regular file. Missing, skipped,
and failed steps are not a pass.

    python3 -I qa/native-qa/validate.py RECEIPT.json
"""
import argparse
import json
from pathlib import Path
import re
import sys

MIN_FREE_BYTES = 6 * 1024 ** 3
SCHEMA = "zeus-native-qa-receipt/1"
INSTALLED_APP = Path("/Applications/Zeus.app")
HEAD_RE = re.compile(r"[0-9a-f]{40}\Z")
SECRET = re.compile(
    r"sk-[A-Za-z0-9_-]{16,}|xi-api|api[_-]?key\s*[:=]|authorization:|bearer\s+[A-Za-z0-9]",
    re.I,
)
STEPS_PATH = Path(__file__).with_name("steps.json")


class Refused(Exception):
    pass


def catalog():
    """Scripted steps in the public hands-on order."""
    document = json.loads(STEPS_PATH.read_text())
    return document["steps"]


def blank_receipt(head, app):
    """Empty slots a later run fills in. The verdict is not-run."""
    steps = []
    for step in catalog():
        steps.append({
            "id": step["id"],
            "title": step["title"],
            "script": list(step["script"]),
            "screenshot": "",
            "result": "",
        })
    return {
        "schema": SCHEMA,
        "head": head,
        "app": str(app),
        "verdict": "not-run",
        "steps": steps,
    }


def desktop_app(home, head):
    """The only build destination: ~/Desktop/Zeus-latest-<sha8>.app."""
    if not isinstance(head, str) or not HEAD_RE.fullmatch(head):
        raise Refused(f"head must be 40 lowercase hex characters, got {head!r}")
    return Path(home) / "Desktop" / f"Zeus-latest-{head[:8]}.app"


def refuse_if_installed(dest):
    """Refuse the installed app path."""
    dest = Path(dest)
    if dest == INSTALLED_APP or dest.resolve() == INSTALLED_APP:
        raise Refused("refusing to build over /Applications/Zeus.app")


def build_commands():
    """The only build invocation. It does not install the app."""
    return [["swift", "build", "-c", "release"]]


def require_free_space(paths, usage):
    """Refuse when any path has less than 6 GiB free."""
    for path in paths:
        path = Path(path)
        if not path.is_dir():
            raise Refused(f"{path} is not a directory")
        free = usage(path).free
        if free < MIN_FREE_BYTES:
            raise Refused(f"need at least 6 GiB free on {path}, found {free} bytes")


def prepare(head, home, repo, usage, run, platform_name="Darwin", assemble=None):
    """Check the Mac and free space, then build. A short disk never starts the build."""
    if platform_name != "Darwin":
        raise Refused("macOS only")
    home = Path(home)
    repo = Path(repo)
    desktop = home / "Desktop"
    require_free_space([desktop, repo], usage)
    dest = desktop_app(home, head)
    refuse_if_installed(dest)
    for command in build_commands():
        run(command)
    if assemble is not None:
        assemble(repo, dest)
    return blank_receipt(head, str(dest))


def _screenshot_problem(step_id, value, base_dir):
    if not isinstance(value, str) or not value.strip():
        return f"{step_id}: screenshot is missing"
    path = Path(value)
    if not path.is_absolute():
        path = Path(base_dir) / path
    if path.is_symlink() or not path.is_file() or path.stat().st_size <= 0:
        return f"{step_id}: screenshot is not a real file"
    return None


def judge(receipt, base_dir):
    """Return ('pass', []) or ('fail', reasons). The receipt's own verdict is ignored."""
    reasons = []
    if not isinstance(receipt, dict):
        return "fail", ["receipt is not an object"]
    try:
        encoded = json.dumps(receipt)
    except (TypeError, ValueError) as error:
        return "fail", [f"receipt is not serializable: {error}"]
    if SECRET.search(encoded):
        reasons.append("receipt looks like it contains a credential")
    if receipt.get("schema") != SCHEMA:
        reasons.append(f"schema must be {SCHEMA}")
    head = receipt.get("head")
    if not isinstance(head, str) or not HEAD_RE.fullmatch(head):
        reasons.append("head must be 40 lowercase hex characters")
        expected_name = None
    else:
        expected_name = f"Zeus-latest-{head[:8]}.app"
    app = receipt.get("app")
    if isinstance(app, str) and (Path(app) == INSTALLED_APP or Path(app).resolve() == INSTALLED_APP):
        reasons.append("refusing /Applications/Zeus.app")
    if expected_name is not None:
        name = Path(app).name if isinstance(app, str) else ""
        if name != expected_name:
            reasons.append(f"app must be named {expected_name}")
    steps = receipt.get("steps")
    if not isinstance(steps, list):
        reasons.append("steps must be a list")
        steps = []
    expected = [step["id"] for step in catalog()]
    seen = []
    for step in steps:
        if not isinstance(step, dict):
            reasons.append("step is not an object")
            continue
        sid = step.get("id", "?")
        if sid in seen:
            reasons.append(f"{sid}: duplicate step")
        seen.append(sid)
        if step.get("result") != "passed":
            reasons.append(f"{sid}: result {step.get('result')!r} is not passed")
            continue
        problem = _screenshot_problem(sid, step.get("screenshot"), base_dir)
        if problem:
            reasons.append(problem)
    for sid in expected:
        if sid not in seen:
            reasons.append(f"{sid}: missing")
    for sid in seen:
        if sid not in expected:
            reasons.append(f"{sid}: unknown step")
    if seen != expected and sorted(seen) == sorted(expected) and len(seen) == len(set(seen)):
        reasons.append("steps are not the public list in order")
    if reasons:
        return "fail", reasons
    return "pass", []


def main(argv=None):
    parser = argparse.ArgumentParser(description="Validate a native QA receipt. Exit 0 only for a pass.")
    parser.add_argument("receipt", help="path to the receipt JSON")
    parser.add_argument("--base", help="directory for relative screenshot paths")
    args = parser.parse_args(argv)
    path = Path(args.receipt)
    try:
        receipt = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        print(f"fail: {error}", file=sys.stderr)
        return 1
    base = Path(args.base) if args.base else path.parent
    verdict, reasons = judge(receipt, base)
    if verdict != "pass":
        for reason in reasons:
            print(reason, file=sys.stderr)
        print("fail")
        return 1
    print("pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
