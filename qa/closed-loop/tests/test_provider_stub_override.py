"""Z5 gap: a DEBUG-only loopback override, off unless the sentinel is set."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "Sources/Zeus/Brain/Providers/OpenAICompatProvider.swift"


class ProviderStubOverride(unittest.TestCase):
    def test_debug_stub_is_opt_in_and_loopback_only(self):
        text = SOURCE.read_text(encoding="utf-8")
        self.assertIn("#if DEBUG", text)
        self.assertIn("ZEUS_DEBUG_PROVIDER_STUB", text)
        self.assertIn("ZEUS_DEBUG_PROVIDER_BASE_URL", text)
        self.assertIn('url.host == "127.0.0.1"', text)
        self.assertIn("ProviderEndpointOverride.resolved", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
