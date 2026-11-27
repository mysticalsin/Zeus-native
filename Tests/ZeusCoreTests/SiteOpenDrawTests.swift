import Testing
@testable import ZeusCore

struct SiteOpenDrawTests {
    @Test func aPageShowsTheHostWithoutWww() throws {
        let plan = try #require(SiteOpenDraw.plan(url: "https://www.example.com/docs"))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Site", "example.com"])
        #expect(plan.boltCaption(at: 0) == "Site")
        #expect(plan.boltCaption(at: 100) == "example.com")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        let port = try #require(SiteOpenDraw.plan(url: "http://localhost:3000/app"))
        #expect(port.host == "localhost")
    }

    @Test func aMailOrFileAddressIsNotDrawn() {
        #expect(SiteOpenDraw.plan(url: "mailto:user@example.com") == nil)
        #expect(SiteOpenDraw.plan(url: "file:///tmp/note.txt") == nil)
        #expect(SiteOpenDraw.plan(url: "  ") == nil)
        #expect(SiteOpenDraw.plan(url: "https://") == nil)
    }
}
