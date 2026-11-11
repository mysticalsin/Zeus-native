import Testing
import ZeusCore

@Suite("Speech attempt policy")
struct SpeechAttemptPolicyTests {
    @Test func aSilentEngineThatWasNotInterruptedIsRecordedAsFailing() {
        #expect(SpeechAttemptPolicy.shouldRecordFailure(producedAudio: false, cancelled: false))
    }

    @Test func aBargeInIsNeverAnEngineFailure() {
        #expect(!SpeechAttemptPolicy.shouldRecordFailure(producedAudio: false, cancelled: true))
    }

    @Test func anEngineThatSpokeIsNeverAFailure() {
        #expect(!SpeechAttemptPolicy.shouldRecordFailure(producedAudio: true, cancelled: false))
        #expect(!SpeechAttemptPolicy.shouldRecordFailure(producedAudio: true, cancelled: true))
    }

    @Test func lateAudioMayNotPlayAfterACancel() {
        #expect(SpeechAttemptPolicy.mayPlay(cancelled: false))
        #expect(!SpeechAttemptPolicy.mayPlay(cancelled: true))
    }
}
