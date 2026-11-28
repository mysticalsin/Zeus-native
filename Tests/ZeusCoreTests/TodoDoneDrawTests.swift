import Testing
@testable import ZeusCore

struct TodoDoneDrawTests {
    @Test func markingAToDoDoneShowsTheTitle() throws {
        let plan = try #require(TodoDoneDraw.from(line: "Done: send the invoice."))
        let missed = try #require(TodoDoneDraw.from(line: "I couldn't find a to-do called the invoice."))
        func cards(_ plan: TodoDoneDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Done", "send the invoice"])
        #expect(plan.boltCaption(at: 0) == "Done")
        #expect(plan.boltCaption(at: 100) == "send the invoice")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(missed) == ["Missing", "the invoice"])
        #expect(missed.boltCaption(at: 0) == "Missing")
    }

    @Test func anAddedToDoAndAStaleScreenAreNotThisCard() {
        #expect(TodoDoneDraw.from(line: "") == nil)
        #expect(TodoDoneDraw.from(line: "Done.") == nil)
        #expect(TodoDoneDraw.from(line: "Done: .") == nil)
        #expect(TodoDoneDraw.from(line: "I couldn't find a to-do called .") == nil)
        #expect(TodoDoneDraw.from(line: "I couldn't add that to-do.") == nil)
        #expect(TodoDoneDraw.from(line: "Added send the invoice.") == nil)
        #expect(TodoDoneDraw.from(line: "That screen changed before I got to s3:e7.") == nil)
        #expect(TodoDoneDraw.from(line: "Done. The report is saved.") == nil)
    }
}
