import Foundation
import Testing
@testable import ZeusCore

@Suite("W7 Polyglot transcript order")
struct W7PolyglotTests {
    private func line(_ id: Int, _ text: String) -> PolyglotLine {
        PolyglotLine(id: id, side: .microphone, original: text, language: "pt")
    }

    @Test func draining_run_caption_arriving_last_still_sorts_first() {
        var transcript = PolyglotTranscript()
        let older = PolyglotRunIDs.firstID(run: 1)
        let newer = PolyglotRunIDs.firstID(run: 2)
        transcript.upsert(line(newer, "second run"))
        transcript.upsert(line(older, "first run"))
        #expect(transcript.lines.map(\.original) == ["first run", "second run"])
        #expect(transcript.recent(1).first?.original == "second run")
        #expect(transcript.text(target: "en") == "[PT] first run\n[PT] second run")
    }

    @Test func in_order_arrival_still_appends() {
        var transcript = PolyglotTranscript()
        transcript.upsert(line(1, "a"))
        transcript.upsert(line(2, "b"))
        transcript.upsert(line(3, "c"))
        #expect(transcript.lines.map(\.id) == [1, 2, 3])
    }

    @Test func updating_a_known_id_keeps_its_place() {
        var transcript = PolyglotTranscript()
        transcript.upsert(line(1, "a"))
        transcript.upsert(line(2, "b"))
        transcript.upsert(line(1, "a again"))
        #expect(transcript.lines.map(\.original) == ["a again", "b"])
    }

    @Test func trimming_drops_the_oldest_lines() {
        var transcript = PolyglotTranscript()
        for id in 1...(PolyglotTranscript.keep + 5) { transcript.upsert(line(id, "x")) }
        #expect(transcript.lines.count == PolyglotTranscript.keep)
        #expect(transcript.lines.first?.id == 6)
    }
}
