import Foundation
import Testing
@testable import ZeusCore

private struct FakeEngine: TranscriptionEngine {
    let kind: TranscriptionEngineKind
    var state: EngineAvailability = .ready
    var text = "hello"
    var fails = false

    func availability() async -> EngineAvailability { state }
    func prepare(progress: (@Sendable (Double) -> Void)?) async throws {}
    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        if fails { throw TranscriptionError.noSpeech }
        return text
    }
}

@Suite("Transcription engines")
struct TranscriptionEngineTests {
    @Test func preferredWinsWhenReady() {
        let kind = EngineSelection.resolve(preferred: .whisper, availability: [.parakeet: .ready, .whisper: .ready, .apple: .ready])
        #expect(kind == .whisper)
    }

    @Test func fallsBackInOrderWhenPreferredIsMissing() {
        #expect(EngineSelection.resolve(preferred: .whisper, availability: [.parakeet: .ready, .whisper: .notDownloaded, .apple: .ready]) == .parakeet)
        #expect(EngineSelection.resolve(preferred: .parakeet, availability: [.parakeet: .downloading(0.4), .apple: .ready]) == .apple)
        #expect(EngineSelection.resolve(preferred: .parakeet, availability: [:]) == .apple)
    }

    @Test func routerUsesPreferredAndTrims() async throws {
        let router = TranscriptionRouter(engines: [FakeEngine(kind: .parakeet, text: "  local words \n"), FakeEngine(kind: .apple, text: "apple")])
        let result = try await router.transcribe(samples: [0], preferred: .parakeet)
        #expect(result.text == "local words")
        #expect(result.engine == .parakeet)
    }

    @Test func routerFallsBackWhenEngineThrows() async throws {
        let router = TranscriptionRouter(engines: [FakeEngine(kind: .parakeet, fails: true), FakeEngine(kind: .apple, text: "apple")])
        let result = try await router.transcribe(samples: [0], preferred: .parakeet)
        #expect(result.engine == .apple)
        #expect(result.text == "apple")
    }

    @Test func routerSkipsEnginesThatAreNotReady() async throws {
        let router = TranscriptionRouter(engines: [FakeEngine(kind: .parakeet, state: .notDownloaded, text: "nope"), FakeEngine(kind: .apple, text: "apple")])
        #expect(try await router.transcribe(samples: [0], preferred: .parakeet).engine == .apple)
    }

    @Test func routerThrowsWhenEverythingFails() async {
        let router = TranscriptionRouter(engines: [FakeEngine(kind: .apple, fails: true)])
        await #expect(throws: TranscriptionError.noSpeech) { try await router.transcribe(samples: [0], preferred: .apple) }
    }

    @Test func wordErrorRateIgnoresCaseAndPunctuation() {
        #expect(TranscriptMetrics.wordErrorRate(reference: "Hello, World!", hypothesis: "hello world") == 0)
        #expect(TranscriptMetrics.wordErrorRate(reference: "Let's go", hypothesis: "lets go") == 0)
    }

    @Test func wordErrorRateCountsEdits() {
        // one substitution, one deletion over four words
        #expect(TranscriptMetrics.wordErrorRate(reference: "the quick brown fox", hypothesis: "the slow fox") == 0.5)
        // insertions can push past 100 %
        #expect(TranscriptMetrics.wordErrorRate(reference: "hi", hypothesis: "oh hi there friend") == 3)
        #expect(TranscriptMetrics.wordErrorRate(reference: "", hypothesis: "") == 0)
    }

    @Test func olderHistoryRecordsStillDecode() throws {
        let json = #"{"id":"a","datetime":"2026-10-01T10:00:00Z","duration":1200,"processingTime":300,"modeKey":"voice","modeName":"Voice","rawResult":"hi","result":"Hi","inserted":true,"source":"microphone"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(DictationRecord.self, from: Data(json.utf8))
        #expect(record.engine == nil)
        #expect(DictationRecord(duration: 1, processingTime: 1, modeKey: "v", modeName: "V", rawResult: "", result: "", engine: "parakeet").engine == "parakeet")
    }
}
