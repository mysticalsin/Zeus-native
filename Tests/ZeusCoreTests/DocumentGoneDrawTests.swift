import Testing
@testable import ZeusCore

struct DocumentGoneDrawTests {
    @Test func anApprovedDocumentThatDisappearedShowsGone() throws {
        let plan = try #require(DocumentGoneDraw.from(line: "The approved document is no longer available. Nothing was changed."))
        func cards(_ plan: DocumentGoneDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Document", "Gone"])
        #expect(plan.boltCaption(at: 0) == "Document")
        #expect(plan.boltCaption(at: 100) == "Gone")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anUnavailableDocumentAndAMissingTabAreNotThisGone() {
        #expect(DocumentGoneDraw.from(line: "") == nil)
        #expect(DocumentGoneDraw.from(line: "The approved document is unavailable. Nothing was changed.") == nil)
        #expect(DocumentGoneDraw.from(line: "The selected tab is no longer available.") == nil)
        #expect(DocumentGoneDraw.from(line: "The approved page navigated. Nothing was changed.") == nil)
        #expect(DocumentGoneDraw.from(line: "No active Chrome tab") == nil)
        #expect(DocumentGoneDraw.from(line: "No assistant called dust") == nil)
        #expect(DocumentGoneDraw.from(line: "I couldn't find that tab") == nil)
    }
}
