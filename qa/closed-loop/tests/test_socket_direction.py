"""Each socket direction pins the program on that side, not the other side's identifier."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class SocketDirection(unittest.TestCase):
    def test_chrome_bridge_pins_the_helper(self):
        text = (ROOT / "Sources/Zeus/Chrome/ChromeBridge.swift").read_text()
        self.assertIn("serverIdentifier: SocketPeerIdentifier.bridge", text)

    def test_the_app_server_pins_helper_identifiers(self):
        text = (ROOT / "Sources/ZeusCore/PeerSigning.swift").read_text()
        window = text.split("defaultVerifier", 1)[1][:500]
        self.assertIn("acceptHelper", window)
        self.assertNotIn("bundleIdentifier", window)


if __name__ == "__main__":
    unittest.main()
