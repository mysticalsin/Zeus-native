import Testing
@testable import ZeusCore

@Suite("Connection control speech")
struct ConnectionControlSpeechTests {
    @Test func connectionPrimaryNamesTheProviderAndTheAction() {
        let speech = ConnectionControlSpeech.primary(provider: "Codex", action: "Connect", detail: "Found on this Mac.", busy: false)
        #expect(speech.label == "Connect Codex")
        #expect(speech.value == "Found on this Mac.")
        #expect(speech.hint == "Connect Codex.")
    }

    @Test func aBusyCheckNamesTheProvider() {
        let speech = ConnectionControlSpeech.primary(provider: "Ollama", action: "Start", detail: "Checking", busy: true)
        #expect(speech.label == "Checking Ollama")
        #expect(speech.value == "Busy")
        #expect(speech.hint.contains("Ollama"))
    }

    @Test func reducedMotionToggleDurationIsZero() {
        #expect(ConnectionControlSpeech.reducedMotionToggleSeconds == 0)
    }

    @Test func statusAndFieldsNameTheProvider() {
        #expect(ConnectionControlSpeech.status(provider: "Grok Bot", text: "Available") == "Grok Bot, Available")
        #expect(ConnectionControlSpeech.field(provider: "Any LLM", field: "API key") == "Any LLM API key")
    }
}
