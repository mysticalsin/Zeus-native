import Testing
@testable import ZeusCore

struct PointSecretDrawTests {
    @Test func aSecretPointShowsSecret() throws {
        let plan = try #require(PointSecretDraw.from(line: "I won't point at that."))
        func cards(_ plan: PointSecretDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Point", "Secret"])
        #expect(plan.boltCaption(at: 0) == "Point")
        #expect(plan.boltCaption(at: 100) == "Secret")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aMissingControlAndAPasswordFieldAreNotThisPoint() {
        #expect(PointSecretDraw.from(line: "") == nil)
        #expect(PointSecretDraw.from(line: "I couldn't find that on screen, so I'll keep going.") == nil)
        #expect(PointSecretDraw.from(line: "That's a password or payment field, so I left it for you. Type it yourself and tell me when to carry on.") == nil)
        #expect(PointSecretDraw.from(line: "Chrome couldn't identify the page. Nothing was changed.") == nil)
    }
}
