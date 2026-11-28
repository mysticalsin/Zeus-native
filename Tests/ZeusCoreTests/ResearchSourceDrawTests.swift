import Testing
@testable import ZeusCore

@Suite struct ResearchSourceDrawTests {
    @Test func sourcesAreDrawnOneSiteAtATime() throws {
        let plan = try #require(ResearchSourceDraw.plan(sources: [
            "https://www.example.com/a",
            "https://example.com/b",
            "https://news.example.org/story",
            "https://extra.test/too-many",
            "https://fourth.test/dropped",
        ]))
        #expect(plan.hosts == ["example.com", "news.example.org", "extra.test"])
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Sources", "example.com", "news.example.org", "extra.test"])
        #expect(plan.boltCaption(at: 0) == "Sources")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 690, y: 320))
        let hostBeat = ExplainBeatSchedule.gap * 2
        #expect(plan.boltCaption(at: hostBeat) == "example.com")
        #expect(plan.guideBolt(at: hostBeat) == TalkDraw.Point(x: 920, y: 180))
        #expect(plan.boltCaption(at: .nan) == "Sources")
        #expect(plan.guideBolt(at: .nan) == TalkDraw.Point(x: 320, y: 320))
    }

    @Test func aResearchAnswerWithoutAWebSourceIsNotDrawn() {
        #expect(ResearchSourceDraw.plan(sources: []) == nil)
        #expect(ResearchSourceDraw.plan(sources: [
            "mailto:user@example.com",
            "javascript:alert(1)",
            "file:///tmp/notes.txt",
            "not a url",
        ]) == nil)
    }
}
