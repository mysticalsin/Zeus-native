import Foundation
import Testing
@testable import Zeus

/// A fake engine stands in for every voice engine: no audio is made and nothing leaves the Mac.
@MainActor
@Suite("Speaker line start", .serialized)
struct SpeakerTests {
    @Test func onStartFiresOncePerLineInOrderBeforeTheNextLineBegins() async throws {
        let speaker = Speaker(languageCode: "en-US")
        var events: [String] = []
        speaker.attemptOverride = { text in
            events.append("begin \(text)")
            return "fake"
        }
        for line in ["a", "b", "c"] {
            speaker.speak(line) { events.append("start \(line)") }
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while speaker.isSpeaking, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(events == ["begin a", "start a", "begin b", "start b", "begin c", "start c"])
    }

    @Test func aLineWithNoCallbackStillSpeaks() async throws {
        let speaker = Speaker(languageCode: "en-US")
        var spoken: [String] = []
        speaker.attemptOverride = { text in spoken.append(text); return "fake" }
        speaker.speak("only")
        let deadline = ContinuousClock.now + .seconds(10)
        while speaker.isSpeaking, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(spoken == ["only"])
    }

    /// Engines queue a line's audio behind the earlier line's: the first buffer is scheduled while the earlier
    /// line still plays. The start callback must wait for that earlier audio to finish.
    @Test func aPipelinedLineStartsOnlyAfterTheEarlierLinesAudioHasPlayed() async throws {
        let speaker = Speaker(languageCode: "en-US")
        let ledger = speaker.playbackLedger
        var events: [String] = []
        speaker.attemptOverride = { text in
            ledger.noteScheduled()
            speaker.markAudioReady()
            events.append("queued \(text)")
            return "fake"
        }
        speaker.speak("a") { events.append("start a") }
        speaker.speak("b") { events.append("start b") }
        let deadline = ContinuousClock.now + .seconds(10)
        while !events.contains("queued b"), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(events == ["start a", "queued a", "queued b"], "line b is queued but line a has not finished")

        ledger.noteCompleted(generation: ledger.generation)
        #expect(events == ["start a", "queued a", "queued b", "start b"])
        ledger.noteCompleted(generation: ledger.generation)
        #expect(events.filter { $0.hasPrefix("start") }.count == 2)
    }

    @Test func aStopDropsTheWaitingLineStartsAndIgnoresLateCompletions() {
        let ledger = PlaybackLedger()
        var fired = 0
        ledger.noteScheduled()
        ledger.whenPlayed(upTo: 1) { fired += 1 }
        let generation = ledger.generation
        ledger.reset()
        ledger.noteCompleted(generation: generation)
        #expect(fired == 0 && ledger.completed == 0 && ledger.scheduled == 0)
        ledger.whenPlayed(upTo: 0) { fired += 1 }
        #expect(fired == 1, "nothing ahead: starts at once")
    }
}
