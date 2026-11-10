import Foundation
import Testing
@testable import ZeusCore

// The bridge itself lives in the Zeus target, which this test target can't import; these cover the ZeusCore
// rules its separate preview task relies on.
@Suite("W7 Scribe preview rules")
struct W7ScribeTests {
    private func segment(_ session: ScribeSessionID, _ text: String, final: Bool, speaker: ScribeSpeaker = .unknown) -> ScribeTranscriptSegment {
        ScribeTranscriptSegment(id: "mic-0", session: session, speaker: speaker, start: 0, end: 2, text: text, isFinal: final)
    }

    @Test func lateProvisionalNeverOverwritesFinal() {
        let session = ScribeSessionID()
        var transcript = ScribeTranscript(session: session)
        _ = transcript.upsert(segment(session, "hello there", final: true, speaker: .you))
        // A preview that finishes after the closed chunk was recognised (previews run on their own task).
        let late = transcript.upsert(segment(session, "hello", final: false))
        #expect(late == .ignoredLocked)
        #expect(transcript.segments.first?.text == "hello there")
        #expect(transcript.segments.first?.speaker == .you)
    }

    @Test func previewReplacesPlaceholderThenFinalReplacesPreview() {
        let session = ScribeSessionID()
        var transcript = ScribeTranscript(session: session)
        _ = transcript.upsert(segment(session, "…", final: false))
        let preview = transcript.upsert(segment(session, "hello", final: false))
        let final = transcript.upsert(segment(session, "hello there", final: true, speaker: .you))
        #expect(preview == .replaced)
        #expect(final == .replaced)
        #expect(transcript.segments.count == 1)
    }

    @Test func unmatchedPreviewSpeakerIsNotYou() {
        #expect(ScribeSpeaker.unknown != .you)
        #expect(ScribeSpeaker.unknown.displayName == "Unknown")
    }
}
