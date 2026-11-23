"""manual-run harness for the Desktop build of Zeus.

It builds only ~/Desktop/Zeus-latest-<sha8>.app. It does not open Zeus and it
never launches /Applications/Zeus.app. A person opens the Desktop build. The
harness records a pid or bundle path only when that running app is observed.
A failed run writes a receipt marked FAIL, which cannot validate.
On any other host it does not build. It writes a receipt that marks every
Mac hands-on journey unproven, and that receipt cannot validate.
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
    return subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)


def _command_log(command, completed):
    stdout = getattr(completed, "stdout", None) or getattr(completed, "output", None) or ""
    stderr = getattr(completed, "stderr", None) or ""
    text = "$ " + " ".join(str(part) for part in command) + "\n" + stdout + stderr
    if text and not text.endswith("\n"):
        text += "\n"
    return text


def _note(log, command, text):
    if log is None:
        return
    body = text or ""
    line = "$ " + " ".join(str(part) for part in command) + "\n" + body
    if not line.endswith("\n"):
        line += "\n"
    log.append(line)


def real_assemble(repo, dest, bin_dir=None, log=None):
    """Copy the release binary into the Desktop app. Ad hoc signature only."""
    refuse_if_installed(dest)
    dest = Path(dest)
    if str(dest) == INSTALLED or dest == Path(INSTALLED):
        raise Refused("refusing to build over /Applications/Zeus.app")
    if dest.parent.name != "Desktop" or not dest.name.startswith("Zeus-latest-") or not dest.name.endswith(".app"):
        raise Refused("builds go only to ~/Desktop/Zeus-latest-<sha8>.app")
    repo = Path(repo)
    if bin_dir is None:
        command = ["swift", "build", "-c", "release", "--show-bin-path"]
        try:
            bin_dir = subprocess.check_output(command, cwd=repo, text=True).strip()
        except subprocess.CalledProcessError as error:
            _note(log, command, (error.output or "") + (error.stderr or ""))
            raise
        _note(log, command, bin_dir)
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
    command = ["codesign", "--force", "--sign", "-", "--timestamp=none", str(dest)]
    try:
        completed = subprocess.run(command, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as error:
        _note(log, command, (error.stdout or "") + (error.stderr or ""))
        raise
    _note(log, command, (completed.stdout or "") + (completed.stderr or ""))


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


def record_manual_run(receipt, dest, captured, path=None):
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
    out = Path(path) if path is not None else dest.parent / f"{dest.stem}.qa-receipt.json"
    if out.is_symlink():
        raise Refused("refusing to write a receipt through a symlink")
    out.write_text(json.dumps(body, indent=2) + "\n")
    return str(out), 2


def _ci_build():
    """True when this process is a CI job. The value is only read, never set."""
    return bool(os.environ.get("GITHUB_ACTIONS") or os.environ.get("CI"))


def _receipt_path(dest, receipt_path, repo):
    path = Path(receipt_path) if receipt_path else dest.parent / f"{dest.stem}.qa-receipt.json"
    if path.is_symlink() or path.parent.is_symlink() or not path.parent.is_dir():
        raise Refused(f"{path.parent} is not a directory")
    installed = Path(INSTALLED)
    if path == installed or path.resolve() == installed or installed in path.resolve().parents:
        raise Refused("refusing to build over /Applications/Zeus.app")
    resolved = path.resolve()
    root = Path(repo).resolve()
    if resolved == root or root in resolved.parents:
        raise Refused("refusing to write the receipt inside the repository")
    return path


def _write_unproven(head, dest, platform_name, path):
    receipt = _validate.unproven_receipt(head, str(dest), platform_name)
    path.write_text(json.dumps(receipt, indent=2) + "\n")
    return str(path), 2


def _fail_receipt(head, dest, log, error, path):
    receipt = _validate.blank_receipt(head, str(dest))
    receipt["platform"] = "Darwin"
    text = "".join(log)
    if not text:
        text = f"{error}\n"
    if not text.endswith("\n"):
        text += "\n"
    receipt["log"] = text
    return record_manual_run(receipt, dest, None, path)


def execute(repo, home, head, platform_name, receipt_path=None, usage=None, run=None, assemble=None, processes=None):
    """Build on macOS, or write an unproven receipt on any other host.

    The return is (receipt path, exit code). Exit code 0 is never used: the
    harness does not perform the hands-on steps, so it cannot pass them.
    """
    repo = Path(repo)
    home = Path(home)
    if not head:
        head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    dest = _validate.desktop_app(home, head)
    path = _receipt_path(dest, receipt_path, repo)
    if platform_name != "Darwin":
        return _write_unproven(head, dest, platform_name, path)
    if _ci_build():
        raise Refused("refusing to build in CI")
    log = []

    def logging_run(command, cwd=None):
        runner = run or _run
        try:
            completed = runner(command, cwd=cwd)
        except subprocess.CalledProcessError as error:
            log.append(_command_log(command, error))
            raise
        if completed is None:
            completed = subprocess.CompletedProcess(command, 0, stdout="", stderr="")
        log.append(_command_log(command, completed))
        return completed

    def logging_assemble(repo_path, dest_path):
        real_assemble(repo_path, dest_path, log=log)

    try:
        receipt = prepare(
            head, home, repo,
            usage if usage is not None else shutil.disk_usage,
            logging_run, platform_name,
            assemble if assemble is not None else logging_assemble,
        )
    except (subprocess.CalledProcessError, OSError) as error:
        return _fail_receipt(head, dest, log, error, path)
    receipt["platform"] = "Darwin"
    text = "".join(log)
    if not text.endswith("\n"):
        text = text + "\n" if text else "swift build -c release\n"
    receipt["log"] = text
    listing = live_processes() if processes is None else processes
    captured = capture_runtime(dest, listing)
    return record_manual_run(receipt, dest, captured, path)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="manual-run harness. It does not open Zeus. Builds only the Desktop app."
    )
    parser.add_argument("--repo", required=True)
    parser.add_argument("--home", default=str(Path.home()))
    parser.add_argument("--head", help="40 lowercase hex characters; default is git rev-parse HEAD")
    parser.add_argument("--receipt", help="receipt JSON path; default sits beside the Desktop build")
    args = parser.parse_args(argv)
    repo = Path(args.repo)
    head = args.head
    if not head:
        head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    try:
        out, code = execute(repo, Path(args.home), head, platform.system(), receipt_path=args.receipt)
    except Refused as error:
        print(f"qa-native-run: {error}", file=sys.stderr)
        return 2
    print(out)
    if platform.system() == "Darwin":
        print("manual-run harness: Zeus was not opened. Open the Desktop build yourself.")
        print("/Applications/Zeus.app is never launched. This receipt is marked FAIL.")
    else:
        print("unproven: macOS hands-on journeys were not run.")
    return code


if __name__ == "__main__":
    sys.exit(main())
