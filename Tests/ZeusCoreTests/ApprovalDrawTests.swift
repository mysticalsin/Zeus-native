import Testing
@testable import ZeusCore

struct ApprovalDrawTests {
    @Test func theThreeVerdictsNameTheCard() throws {
        let approved = try #require(ApprovalDraw.plan(result: "Approved"))
        let denied = try #require(ApprovalDraw.plan(result: "Denied"))
        let handed = try #require(ApprovalDraw.plan(result: "Over to the app"))
        func cards(_ plan: ApprovalDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(approved) == ["Approval", "Approved"])
        #expect(cards(denied) == ["Approval", "Denied"])
        #expect(cards(handed) == ["Approval", "Over to the app"])
        #expect(approved.boltCaption(at: 0) == "Approval")
        #expect(approved.boltCaption(at: 100) == "Approved")
        #expect(handed.boltCaption(at: 100) == "Over to the app")
        #expect(approved.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(approved.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherWordsAreNotAVerdict() {
        #expect(ApprovalDraw.plan(result: "") == nil)
        #expect(ApprovalDraw.plan(result: " ") == nil)
        #expect(ApprovalDraw.plan(result: "Allowed") == nil)
        #expect(ApprovalDraw.plan(result: "Open Safari") == nil)
        #expect(ApprovalDraw.plan(result: "Done") == nil)
    }
}
