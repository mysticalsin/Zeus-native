"""Receipt rules for the native hands-on QA harness.

A later manual Mac run fills one screenshot slot and one result slot per step.
Results use the hands-on statuses PASS, FAIL, and MANUAL. Only PASS can pass.
A screenshot must be a real PNG, at least 200 by 100, and not one colour.
The receipt must show an app pid or a Desktop bundle path captured at runtime.
A receipt marked FAIL does not pass. A Linux run marks every Mac journey
unproven, and an unproven receipt does not pass.

    python3 -I qa/native-qa/validate.py RECEIPT.json
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import struct
import sys
import zlib

MIN_FREE_BYTES = 6 * 1024 ** 3
SCHEMA = "zeus-native-qa-receipt/1"
PASS_RESULT = "PASS"
UNPROVEN = "unproven"
PNG_SIG = b"\x89PNG\r\n\x1a\n"
INSTALLED_APP = Path("/Applications/Zeus.app")
HEAD_RE = re.compile(r"[0-9a-f]{40}\Z")
SECRET = re.compile(
    r"sk-[A-Za-z0-9_-]{16,}|xi-api|api[_-]?key\s*[:=]|authorization:|bearer\s+[A-Za-z0-9]",
    re.I,
)
STEPS_PATH = Path(__file__).with_name("steps.json")


class Refused(Exception):
    pass


def _load_human_qa():
    """Load the public journey list by path. Isolated Python does not import the package."""
    path = Path(__file__).resolve().parents[1] / "closed-loop" / "human_qa.py"
    spec = importlib.util.spec_from_file_location("zeus_human_qa_journeys", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_human_qa = _load_human_qa()


def catalog():
    """Scripted steps in the public hands-on order."""
    document = json.loads(STEPS_PATH.read_text())
    return document["steps"]


def journey_catalog():
    """Public hands-on journeys in the same order as qa/closed-loop/human_qa.py."""
    return [(name, list(step_ids)) for name, step_ids in _human_qa.JOURNEYS.items()]


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


def unproven_receipt(head, app, platform_name):
    """A receipt for a host that did not run the Mac journeys. It cannot pass."""
    if platform_name == "Darwin":
        raise Refused("a Mac run is not labeled unproven")
    if not isinstance(platform_name, str) or not platform_name.strip():
        raise Refused("platform is missing")
    receipt = blank_receipt(head, app)
    receipt["verdict"] = UNPROVEN
    receipt["platform"] = platform_name
    receipt["manual_run"] = True
    receipt["opened_by_harness"] = False
    receipt["runtime_app_pid"] = None
    receipt["runtime_app_bundle"] = None
    journeys = []
    for name, step_ids in journey_catalog():
        journeys.append({
            "id": name,
            "status": UNPROVEN,
            "reason": "macOS only",
            "steps": step_ids,
        })
    receipt["journeys"] = journeys
    for step in receipt["steps"]:
        step["result"] = UNPROVEN
    names = ", ".join(journey["id"] for journey in journeys)
    receipt["log"] = (
        f"unproven: {platform_name} did not build or open Zeus. "
        f"Mac-only journeys: {names}.\n"
    )
    return receipt


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
        run(command, cwd=repo)
    if assemble is not None:
        assemble(repo, dest)
    return blank_receipt(head, str(dest))


def _paeth(left, up, up_left):
    estimate = left + up - up_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    up_left_distance = abs(estimate - up_left)
    if left_distance <= up_distance and left_distance <= up_left_distance:
        return left
    if up_distance <= up_left_distance:
        return up
    return up_left


def _require_png(path):
    """Signature, IHDR, at least 200x100, and more than one colour."""
    data = Path(path).read_bytes()
    if len(data) < 8 or data[:8] != PNG_SIG:
        raise ValueError("is not a PNG")
    pos = 8
    ihdr = None
    idat = []
    while pos + 8 <= len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        tag = data[pos + 4:pos + 8]
        pos += 8
        if pos + length + 4 > len(data):
            raise ValueError("is not a PNG")
        chunk = data[pos:pos + length]
        crc = int.from_bytes(data[pos + length:pos + length + 4], "big")
        if (zlib.crc32(tag + chunk) & 0xFFFFFFFF) != crc:
            raise ValueError("is not a PNG")
        pos += length + 4
        if ihdr is None and tag != b"IHDR":
            raise ValueError("is not a PNG")
        if tag == b"IHDR":
            if ihdr is not None or len(chunk) != 13:
                raise ValueError("is not a PNG")
            ihdr = struct.unpack(">IIBBBBB", chunk)
            width, height = ihdr[0], ihdr[1]
            if width < 200 or height < 100:
                raise ValueError("is smaller than 200x100")
        elif tag == b"IDAT":
            idat.append(chunk)
        elif tag == b"IEND":
            break
    if ihdr is None or not idat:
        raise ValueError("is not a PNG")
    width, height, bit_depth, color_type, compression, filtering, interlace = ihdr
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if (
        channels is None or bit_depth != 8 or compression != 0 or filtering != 0 or interlace != 0
        or width > 8192 or height > 8192
    ):
        raise ValueError("is not a PNG")
    try:
        raw = zlib.decompress(b"".join(idat))
    except zlib.error as error:
        raise ValueError("is not a PNG") from error
    stride = width * channels
    if len(raw) < height * (stride + 1):
        raise ValueError("is not a PNG")
    first = None
    offset = 0
    previous = bytearray(stride)
    for _y in range(height):
        filter_type = raw[offset]
        offset += 1
        scan = raw[offset:offset + stride]
        offset += stride
        if len(scan) != stride or filter_type > 4:
            raise ValueError("is not a PNG")
        row = bytearray(stride)
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            up = previous[x]
            up_left = previous[x - channels] if x >= channels else 0
            sample = scan[x]
            if filter_type == 0:
                value = sample
            elif filter_type == 1:
                value = (sample + left) & 255
            elif filter_type == 2:
                value = (sample + up) & 255
            elif filter_type == 3:
                value = (sample + ((left + up) // 2)) & 255
            else:
                value = (sample + _paeth(left, up, up_left)) & 255
            row[x] = value
        previous = row
        for x in range(0, stride, channels):
            pixel = bytes(row[x:x + channels])
            if first is None:
                first = pixel
            elif pixel != first:
                return
    raise ValueError("is one colour")


def _screenshot_problem(step_id, value, base_dir):
    if not isinstance(value, str) or not value.strip():
        return f"{step_id}: screenshot is missing"
    path = Path(value)
    if not path.is_absolute():
        path = Path(base_dir) / path
    if path.is_symlink() or not path.is_file() or path.stat().st_size <= 0:
        return f"{step_id}: screenshot is not a real file"
    try:
        _require_png(path)
    except ValueError as error:
        return f"{step_id}: screenshot {error}"
    return None


def _log_problem(receipt):
    """An empty log, or one torn off before its final newline, is not evidence."""
    log = receipt.get("log")
    if not isinstance(log, str) or not log.strip():
        return "log is empty"
    if not log.endswith("\n"):
        return "log is truncated"
    return None


def _journey_problems(receipt):
    """Unproven journeys stay unproven. A missing list is not a pass by itself."""
    journeys = receipt.get("journeys")
    if journeys is None:
        return []
    if not isinstance(journeys, list):
        return ["journeys must be a list"]
    problems = []
    for journey in journeys:
        if not isinstance(journey, dict):
            problems.append("journey is not an object")
            continue
        if journey.get("status") == UNPROVEN:
            problems.append(f"{journey.get('id', '?')}: unproven")
    return problems


def _runtime_problem(receipt):
    """FAIL, an unproven host, a harness launch, or no captured pid or bundle path."""
    if receipt.get("verdict") == "unproven":
        return "receipt is unproven"
    host = receipt.get("platform")
    if isinstance(host, str) and host != "Darwin":
        return f"{host} is unproven"
    if receipt.get("verdict") == "FAIL":
        return "receipt is marked FAIL"
    if receipt.get("manual_run") is not True:
        return "manual-run receipt must record manual_run"
    if receipt.get("opened_by_harness") is not False:
        return "harness must not open Zeus"
    app = receipt.get("app")
    pid = receipt.get("runtime_app_pid")
    bundle = receipt.get("runtime_app_bundle")
    pid_ok = isinstance(pid, int) and not isinstance(pid, bool) and pid > 0
    if isinstance(bundle, str) and bundle:
        path = Path(bundle)
        if path == INSTALLED_APP or path.resolve() == INSTALLED_APP:
            return "refusing /Applications/Zeus.app"
        if isinstance(app, str) and bundle != app:
            return "runtime bundle path does not match the app"
        executable = path / "Contents" / "MacOS" / "Zeus"
        if path.is_symlink() or executable.is_symlink() or not executable.is_file():
            if not pid_ok:
                return "runtime app pid or bundle path was not captured"
        else:
            return None
    if pid_ok:
        return None
    return "runtime app pid or bundle path was not captured"


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
        if step.get("result") != PASS_RESULT:
            reasons.append(f"{sid}: result {step.get('result')!r} is not PASS")
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
    runtime = _runtime_problem(receipt)
    if runtime:
        reasons.append(runtime)
    reasons.extend(_journey_problems(receipt))
    log_problem = _log_problem(receipt)
    if log_problem:
        reasons.append(log_problem)
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
