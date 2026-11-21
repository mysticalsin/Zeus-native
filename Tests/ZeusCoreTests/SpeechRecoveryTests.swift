import Foundation
import Testing
@testable import ZeusCore

@Suite("Speech recovery")
struct SpeechRecoveryTests {
    @Test func providerClipWaitUsesTheSelfTestBound() {
        let started = Date(timeIntervalSince1970: 1_000)
        #expect(ProviderClipWait.expired(started: started, now: started.addingTimeInterval(ProviderClipWait.limit)) )
        #expect(ProviderClipWait.expired(started: started, now: started.addingTimeInterval(ProviderClipWait.limit - 0.1)) == false)
        #expect(ProviderClipWait.limit == 25)
    }

    @Test func aCutOffSentenceIsNotSpoken() {
        #expect(CloudSentenceEnd.decide(scheduledAudio: true, transportFailed: true, cancelled: false) == .failed)
        #expect(CloudSentenceEnd.decide(scheduledAudio: false, transportFailed: true, cancelled: false) == .failed)
        #expect(CloudSentenceEnd.decide(scheduledAudio: true, transportFailed: false, cancelled: false) == .spoken)
        #expect(CloudSentenceEnd.decide(scheduledAudio: true, transportFailed: true, cancelled: true) == .cancelled)
    }

    @Test func aSilentHeaderIsAbandonedAtTheFirstAudioTimeout() {
        let began = Date(timeIntervalSince1970: 5_000)
        let timeout = VoiceTTSChain.firstAudioTimeout
        #expect(CloudHeaderWait.shouldAbandon(began: began, now: began.addingTimeInterval(timeout), receivedAudio: false))
        #expect(CloudHeaderWait.shouldAbandon(began: began, now: began.addingTimeInterval(timeout - 0.1), receivedAudio: false) == false)
        #expect(CloudHeaderWait.shouldAbandon(began: began, now: began.addingTimeInterval(timeout + 5), receivedAudio: true) == false)
    }
}
