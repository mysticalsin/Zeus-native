"""Package the compiled, test-only AppKit host without installing or launching Zeus."""
import os
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

from contracts import ROOT, digest, require

SUITES = {"OwnedWindowEventDriverTests", "ScribeComponentJourneyTests", "ScribeAccessibilityJourneyTests",
          "OnboardingComponentJourneyTests", "OnboardingFilmLifecycleTests",
          "ExplanationRendererTests", "ExplanationTalkButtonTests", "ExplanationScreenContextTests",
          "ExplanationChatLifecycleTests", "ScribeTrustedAccessibilityJourneyTests"}
# Launchable by the host, but only by the local trusted runner. `selected` never picks these for CI.
TRUSTED_SUITES = {"ScribeTrustedAccessibilityJourneyTests"}
INFO = {
    "CFBundleExecutable": "zeus-native-test-host",
    "CFBundleIdentifier": "org.zeus.native-test-host",
    "CFBundleName": "Zeus Native Test Host",
    "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1",
    "NSPrincipalClass": "NSApplication",
    "NSHighResolutionCapable": True,
}


def selected(definitions):
    hosted = [row for row in definitions if row.get("kind") == "native-fixture" and row.get("suite") in SUITES - TRUSTED_SUITES]
    require(not hosted or len(definitions) == 1, "AppKit journeys require their own host process")
    return bool(hosted)


def executable(output_directory, ident):
    return Path(output_directory) / ident / "native-artifacts/test-host/ZeusNativeTestHost.app/Contents/MacOS/zeus-native-test-host"


def bundle_binary(repo):
    return Path(repo) / ".build/debug/ZeusPackageTests.xctest/Contents/MacOS/ZeusPackageTests"


def inputs_path(output_directory, ident):
    return Path(output_directory) / ident / "native-artifacts/test-host/inputs.json"


def runtime_configuration():
    """Record the actual selected platform and loader paths used by this host."""
    result = subprocess.run(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"],
                            capture_output=True, text=True, check=True, timeout=10)
    platform = Path(result.stdout.strip())
    require(platform.is_absolute() and platform.is_dir(), "selected Xcode platform is unavailable")
    frameworks = [platform / "Developer/Library/Frameworks", platform / "Developer/Library/PrivateFrameworks"]
    libraries = [platform / "Developer/usr/lib"]
    require(all(path.is_dir() for path in frameworks + libraries), "selected Xcode test runtime is incomplete")
    environment = {key: ":".join([*(str(path) for path in paths), *([os.environ[key]] if os.environ.get(key) else [])])
                   for key, paths in (("DYLD_FRAMEWORK_PATH", frameworks), ("DYLD_LIBRARY_PATH", libraries))}
    return {"platform": str(platform), "environment": environment}


def input_provenance(repo, runtime):
    tests = bundle_binary(repo)
    require(tests.is_file() and os.access(tests, os.X_OK)
            and tests.resolve().is_relative_to((Path(repo) / ".build").resolve()),
            "compiled native test bundle is missing or redirected")
    return {"schema_version": 1,
            "test_bundle": {"path": str(tests), "resolved_path": str(tests.resolve()),
                            "sha256": digest(tests.read_bytes())},
            "selected_platform": runtime["platform"]}


def prepare(output_directory, ident, repo=ROOT):
    repo = Path(repo)
    built = repo / ".build/debug/zeus-native-test-host"
    tests = bundle_binary(repo)
    for binary in (built, tests):
        require(binary.is_file() and os.access(binary, os.X_OK)
                and binary.resolve().is_relative_to((repo / ".build").resolve()),
                "compiled native AppKit host or test bundle is missing or redirected")
    target = executable(output_directory, ident)
    target.parent.mkdir(parents=True, exist_ok=False)
    shutil.copy2(built, target)
    (target.parent.parent / "Info.plist").write_bytes(plistlib.dumps(INFO))
    # Prefer the selected macOS platform runtime paths to ambient overrides.
    # The host imports no Testing library; the test bundle loads its own.
    runtime = runtime_configuration()
    inputs_path(output_directory, ident).write_text(json.dumps(input_provenance(repo, runtime), indent=2) + "\n")
    return runtime["environment"]


def validate_artifacts(files, ident):
    binary = str(executable("/", ident).relative_to("/"))
    info = str(Path(binary).parent.parent / "Info.plist")
    require(binary in files and info in files and files[binary].stat().st_size > 0,
            "native AppKit host artifacts are missing")
    try:
        metadata = plistlib.loads(files[info].read_bytes())
    except (ValueError, plistlib.InvalidFileException) as error:
        raise ValueError("native AppKit host metadata is invalid") from error
    require(metadata == INFO, "native AppKit host metadata changed")
