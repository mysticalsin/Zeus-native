"""Documented commands must resolve, and the docs that name a runtime directory must match the script."""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
DOCS = [ROOT / "docs", ROOT / "qa"]
PLACEHOLDER = re.compile(r"<([A-Za-z][^>\n]*)>")
DEFINITION = re.compile(r"`<([^>]+)>` is `")
FENCE = re.compile(r"```([^\n]*)\n(.*?)```", re.S)
COMMAND = re.compile(r"\b(?:python3|swift|bash|sh|zsh|xcrun|open|killall|ditto)\b|(?:^|[\s;])(?:\./|scripts/)")


def markdown_files():
    found = []
    for root in DOCS:
        found.extend(path for path in root.rglob("*.md") if "receipts" not in path.parts)
    return found


def commands(text):
    """Shell fences, plus inline code paired outside those fences so a fence cannot shift the pairs."""
    spans = []
    masked = list(text)
    for match in FENCE.finditer(text):
        lang = match.group(1).strip().split()[:1]
        lang = lang[0].lower() if lang else ""
        body = match.group(2)
        if lang in {"sh", "bash", "shell", "console", "zsh"}:
            spans.append((match.start(2), body))
        for index in range(match.start(), match.end()):
            masked[index] = " "
    plain = "".join(masked)
    cursor = 0
    while True:
        start = plain.find("`", cursor)
        if start < 0:
            break
        end = plain.find("`", start + 1)
        if end < 0:
            break
        body = plain[start + 1:end]
        if body.strip() and COMMAND.search(body):
            spans.append((start + 1, body))
        cursor = end + 1
    return spans


def unquoted(command):
    stripped = re.sub(r'"(?:\\.|[^"\\])*"', '""', command)
    stripped = re.sub(r"'(?:\\.|[^'\\])*'", "''", stripped)
    return PLACEHOLDER.findall(stripped)


def undefined_placeholders(text):
    problems = []
    defined_at = [(match.start(), match.group(1)) for match in DEFINITION.finditer(text)]
    for start, command in commands(text):
        known = {name for pos, name in defined_at if pos < start}
        for name in PLACEHOLDER.findall(command):
            if name not in known:
                problems.append(f"undefined <{name}> in command: {command.strip()[:120]}")
        for name in unquoted(command):
            problems.append(f"unquoted <{name}> redirects: {command.strip()[:120]}")
    return problems


class DocumentedPaths(unittest.TestCase):
    def test_human_qa_doc_matches_the_script_base(self):
        script = (ROOT / "scripts/human-qa.sh").read_text().splitlines()[17]
        base = script.split("=", 1)[1].strip().strip('"')
        doc = (ROOT / "docs/HUMAN-QA.md").read_text().splitlines()[37]
        self.assertIn("$HOME/AI-Brain-build/zeus-human-qa", script)
        self.assertIn(base, doc)

    def test_voice_pipeline_doc_matches_the_script_directory(self):
        script = (ROOT / "scripts/voice-selftest.sh").read_text().splitlines()[38]
        directory = script.split("=", 1)[1].strip().strip('"')
        doc = (ROOT / "docs/VOICE-PIPELINE.md").read_text().splitlines()[72]
        self.assertEqual(directory, "$HOME/AI-Brain-build/voice-selftest")
        self.assertIn(directory, doc)

    def test_step_zero_defines_models_dir_before_the_report_copy(self):
        text = (ROOT / "docs/STEP-ZERO-PROBE-PLAN.md").read_text()
        copy_at = text.index("Copy the file to")
        definition = "`<models-dir>` is `$HOME/AI-Brain-build`"
        self.assertIn(definition, text)
        self.assertLess(text.index(definition), copy_at)
        self.assertIn("<models-dir>/zeus-plans/step-zero/", text[copy_at:copy_at + 200])

    def test_kokoro_acceptance_uses_example_home(self):
        data = json.loads((ROOT / "qa/feature-map.json").read_text())
        acceptance = next(ob["acceptance"] for feature in data["features"] for ob in feature["obligations"]
                          if ob["id"] == "F11.local-worker-protocol")
        self.assertIn("HOME=/Users/example", acceptance)
        self.assertIn("/Users/example", acceptance)

    def test_assistant_key_reads_a_neutral_name_and_the_legacy_file(self):
        text = (ROOT / "Sources/Zeus/App/AssistantKeyImporter.swift").read_text()
        neutral = '"/.zeus/anthropic-key.txt"'
        legacy = '"/.zeus/tony-anthropic-key.txt"'
        self.assertIn(neutral, text)
        self.assertIn(legacy, text)
        resolver = text.split("func defaultKeyPath", 1)[1].split("static func", 1)[0]
        self.assertLess(resolver.index(neutral), resolver.index(legacy))
        caller = text.split("func importDefaultIfNeeded", 1)[1].split("static func", 1)[0]
        self.assertIn("defaultKeyPath()", caller)

    def test_runnable_commands_have_no_undefined_placeholders(self):
        problems = []
        for path in markdown_files():
            for problem in undefined_placeholders(path.read_text()):
                problems.append(f"{path.relative_to(ROOT)}: {problem}")
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
