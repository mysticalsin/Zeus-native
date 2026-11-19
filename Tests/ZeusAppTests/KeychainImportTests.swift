import Foundation
import Testing
@testable import Zeus

/// `--keychain-import` is how scripts hand Zeus a value so Zeus's own signature owns the Keychain item.
/// An item made by the `security` tool is readable only by Apple tools, so Zeus silently got nothing.
struct KeychainImportTests {
    @Test func theSavedElevenLabsVoiceCanBeImportedByScripts() {
        #expect(KeychainSelfTest.importable.contains("elevenlabs.voice-id"))
        #expect(KeychainSelfTest.aliases["elevenlabs-voice-id"] == "elevenlabs.voice-id")
    }
}
