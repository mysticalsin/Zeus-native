"""manual-run harness for the Desktop build of Zeus.

It builds only ~/Desktop/Zeus-latest-<sha8>.app. It does not open Zeus and it
never launches /Applications/Zeus.app. A person opens the Desktop build. The
harness records a pid or bundle path only when that running app is observed.
A failed run writes a receipt marked FAIL, which cannot validate.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys


def _load_validate():
    """Load the sibling module by path. Isolated Python does not put the script directory on sys.path."""
    path = Path(__file__).with_name("validate.py")
    spec = importlib.util.spec_from_file_location("zeus_native_qa_validate", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_validate = _load_validate()
Refused = _validate.Refused
prepare = _validate.prepare
refuse_if_installed = _validate.refuse_if_installed

INSTALLED = "/Applications/Zeus.app"


def _run(command, cwd=None):
    subprocess.run(command, cwd=cwd, check=True)


def real_assemble(repo, dest, bin_dir=None):
    """Copy the release binary into the Desktop app. Ad hoc signature only."""
    refuse_if_installed(dest)
    dest = Path(dest)
    if str(dest) == INSTALLED or dest == Path(INSTALLED):
        raise Refused("refusing to build over /Applications/Zeus.app")
    if dest.parent.name != "Desktop" or not dest.name.startswith("Zeus-latest-") or not dest.name.endswith(".app"):
        raise Refused("builds go only to ~/Desktop/Zeus-latest-<sha8>.app")
    repo = Path(repo)
    if bin_dir is None:
        bin_dir = subprocess.check_output(
            ["swift", "build", "-c", "release", "--show-bin-path"], cwd=repo, text=True
        ).strip()
    exe = Path(bin_dir) / "Zeus"
    if not exe.is_file() or exe.is_symlink():
        raise Refused("the build did not produce a Zeus binary")
    if dest.exists():
        if dest.is_symlink() or not dest.is_dir():
            raise Refused("refusing to replace the build path")
        shutil.rmtree(dest)
    macos = dest / "Contents" / "MacOS"
    resources = dest / "Contents" / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    plist = repo / "Resources" / "Info.plist"
    if not plist.is_file():
        raise Refused("Resources/Info.plist is missing")
    shutil.copy2(plist, dest / "Contents" / "Info.plist")
    shutil.copy2(exe, macos / "Zeus")
    os.chmod(macos / "Zeus", 0o755)
    for name in (
        "AppIcon.icns", "Logo.png", "Logo.pdf", "MenuBarTemplate.png",
        "MenuBarTemplate@2x.png", "NOTICES.txt",
    ):
        src = repo / "Resources" / name
        if src.is_file() and not src.is_symlink():
            shutil.copy2(src, resources / name)
    helpers = dest / "Contents" / "Helpers"
    for src_name, dest_name in (("zeus-hook", "zeus-hook"), ("zeus-bridge", "zeus-bridge"), ("zeus-cli", "zeus")):
        src = Path(bin_dir) / src_name
        if src.is_file() and not src.is_symlink():
            helpers.mkdir(exist_ok=True)
            shutil.copy2(src, helpers / dest_name)
            os.chmod(helpers / dest_name, 0o755)
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(dest)], check=True)


def capture_runtime(dest, listing):
    """Return the pid and bundle of a process already running from dest.

    This does not start a process. /Applications/Zeus.app is refused.
    """
    dest = Path(dest)
    refuse_if_installed(dest)
    if dest == Path(INSTALLED) or dest.resolve() == Path(INSTALLED):
        raise Refused("refusing to build over /Applications/Zeus.app")
    wanted = str(dest)
    for row in listing:
        if not isinstance(row, dict):
            continue
        bundle = row.get("bundle")
        pid = row.get("pid")
        if bundle != wanted:
            continue
        if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
            continue
        if Path(bundle) == Path(INSTALLED):
            continue
        return {"pid": pid, "bundle": wanted}
    return None


def live_processes():
    """Processes whose command line is a Zeus.app binary. Does not start one."""
    if platform.system() != "Darwin":
        return []
    try:
        output = subprocess.check_output(["ps", "-ax", "-o", "pid=,command="], text=True)
    except (OSError, subprocess.CalledProcessError):
        return []
    rows = []
    needle = ".app/Contents/MacOS/Zeus"
    for line in output.splitlines():
        text = line.strip()
        marker = text.find(needle)
        if marker < 0:
            continue
        pid_text, _, _command = text.partition(" ")
        try:
            pid = int(pid_text)
        except ValueError:
            continue
        head = text[:marker]
        space = head.rfind(" ")
        bundle = head[space + 1:] + ".app"
        if bundle == INSTALLED:
            continue
        rows.append({"pid": pid, "bundle": bundle})
    return rows


def record_manual_run(receipt, dest, captured):
    """Write a FAIL receipt. The manual steps are not a pass yet."""
    dest = Path(dest)
    refuse_if_installed(dest)
    if dest == Path(INSTALLED) or str(dest) == INSTALLED:
        raise Refused("refusing to build over /Applications/Zeus.app")
    body = json.loads(json.dumps(receipt))
    body["manual_run"] = True
    body["opened_by_harness"] = False
    body["verdict"] = "FAIL"
    body["runtime_app_pid"] = None
    body["runtime_app_bundle"] = None
    if captured and captured.get("bundle") == str(dest) and Path(captured["bundle"]) != Path(INSTALLED):
        pid = captured.get("pid")
        if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0:
            body["runtime_app_pid"] = pid
        executable = dest / "Contents" / "MacOS" / "Zeus"
        if executable.is_file() and not executable.is_symlink() and not dest.is_symlink():
            body["runtime_app_bundle"] = str(dest)
    out = dest.parent / f"{dest.stem}.qa-receipt.json"
    out.write_text(json.dumps(body, indent=2) + "\n")
    return str(out), 2


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="manual-run harness. It does not open Zeus. Builds only the Desktop app."
    )
    parser.add_argument("--repo", required=True)
    parser.add_argument("--home", default=str(Path.home()))
    parser.add_argument("--head", help="40 lowercase hex characters; default is git rev-parse HEAD")
    args = parser.parse_args(argv)
    repo = Path(args.repo)
    head = args.head
    if not head:
        head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    try:
        receipt = prepare(
            head, Path(args.home), repo, shutil.disk_usage, _run, platform.system(), real_assemble
        )
        dest = Path(receipt["app"])
        refuse_if_installed(dest)
        if str(dest) == INSTALLED:
            raise Refused("refusing to build over /Applications/Zeus.app")
        captured = capture_runtime(dest, live_processes())
        out, code = record_manual_run(receipt, dest, captured)
    except Refused as error:
        print(f"qa-native-run: {error}", file=sys.stderr)
        return 2
    print(out)
    print("manual-run harness: Zeus was not opened. Open the Desktop build yourself.")
    print("/Applications/Zeus.app is never launched. This receipt is marked FAIL.")
    return code


if __name__ == "__main__":
    sys.exit(main())
