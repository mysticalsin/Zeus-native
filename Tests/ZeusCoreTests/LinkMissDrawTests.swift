import Testing
@testable import ZeusCore

struct LinkMissDrawTests {
    @Test func aLinkThatIsNotAPageShowsNotAPage() throws {
        let plan = try #require(LinkMissDraw.from(line: LinkMissDraw.line))
        func cards(_ plan: LinkMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Link", "Not a page"])
        #expect(plan.boltCaption(at: 0) == "Link")
        #expect(plan.boltCaption(at: 100) == "Not a page")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aWebPageAndOtherLinesAreNotThisCard() {
        #expect(LinkMissDraw.from(line: "") == nil)
        #expect(LinkMissDraw.from(line: "Opening example.com.") == nil)
        #expect(LinkMissDraw.from(line: "Okay, I left it.") == nil)
        #expect(LinkMissDraw.from(line: "I couldn't tell what to run, so I left it.") == nil)
        #expect(LinkMissDraw.from(line: "I couldn't open example.com.") == nil)
    }
}
