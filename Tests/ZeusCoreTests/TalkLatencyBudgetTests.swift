import Testing
@testable import ZeusCore

@Suite("Talk latency budget")
struct TalkLatencyBudgetTests {
    @Test func twoHundredPlusFiveHundredPlusThreeFiftyIsOneThousandFifty() {
        let sample = TalkLatencySample(sttFinalMs: 200, captureReadyMs: 40, firstTokenMs: 500, ttsFirstMs: 350)
        #expect(sample.firstAudioMs == 1_050)
    }

    @Test func aMissingCaptureAddsNoTime() {
        let sample = TalkLatencySample(sttFinalMs: 200, captureReadyMs: nil, firstTokenMs: 500, ttsFirstMs: 350)
        #expect(sample.captureReadyMs == nil)
        #expect(sample.firstAudioMs == 1_050)
    }

    @Test func fastTierFirstTextBudgetStaysEightSeconds() {
        #expect(FastTier.firstTextBudgetMs == 8_000)
    }

    @Test func oneThousandFiftyIsWithinBudgetAndThirteenHundredIsOver() {
        #expect(TalkLatencyBudget.firstAudioTargetMs == 1_200)
        #expect(TalkLatencyBudget.sttFinalCapMs == 450)
        #expect(1_050 <= TalkLatencyBudget.firstAudioTargetMs)
        #expect(1_300 > TalkLatencyBudget.firstAudioTargetMs)
        let inside = TalkLatencySample(sttFinalMs: 200, firstTokenMs: 500, ttsFirstMs: 350, firstVisualMs: nil)
        let over = TalkLatencySample(sttFinalMs: 400, firstTokenMs: 500, ttsFirstMs: 400, firstVisualMs: 1_400)
        #expect(inside.firstAudioMs == 1_050)
        #expect(inside.firstAudioMs <= TalkLatencyBudget.firstAudioTargetMs)
        #expect(over.firstAudioMs == 1_300)
        #expect(over.firstAudioMs > TalkLatencyBudget.firstAudioTargetMs)
        #expect(over.firstVisualMs == 1_400)
    }
}
