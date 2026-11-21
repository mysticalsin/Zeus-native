import Foundation
import Testing
@testable import ZeusCore

@Suite struct TalkMissingSetupTests {
    /// The Microphone row in Settings when access is denied.
    private let microphone = "Denied. Turn it on in System Settings \u{203A} Privacy \u{203A} Microphone."
    /// The Screen Recording row in Settings when access is denied.
    private let screen = "Denied. Turn it on in System Settings \u{203A} Privacy \u{203A} Screen Recording."
    /// The Integrations row in Settings when the command-line tool is not on this Mac.
    private let brain = "Not found on this Mac. Install shows the official command."

    @Test func aMissingMicrophoneUsesTheSettingsSentence() {
        #expect(TalkMissingSetup.sentence(mic: false, screen: true, brainKey: true, cli: true) == microphone)
    }

    @Test func aMissingScreenUsesTheSettingsSentence() {
        #expect(TalkMissingSetup.sentence(mic: true, screen: false, brainKey: true, cli: true) == screen)
    }

    @Test func aMissingBrainKeyAndCLIUsesTheSettingsSentence() {
        #expect(TalkMissingSetup.sentence(mic: true, screen: true, brainKey: false, cli: false) == brain)
    }

    @Test func aBrainKeyOrCLIAloneNeedsNoSentence() {
        #expect(TalkMissingSetup.sentence(mic: true, screen: true, brainKey: false, cli: true) == nil)
        #expect(TalkMissingSetup.sentence(mic: true, screen: true, brainKey: true, cli: false) == nil)
    }

    @Test func everythingPresentNeedsNoSentence() {
        #expect(TalkMissingSetup.sentence(mic: true, screen: true, brainKey: true, cli: true) == nil)
    }

    @Test func theSentencesDoNotAddCameraCalendarOrAutomation() {
        let lines = [microphone, screen, brain]
        for line in lines {
            #expect(!line.localizedCaseInsensitiveContains("camera"))
            #expect(!line.localizedCaseInsensitiveContains("calendar"))
            #expect(!line.localizedCaseInsensitiveContains("automation"))
        }
    }
}
