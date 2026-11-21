"""Z5 gap: a DEBUG-only loopback override, off unless the sentinel is set.

The behaviour test compiles an isolated package. That package is not the app
manifest: production Package.swift stays untouched, and Linux cannot build the
Zeus executable.
"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "Sources/Zeus/Brain/Providers/OpenAICompatProvider.swift"
BEHAVIOUR = ROOT / "Tests/ZeusAppTests/ProviderEndpointOverrideTests.swift"

PACKAGE = """// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ProviderEndpointOverride",
    targets: [
        .target(name: "Zeus"),
        .testTarget(name: "ZeusAppTests", dependencies: ["Zeus"]),
    ]
)
"""


def function_body(text, func_at):
    brace = text.index("{", func_at)
    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:index]
    raise AssertionError("resolved has no closing brace")


def extract_override(text):
    """The override type, plus the #if DEBUG that wraps it when the type is conditional."""
    enum_at = text.index("enum ProviderEndpointOverride")
    line_start = text.rfind("\n", 0, enum_at) + 1
    prefix = text[:line_start].splitlines(keepends=True)
    cursor = len(prefix)
    while cursor > 0:
        stripped = prefix[cursor - 1].strip()
        if stripped == "" or stripped.startswith("//"):
            cursor -= 1
            continue
        break
    if cursor > 0 and prefix[cursor - 1].strip() == "#if DEBUG":
        start = sum(len(line) for line in prefix[: cursor - 1])
        wrapped = True
    else:
        start = line_start
        wrapped = False
    brace = text.index("{", start)
    depth = 0
    end = None
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    if end is None:
        raise AssertionError("ProviderEndpointOverride has no closing brace")
    body = text[start:end]
    if wrapped:
        rest = text[end:]
        marker = rest.find("#endif")
        if marker < 0 or rest[:marker].strip() != "":
            raise AssertionError("the #if DEBUG around ProviderEndpointOverride has no #endif")
        body = text[start:end + marker + len("#endif")]
    return "import Foundation\n\n" + body.strip() + "\n"


class ProviderStubOverride(unittest.TestCase):
    def test_debug_stub_is_opt_in_and_loopback_only(self):
        text = SOURCE.read_text(encoding="utf-8")
        self.assertIn("#if DEBUG", text)
        self.assertIn("ZEUS_DEBUG_PROVIDER_STUB", text)
        self.assertIn("ZEUS_DEBUG_PROVIDER_BASE_URL", text)
        self.assertIn('url.host == "127.0.0.1"', text)
        self.assertIn("ProviderEndpointOverride.resolved", text)

    def test_debug_wraps_the_type_and_the_call_sites(self):
        text = SOURCE.read_text(encoding="utf-8")
        enum_at = text.index("enum ProviderEndpointOverride")
        self.assertIn("#if DEBUG", text[:enum_at])
        body = function_body(text, text.index("func resolved", enum_at))
        self.assertNotIn("#if", body)
        self.assertNotIn("#else", body)
        self.assertNotIn("#endif", body)
        for snippet in (
            "ProviderEndpointOverride.resolved(production: production, key: nil)",
            "ProviderEndpointOverride.resolved(production: production, key: key)",
        ):
            at = text.index(snippet)
            window = text[max(0, at - 200):at]
            self.assertGreater(window.rfind("#if DEBUG"), window.rfind("#endif"))

    def test_override_applies_only_when_no_key_is_set(self):
        swift = shutil.which("swift")
        self.assertIsNotNone(swift, "swift is required to execute the override behaviour test")
        excerpt = extract_override(SOURCE.read_text(encoding="utf-8"))
        root = Path(tempfile.mkdtemp(prefix="zeus-provider-override-"))
        try:
            (root / "Sources" / "Zeus").mkdir(parents=True)
            (root / "Tests" / "ZeusAppTests").mkdir(parents=True)
            (root / "Package.swift").write_text(PACKAGE, encoding="utf-8")
            (root / "Sources" / "Zeus" / "ProviderEndpointOverride.swift").write_text(excerpt, encoding="utf-8")
            destination = root / "Tests" / "ZeusAppTests" / "ProviderEndpointOverrideTests.swift"
            destination.write_text(BEHAVIOUR.read_text(encoding="utf-8"), encoding="utf-8")
            result = subprocess.run(
                [swift, "test", "--package-path", str(root)],
                text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + "\n" + result.stderr)
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)

