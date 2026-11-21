import Foundation
import Testing
@testable import ZeusCore

@Suite struct TalkMissingSetupTests {
    /// The Microphone row in Settings when access is denied.
    private let microphone = "Denied. Turn it on in System Settings \u{203A} Privacy \u{203A} Microphone."
    /// The Screen Recording row in Settings when access is denied.
    private let screen = "Denied. Turn it on in System Settings \u{203A} Privacy \u{203A} Screen Recording."
    private let key = "No key saved. Commands go to the assistant."
    private let cli = "Not found on this Mac. Install shows the official command."

    @Test func aMissingMicrophoneUsesTheSettingsSentence() {
        #expect(TalkMissingSetup.sentence(mic: false, screen: true, brainKey: true, cli: true) == microphone)
    }

    @Test func aMissingScreenUsesTheSettingsSentence() {
        #expect(TalkMissingSetup.sentence(mic: true, screen: false, brainKey: true, cli: true) == screen)
    }

    @Test func eachGapHasItsOwnSentenceAndEveryGapIsReported() {
        #expect(key != cli)
        #expect(TalkMissingSetup.sentences(mic: true, screen: true, brainKey: false, cli: true) == [key])
        #expect(TalkMissingSetup.sentences(mic: true, screen: true, brainKey: true, cli: false) == [cli])
        #expect(TalkMissingSetup.sentences(mic: true, screen: true, brainKey: false, cli: false) == [key, cli])
        #expect(TalkMissingSetup.sentences(mic: false, screen: false, brainKey: true, cli: true) == [microphone, screen])
        let all = TalkMissingSetup.sentences(mic: false, screen: false, brainKey: false, cli: false)
        #expect(all == [microphone, screen, key, cli])
        for line in all {
            #expect(!line.localizedCaseInsensitiveContains("camera"))
            #expect(!line.localizedCaseInsensitiveContains("calendar"))
            #expect(!line.localizedCaseInsensitiveContains("automation"))
        }
    }

    @Test func everythingPresentNeedsNoSentence() {
        #expect(TalkMissingSetup.sentences(mic: true, screen: true, brainKey: true, cli: true).isEmpty)
    }
}
