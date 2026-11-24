#!/usr/bin/env python3
"""Isolated Linux package for the pointing proposal gate.

Copies the gate, the drive risk model, and the synthetic fixture into a new
directory and runs `swift test` there. It does not edit qa/portable-core/prepare.py,
qa/feature-map.json, or qa/regressions.json, and it does not build the macOS app.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCES = [
    "Sources/ZeusCore/Pointing/PointingProposal.swift",
    "Sources/ZeusCore/Mac/DrivePlan.swift",
    "Sources/ZeusCore/Mac/AXSnapshot.swift",
    "Sources/ZeusCore/Mac/MacActionNumbers.swift",
    "Sources/ZeusCore/JSONValue.swift",
]
TESTS = [
    "Tests/ZeusCoreTests/PointingProposalValidationTests.swift",
]
FIXTURE = "Tests/ZeusCoreTests/Fixtures/pointing-proposal.json"


def package_manifest(linux: bool) -> str:
    shim = ""
    dependency = "[]"
    if linux:
        shim = '        .target(name: "CoreGraphics"),\n'
        dependency = '["CoreGraphics"]'
    return f"""// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PointingProposal",
    platforms: [.macOS("14.2")],
    targets: [
{shim}        .target(name: "ZeusCore", dependencies: {dependency}),
        .testTarget(name: "ZeusCoreTests", dependencies: ["ZeusCore"], resources: [
            .copy("Fixtures"),
        ]),
    ]
)
"""


def prepare(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=False)
    linux = sys.platform.startswith("linux")
    (output / "Package.swift").write_text(package_manifest(linux))
    if linux:
        shim = output / "Sources/CoreGraphics/FoundationGeometry.swift"
        shim.parent.mkdir(parents=True)
        shim.write_text("@_exported import Foundation\n")
    for relative in SOURCES:
        destination = output / "Sources/ZeusCore" / Path(relative).name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / relative, destination)
    for relative in TESTS:
        destination = output / "Tests/ZeusCoreTests" / Path(relative).name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / relative, destination)
    fixture = output / "Tests/ZeusCoreTests/Fixtures/pointing-proposal.json"
    fixture.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(REPO / FIXTURE, fixture)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New output directory. Existing paths are left untouched.")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    swift = shutil.which("swift")
    if swift is None:
        sys.exit("swift is not on PATH")
    if args.output:
        output = args.output.expanduser().resolve()
    else:
        output = Path(tempfile.mkdtemp(prefix="zeus-pointing-proposal-"))
    prepare(output)
    command = [
        swift, "test", "--package-path", str(output), "--jobs", str(args.jobs),
        "--filter", "PointingProposalValidationTests",
        "--xunit-output", str(output / "results.xml"),
    ]
    log = output / "test.log"
    print(f"Prepared {output}", flush=True)
    with log.open("w") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=False)
    print(f"exit {result.returncode}; {log}", flush=True)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
