"""Visible settings helpers stay one short sentence, and the privacy facts stay on screen."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
PAGES = ROOT / "Sources/Zeus/Settings/GlanceSettingsPages.swift"
ESCAPE = re.compile(r"\\u\{([0-9A-Fa-f]+)\}")
LITERAL = re.compile(r'"((?:\\.|[^"\\])*)"')


def swift_text(raw):
    return ESCAPE.sub(lambda match: chr(int(match.group(1), 16)), raw)


def sentences(value):
    return [part for part in re.split(r"(?<=[.!?])\s+", value.strip()) if part]


def argument_span(text, start):
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char == '"':
            index += 1
            while index < len(text) and text[index] != '"':
                if text[index] == "\\":
                    index += 2
                    continue
                index += 1
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif char == "," and depth == 0:
            break
        index += 1
    return text[start:index]


def visible_helpers(text):
    found = []
    for match in re.finditer(r"\btext:\s*", text):
        chunk = argument_span(text, match.end())
        line = text[: match.start()].count("\n") + 1
        for literal in LITERAL.finditer(chunk):
            value = swift_text(literal.group(1))
            found.append((line, value))
    return found


class SettingsCopyLint(unittest.TestCase):
    def test_row_helper_text_is_one_short_line(self):
        helpers = visible_helpers(PAGES.read_text())
        too_long = [
            f"line {line} ({len(value)} chars, {len(sentences(value))} sentences): {value}"
            for line, value in helpers
            if len(value) > 90 or len(sentences(value)) > 1
        ]
        self.assertEqual(too_long, [])

    def test_no_page_taglines(self):
        text = PAGES.read_text()
        taglines = []
        for match in re.finditer(r'subtitle:\s*"([^"]*)"', text):
            if match.group(1):
                line = text[: match.start()].count("\n") + 1
                taglines.append(f"line {line}: {match.group(1)}")
        self.assertEqual(taglines, [])

    def test_privacy_disclosures_survive(self):
        helpers = [value.lower() for _, value in visible_helpers(PAGES.read_text())]
        source = PAGES.read_text()
        self.assertTrue(any("microphone indicator" in value for value in helpers))
        self.assertTrue(any("audio" in value and "provider" in value for value in helpers))
        self.assertTrue(any("nothing is sent while" in value for value in helpers))
        self.assertIn("noticePending", source)
        self.assertTrue(any("keychain" in value for value in helpers))


if __name__ == "__main__":
    unittest.main()
