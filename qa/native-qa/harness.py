"""Build Zeus on the Desktop and write an empty hands-on QA receipt.

The build destination is ~/Desktop/Zeus-latest-<sha8>.app. This file refuses
/Applications/Zeus.app. It does not install the app and it does not start
microphone, screen, or audio capture. The receipt stays not-run until a person
fills every screenshot and result slot.
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


def _run(command):
    subprocess.run(command, check=True)


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


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build the Desktop app and write an empty QA receipt.")
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
        out = dest.parent / f"{dest.stem}.qa-receipt.json"
        out.write_text(json.dumps(receipt, indent=2) + "\n")
    except Refused as error:
        print(f"qa-native-run: {error}", file=sys.stderr)
        return 2
    print(out)
    print("not a pass: fill every screenshot and result, then run scripts/qa-native-validate.sh")
    return 2


if __name__ == "__main__":
    sys.exit(main())
