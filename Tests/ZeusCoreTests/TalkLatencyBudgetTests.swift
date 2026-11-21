import Foundation
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

    @Test func firstAudioAndFinalCapBoundaries() {
        func audio(_ stt: Int, _ token: Int, _ tts: Int) -> Int {
            TalkLatencySample(sttFinalMs: stt, firstTokenMs: token, ttsFirstMs: tts).firstAudioMs
        }
        #expect(audio(1_199, 0, 0) == 1_199)
        #expect(audio(1_200, 0, 0) == 1_200)
        #expect(audio(1_201, 0, 0) == 1_201)
        #expect(audio(1_199, 0, 0) <= TalkLatencyBudget.firstAudioTargetMs)
        #expect(audio(1_200, 0, 0) <= TalkLatencyBudget.firstAudioTargetMs)
        #expect(audio(1_201, 0, 0) > TalkLatencyBudget.firstAudioTargetMs)
        #expect(audio(449, 0, 0) == 449)
        #expect(audio(450, 0, 0) == 450)
        #expect(audio(451, 0, 0) == 451)
        #expect(449 <= TalkLatencyBudget.sttFinalCapMs)
        #expect(450 <= TalkLatencyBudget.sttFinalCapMs)
        #expect(451 > TalkLatencyBudget.sttFinalCapMs)
    }

    @Test func aNegativeStageDoesNotShrinkTheSumUnderTheTarget() {
        let sample = TalkLatencySample(sttFinalMs: -200, firstTokenMs: 800, ttsFirstMs: 500)
        #expect(sample.firstAudioMs == 1_300)
        #expect(sample.firstAudioMs > TalkLatencyBudget.firstAudioTargetMs)
        let allNegative = TalkLatencySample(sttFinalMs: -5, firstTokenMs: -1, ttsFirstMs: -2)
        #expect(allNegative.firstAudioMs == 0)
    }

    @Test func speechInputArmsTheBudgetInsteadOfTwoAndAHalfSeconds() throws {
        let source = try speechInputSource()
        #expect(source.contains("TalkLatencyBudget.sttFinalCapMs"))
        #expect(source.contains("cancelRecognizerAfterFinalCap"))
        #expect(!source.contains("deadline: .now() + 2.5"))
    }
}

private func speechInputSource() throws -> String {
    var url = URL(fileURLWithPath: #filePath)
    while url.path != "/" {
        let candidate = url.appendingPathComponent("Sources/Zeus/Voice/SpeechInput.swift")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
        url.deleteLastPathComponent()
    }
    struct Missing: Error {}
    throw Missing()
}
