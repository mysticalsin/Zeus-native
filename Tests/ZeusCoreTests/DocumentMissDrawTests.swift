import Testing
@testable import ZeusCore

struct DocumentMissDrawTests {
    @Test func anApprovedDocumentZeusCouldNotUseShowsUnavailable() throws {
        let plan = try #require(DocumentMissDraw.from(line: "The approved document is unavailable. Nothing was changed."))
        func cards(_ plan: DocumentMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Document", "Unavailable"])
        #expect(plan.boltCaption(at: 0) == "Document")
        #expect(plan.boltCaption(at: 100) == "Unavailable")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aPageLeftUntouchedAndAnAskLeftAreNotThisDocument() {
        #expect(DocumentMissDraw.from(line: "") == nil)
        #expect(DocumentMissDraw.from(line: "The selected tab is no longer available.") == nil)
        #expect(DocumentMissDraw.from(line: "Chrome couldn't identify the page. Nothing was changed.") == nil)
        #expect(DocumentMissDraw.from(line: "The approved page navigated. Nothing was changed.") == nil)
        #expect(DocumentMissDraw.from(line: "Read page.target before approving this action. Nothing was changed.") == nil)
        #expect(DocumentMissDraw.from(line: "I can't ask you about that yet, so I left.") == nil)
        #expect(DocumentMissDraw.from(line: "Beamer's menu didn't respond to \u{201C}Pause\u{201D}.") == nil)
    }
}
