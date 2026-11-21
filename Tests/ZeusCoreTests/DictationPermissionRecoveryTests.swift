import Testing
@testable import ZeusCore

@Suite("Dictation permission recovery")
struct DictationPermissionRecoveryTests {
    @Test func deniedMicrophoneOpensThePrivacyPane() {
        let decision = DictationPermissionGate.decide(microphone: .denied, speech: .authorized, localEngineReady: false)
        #expect(decision == .showSettings(message: "Dictation needs the microphone.", pane: DictationPermissionGate.microphonePane))
    }

    @Test func unaskedMicrophonePromptsInsteadOfFailing() {
        let decision = DictationPermissionGate.decide(microphone: .notDetermined, speech: .notDetermined, localEngineReady: true)
        #expect(decision == .prompt(.microphone))
    }

    @Test func deniedSpeechWithoutALocalEngineOpensSpeechSettings() {
        let decision = DictationPermissionGate.decide(microphone: .authorized, speech: .denied, localEngineReady: false)
        #expect(decision == .showSettings(message: "Dictation needs speech recognition.", pane: DictationPermissionGate.speechPane))
    }

    @Test func localEngineStartsWhenSpeechWasRefused() {
        let decision = DictationPermissionGate.decide(microphone: .authorized, speech: .denied, localEngineReady: true)
        #expect(decision == .start)
    }

    @Test func unaskedSpeechPromptsWhenNoLocalEngineIsReady() {
        let decision = DictationPermissionGate.decide(microphone: .authorized, speech: .notDetermined, localEngineReady: false)
        #expect(decision == .prompt(.speech))
    }
}
