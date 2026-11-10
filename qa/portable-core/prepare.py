#!/usr/bin/env python3
"""Snapshot selected real Zeus sources into isolated Swift 6 validation packages.

This is a synthetic test harness, not a Linux port or a native macOS build.
The production Package.swift and source files are never changed.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile


REPO = Path(__file__).resolve().parents[2]
CORE = "Sources/ZeusCore/"
TESTS = "Tests/ZeusCoreTests/"


def core(*paths):
    return [CORE + path for path in paths]


def tests(*names):
    return [TESTS + name + ".swift" for name in names]


GROUPS = {
    "wiki-export": (
        core("MeetingCopilot.swift", "Scribe/ScribeCapture.swift", "Scribe/ScribeNotes.swift", "Scribe/ScribeTranscript.swift",
             "Wiki/WikiPage.swift", "Wiki/WikiCompiler.swift", "Wiki/SensitiveInfoScanner.swift",
             "Wiki/WikiExportModels.swift", "Wiki/WikiExportVault.swift", "Wiki/WikiExportMCP.swift",
             "Wiki/WikiExportJournal.swift", "Wiki/WikiExportTransaction.swift",
             "SecondBrain/SecondBrain.swift", "SecondBrain/VaultPathBoundary.swift", "JSONValue.swift",
             "BrowserAgent/BrowserUseProtocol.swift"),
        tests("WikiExportTests"),
    ),
    "dictation-insertion": (
        core("Dictation/TextInsertionReceipt.swift"),
        tests("TextInsertionReceiptTests"),
    ),
    "polyglot": (
        core("Polyglot/PolyglotModels.swift", "Polyglot/PolyglotPipeline.swift", "Polyglot/PolyglotSegmenter.swift"),
        tests("PolyglotTests", "PolyglotTargetChangeTests", "W7PolyglotTests"),
    ),
    "regressions": (
        core("Dictation/DictationCore.swift", "Dictation/SpeechEngineCatalog.swift",
             "Dictation/SpokenDictationMarkup.swift", "Dictation/TranscriptionEngine.swift", "Dictation/WhisperPromptRecovery.swift",
             "Dictation/ThinkingOrbMath.swift", "Voice/UltronVoiceSignal.swift", "Recordly/RecordlyCaptureTimeline.swift", "Mac/DriveTypingFlow.swift"),
        tests("DictationExplicitCorrectionTests", "DictationQAFixTests", "SpeechEngineCatalogTests",
              "UltronVoiceSignalTests", "RecordlyCaptureTimelineTests", "DriveTypingFlowTests", "WhisperPromptRecoveryTests", "ThinkingOrbMathTests"),
    ),
    "scribe": (
        core("MeetingCopilot.swift", "TopBar/RecordingMotion.swift", "TopBar/RecordingFeedback.swift", "Scribe/ScribeCallPrompt.swift",
             "Scribe/ScribeCapture.swift", "Scribe/ScribeMicGate.swift", "Scribe/ScribeNotes.swift",
             "Scribe/ScribePresentation.swift", "Scribe/ScribeSession.swift", "Scribe/ScribeSpeakerStats.swift",
             "Scribe/ScribeTranscript.swift", "Scribe/ScribeMicrophoneIngress.swift", "Scribe/ScribeEndWorkflow.swift"),
        tests("ScribeCoreTests", "ScribePresentationTests", "W7ScribeTests", "W8ScribeLookTests", "RecordingMotionTests", "ScribeCompletionTests",
              "ScribeMicrophoneIngressTests", "ScribeEndWorkflowTests", "RecordingFeedbackTests"),
    ),
    "presentation": (
        core("JSONValue.swift", "Mac/Walkthrough.swift", "Mac/MacActionNumbers.swift", "Mac/DrivePlan.swift",
             "Present/SpeechTimeline.swift"),
        tests("WalkthroughRevisionTests", "SpeechTimelineTests", "MacActionNumberTests"),
    ),
    "recordly-geometry": (
        core("BuddyVisibility.swift", "Recordly/RecordlyCursorFollowPath.swift", "Recordly/RecordlyCursorSmoother.swift",
             "Recordly/RecordlyCursorLog.swift", "Recordly/RecordlyZoomRegions.swift", "Recordly/RecordlyExportPlan.swift",
             "Recordly/RecordlyExportSettings.swift"),
        tests("RecordlyCursorFollowTests", "RecordlyExportPlanTests"),
    ),
    "buddy": (
        core("BuddyVisibility.swift", "Present/CompanionPointing.swift", "Present/CompanionMotion.swift", "Present/CoordinateMapper.swift"),
        tests("CompanionPointingTests", "CompanionMotionTests"),
    ),
    "wiki-relationships": (
        core("MeetingCopilot.swift", "Scribe/ScribeCapture.swift", "Scribe/ScribeNotes.swift",
             "Scribe/ScribeTranscript.swift", "Scribe/ScribeSession.swift", "Scribe/ScribeRecapNavigation.swift",
             "Wiki/WikiPage.swift", "Wiki/WikiCompiler.swift", "Wiki/SensitiveInfoScanner.swift", "Wiki/WikiRelationships.swift"),
        tests("WikiRelationshipsTests", "ScribeRecapNavigationTests"),
    ),
    # Optional: the Linux Foundation replaceItemAt limitation affects persistence tests here.
    "wiki": (
        core("MeetingCopilot.swift", "ZeusPaths.swift", "Scribe/ScribeCapture.swift", "Scribe/ScribeNotes.swift",
             "Scribe/ScribeTranscript.swift", "Wiki/WikiPage.swift", "Wiki/WikiCompiler.swift",
             "Wiki/WikiStore.swift", "Wiki/SensitiveInfoScanner.swift"),
        tests("WikiTests"),
    ),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def section(path, start, end=None):
    """Copy exact declaration bytes; fail visibly if a boundary becomes ambiguous."""
    data = (REPO / path).read_bytes()
    text = data.decode("utf-8")
    if text.count(start) != 1 or (end is not None and text.count(end) != 1):
        raise ValueError(f"Extraction boundary missing or ambiguous in {path}")
    first = text.index(start)
    last = text.index(end, first) if end else len(text)
    content = text[first:last]
    evidence = {"source": path, "source_sha256": digest(data), "start": start,
                "end_exclusive": end or "EOF", "excerpt_sha256": digest(content.encode())}
    return content, evidence


def write_excerpts(root, group, manifest):
    pieces = []
    if group == "scribe":
        path = CORE + "Scribe/ScribeLiveLogic.swift"
        for start, end in [
            ("public enum ScribeAudioMath {", "// MARK: - Streaming resampler"),
            ("// MARK: - Call-app identification", "// MARK: - Recap notes, cloud disclosure, system-audio stall"),
            ("// MARK: - Mute evidence (fail closed)", "// MARK: - Mute evidence timeline"),
        ]:
            text, evidence = section(path, start, end)
            pieces.append(text)
            manifest["excerpts"].append(evidence)
        text, evidence = section(TESTS + "ScribeLiveLogicTests.swift",
                                 "    @Test func freshEvidenceIsServedAndExpiredEvidenceIsUnknown()",
                                 "    // MARK: Evidence coverage")
        manifest["excerpts"].append(evidence)
        (root / TESTS / "PortableMuteTests.swift").write_text(
            'import Foundation\nimport Testing\n@testable import ZeusCore\n'
            '@Suite("Scribe mute portable excerpts")\nstruct PortableMuteTests {\n' + text + "\n}\n")
    elif group in ("wiki", "wiki-relationships", "wiki-export"):
        text, evidence = section(CORE + "Scribe/ScribeLiveLogic.swift", "public struct ScribeMeetingRecord:",
                                 "public enum ScribeMeetingStoreError:")
        pieces.append(text)
        manifest["excerpts"].append(evidence)
        if group == "wiki-export":
            text, evidence = section(CORE + "Research/ResearchReport.swift", '    public static let vaultFolder = "ZEUS/Research"',
                                    '    /// Where the report goes:')
            pieces.append("public enum ResearchReport {\n" + text + "\n}")
            manifest["excerpts"].append(evidence)
            text, evidence = section("Sources/Zeus/Wiki/WikiMCPExport.swift",
                                     "extension MCPStdioClient: WikiExportToolClient {", "/// One user-opened selection/review transaction.")
            target = root / "Sources/MCPTransportValidation/MemoryMCPConformance.swift"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("import Foundation\nimport ZeusCore\n" + text)
            manifest["excerpts"].append(evidence)
    elif group == "presentation":
        for path, start, end in [
            (CORE + "ZeusTag.swift", "public struct PointTarget:", "public struct HighlightTarget:"),
            (CORE + "Present/DrawingScene.swift", "public struct MathLayout:", None),
            (CORE + "Mac/AXSnapshot.swift", "public struct AXRef:", "/// What the frontmost window looked like"),
        ]:
            text, evidence = section(path, start, end)
            pieces.append(text)
            manifest["excerpts"].append(evidence)
    elif group == "recordly-geometry":
        text, evidence = section(CORE + "Present/CompanionMotion.swift", "public struct CompanionSpring:",
                                 "/// One frame of a flight.")
        pieces.append(text)
        manifest["excerpts"].append(evidence)
    if pieces:
        (root / CORE / "PortableExcerpts.swift").write_text("import Foundation\n\n" + "\n".join(pieces))


def prepare(output, group, *, platform_name=None):
    platform_name = platform_name or ("linux" if sys.platform.startswith("linux") else sys.platform)
    if platform_name not in {"linux", "darwin"}:
        raise ValueError("Portable recipe supports only linux or darwin")
    root = output / group
    (root / CORE).mkdir(parents=True)
    (root / TESTS).mkdir(parents=True)
    manifest = {"group": group, "repository": str(REPO), "platform": platform_name, "scope": "Synthetic portable subset; no native app validation",
                "files": [], "excerpts": []}
    for source in sum(GROUPS[group], []):
        data = (REPO / source).read_bytes()
        target = root / source
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest["files"].append({"source": source, "sha256": digest(data)})
    write_excerpts(root, group, manifest)
    compatibility = group in ("recordly-geometry", "buddy") and platform_name == "linux"
    extra_target = ''
    core_dependencies = '[]'
    test_dependencies = '["ZeusCore"]'
    test_settings = ''
    if group == "wiki-export":
        wrapper = root / "Sources/zeus-memory-helper/main.swift"
        wrapper.parent.mkdir(parents=True)
        wrapper.write_text('import Foundation\nimport ZeusCore\nexit(WikiExportMCPCommand.run(Array(CommandLine.arguments.dropFirst())))\n')
        extra_target = ('    .executableTarget(name: "zeus-memory-helper", dependencies: ["ZeusCore"]),\n'
                        '    .target(name: "MCPTransportValidation", dependencies: ["ZeusCore"]),\n')
        for source, target in [
            ("Sources/Zeus/BrowserAgent/MCPStdioClient.swift", "Sources/MCPTransportValidation/MCPStdioClient.swift"),
            ("Tests/ZeusAppTests/MemoryMCPTransportTests.swift", TESTS + "MemoryMCPTransportTests.swift"),
        ]:
            data = (REPO / source).read_bytes()
            destination = root / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            manifest["files"].append({"source": source, "sha256": digest(data), "target": target})
        test_dependencies = '["ZeusCore", "MCPTransportValidation"]'
        test_settings = ', swiftSettings: [.define("ZEUS_PORTABLE_MCP")]'
        manifest["executable_wrapper"] = "Exact production WikiExportMCPCommand.run; wrapper only forwards arguments. No app control, capture or vault discovery."
    if compatibility:
        # Linux Foundation exports these value types; this supplies the import name only.
        # It supplies no capture, drawing, coordinate conversion, or business implementation.
        shim = root / "Sources/CoreGraphics/FoundationGeometry.swift"
        shim.parent.mkdir(parents=True)
        shim.write_text("@_exported import Foundation\n")
        manifest["compatibility"] = "Linux-only CoreGraphics module reexports Foundation geometry value types. Not Apple CoreGraphics validation."
        extra_target = '    .target(name: "CoreGraphics"),\n'
        core_dependencies = '["CoreGraphics"]'
    (root / "Package.swift").write_text(
        '// swift-tools-version: 6.0\nimport PackageDescription\n'
        'let package = Package(name: "ZeusPortableValidation", targets: [\n'
        + extra_target + f'    .target(name: "ZeusCore", dependencies: {core_dependencies}),\n'
        +
        f'    .testTarget(name: "ZeusCoreTests", dependencies: {test_dependencies}{test_settings})\n])\n')
    (root / "validation-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", action="append", choices=GROUPS,
                        help="Repeat to select groups. Default: all except wiki.")
    parser.add_argument("--output", type=Path, help="New output directory; existing paths are never overwritten.")
    parser.add_argument("--run", action="store_true", help="Run swift test in each generated package and retain logs.")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if args.output:
        output = args.output.expanduser().absolute()
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix="zeus-portable-"))
    groups = list(dict.fromkeys(args.group or [name for name in GROUPS if name != "wiki"]))
    results = []
    for group in groups:
        root = prepare(output, group)
        print(f"Prepared {group}: {root}", flush=True)
        if args.run:
            command = ["swift", "test", "--package-path", str(root), "--jobs", str(args.jobs)]
            log = root / "test.log"
            with log.open("w") as stream:
                result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=False)
            row = {"group": group, "command": command, "exit_code": result.returncode, "log": str(log)}
            summaries = re.findall(r"Test run with (\d+) tests? in (\d+) suites? (passed|failed)", log.read_text())
            if summaries:
                count, suites, status = summaries[-1]
                row.update(tests=int(count), suites=int(suites), test_summary=status)
            results.append(row)
            print(f"{group}: exit {result.returncode}; {log}", flush=True)
    if results:
        (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    raise SystemExit(1 if any(row["exit_code"] for row in results) else 0)


if __name__ == "__main__":
    main()
