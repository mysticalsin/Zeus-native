import Foundation
import Testing
@testable import ZeusCore

@Suite("Incremental dictation")
struct IncrementalDictationTests {
    private let rate = 16_000

    private func speech(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.2 * sin(Float($0) * 0.1) }
    }

    private func silence(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * Double(rate))) }

    /// Feeds audio in 100 ms pieces, as the microphone does, and collects every chunk handed out.
    private func feed(_ scheduler: inout ChunkScheduler, _ audio: [Float]) -> [Range<Int>] {
        var chunks: [Range<Int>] = []
        let piece = rate / 10
        var start = 0
        while start < audio.count {
            let end = min(start + piece, audio.count)
            chunks += scheduler.append(Array(audio[start..<end]))
            start = end
        }
        return chunks
    }

    @Test func shortDictationSendsNothingUntilRelease() {
        var scheduler = ChunkScheduler()
        let chunks = feed(&scheduler, speech(2))
        #expect(chunks.isEmpty)
        #expect(scheduler.finalDecision() == .transcribeTail(0..<scheduler.totalSamples))
    }

    @Test func aPauseAfterEnoughSpeechEndsAChunk() {
        var scheduler = ChunkScheduler()
        let chunks = feed(&scheduler, speech(4) + silence(0.5))
        #expect(chunks.count == 1)
        #expect(chunks[0].lowerBound == 0)
        #expect(chunks[0].upperBound > 4 * rate)
        #expect(chunks[0].upperBound <= scheduler.totalSamples)
    }

    @Test func aPauseBeforeTheMinimumDoesNotEndAChunk() {
        var scheduler = ChunkScheduler()
        let chunks = feed(&scheduler, speech(1.5) + silence(0.6))
        #expect(chunks.isEmpty)
    }

    @Test func longSpeechWithoutPausesIsCutAtTheMaximum() {
        var scheduler = ChunkScheduler()
        let chunks = feed(&scheduler, speech(13))
        #expect(chunks.count == 1)
        #expect(chunks[0].count >= 12 * rate)
    }

    @Test func chunksDoNotOverlapAndCoverTheRecording() {
        var scheduler = ChunkScheduler()
        let audio = speech(4) + silence(0.5) + speech(4) + silence(0.5) + speech(1)
        let chunks = feed(&scheduler, audio)
        #expect(chunks.count == 2)
        #expect(chunks[0].upperBound == chunks[1].lowerBound)
        guard case .transcribeTail(let tail) = scheduler.finalDecision() else {
            Issue.record("Expected a tail to transcribe")
            return
        }
        #expect(tail.lowerBound == chunks[1].upperBound)
        #expect(tail.upperBound == audio.count)
    }

    @Test func silenceAfterTheLastChunkIsSkipped() {
        var scheduler = ChunkScheduler()
        _ = feed(&scheduler, speech(4) + silence(0.5))
        _ = feed(&scheduler, silence(0.3))
        #expect(scheduler.finalDecision() == .skipTail)
    }

    @Test func aTailThatIsTooShortIsSkipped() {
        var scheduler = ChunkScheduler()
        _ = feed(&scheduler, speech(4) + silence(0.4))
        _ = scheduler.append(speech(0.05))
        #expect(scheduler.finalDecision() == .skipTail)
    }

    @Test func spokenTailAfterAChunkIsTranscribed() {
        var scheduler = ChunkScheduler()
        let first = feed(&scheduler, speech(4) + silence(0.5))
        _ = feed(&scheduler, speech(1))
        #expect(scheduler.finalDecision() == .transcribeTail(first[0].upperBound..<scheduler.totalSamples))
    }

    @Test func quietRecordingIsStillTranscribedWhenNothingWasSentYet() {
        var scheduler = ChunkScheduler()
        _ = feed(&scheduler, silence(2))
        #expect(scheduler.finalDecision() == .transcribeTail(0..<scheduler.totalSamples))
    }

    @Test func emptyRecordingIsEmpty() {
        #expect(ChunkScheduler().finalDecision() == .empty)
    }

    @Test func silentStretchCostsNoChunk() {
        var scheduler = ChunkScheduler()
        let chunks = feed(&scheduler, silence(13))
        #expect(chunks.isEmpty)
        #expect(scheduler.committedSamples > 0)
    }

    @Test func joinerKeepsOrderAndDropsEmptyParts() {
        #expect(ChunkTranscriptJoiner.join(["Hello there.", " ", "  How are you? "]) == "Hello there. How are you?")
        #expect(ChunkTranscriptJoiner.join([]) == "")
    }
}

@Suite("Model keep-alive policy")
struct ModelKeepAlivePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func defaultIsTenMinutes() {
        #expect(ModelKeepAlivePolicy().keepAliveSeconds == 600)
    }

    @Test func recentUseKeepsTheModelAndSchedulesTheRemainder() {
        let policy = ModelKeepAlivePolicy()
        let action = policy.evaluate(lastUse: now.addingTimeInterval(-100), activeUses: 0, now: now)
        #expect(action == .checkAgain(after: 500))
    }

    @Test func idleForTenMinutesUnloads() {
        let policy = ModelKeepAlivePolicy()
        #expect(policy.evaluate(lastUse: now.addingTimeInterval(-600), activeUses: 0, now: now) == .unload)
        #expect(policy.evaluate(lastUse: now.addingTimeInterval(-3_000), activeUses: 0, now: now) == .unload)
    }

    @Test func workInFlightNeverUnloads() {
        let policy = ModelKeepAlivePolicy()
        #expect(policy.evaluate(lastUse: now.addingTimeInterval(-3_000), activeUses: 1, now: now) == .checkAgain(after: 600))
    }

    @Test func neverUsedUnloads() {
        #expect(ModelKeepAlivePolicy().evaluate(lastUse: nil, activeUses: 0, now: now) == .unload)
    }

    @Test func clockGoingBackwardsDoesNotShortenTheWindow() {
        let policy = ModelKeepAlivePolicy()
        #expect(policy.evaluate(lastUse: now.addingTimeInterval(50), activeUses: 0, now: now) == .checkAgain(after: 600))
    }
}

@Suite("Dictation latency log")
struct DictationLatencyTests {
    @Test func fastReleaseIsWithinTheTarget() {
        let latency = DictationLatency(releaseToTextMs: 240, transcribeMs: 180, audioMs: 5_000, engine: "parakeet", insertion: "paste")
        #expect(latency.withinTarget)
        #expect(latency.logLine.contains("release->text 240 ms"))
        #expect(latency.logLine.contains("within 300 ms target"))
    }

    @Test func slowReleaseIsReportedOver() {
        let latency = DictationLatency(releaseToTextMs: 300, transcribeMs: 250, audioMs: 1_000, engine: "apple", insertion: "paste")
        #expect(!latency.withinTarget)
        #expect(latency.logLine.contains("over 300 ms target"))
    }

    @Test func millisecondsRoundAndNeverGoNegative() {
        let start = Date(timeIntervalSince1970: 100)
        #expect(DictationLatency.milliseconds(from: start, to: start.addingTimeInterval(0.2504)) == 250)
        #expect(DictationLatency.milliseconds(from: start, to: start.addingTimeInterval(-1)) == 0)
    }

    @Test func logLineHoldsNoDictatedText() {
        let latency = DictationLatency(releaseToTextMs: 10, transcribeMs: 5, audioMs: 100, engine: "parakeet", insertion: "type")
        #expect(latency.logLine.hasPrefix("dictation: "))
    }
}
