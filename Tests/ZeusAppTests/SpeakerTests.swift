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
}
