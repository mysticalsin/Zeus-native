import Testing
@testable import ZeusCore

struct AgentNoteDrawTests {
    @Test func aNamedAgentKeepsTheNote() throws {
        let kept = try #require(AgentNoteDraw.plan(agent: "Scout", note: "tea at 4"))
        let refused = try #require(AgentNoteDraw.refused(agent: "Scout"))
        func cards(_ plan: AgentNoteDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(kept) == ["Scout", "tea at 4"])
        #expect(kept.boltCaption(at: 0) == "Scout")
        #expect(kept.boltCaption(at: 100) == "tea at 4")
        #expect(kept.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(kept.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(refused) == ["Scout", "Not stored"])
        #expect(refused.note.isEmpty)
        #expect(refused.boltCaption(at: 0) == "Scout")
        #expect(refused.boltCaption(at: 100) == "Not stored")
    }

    @Test func aBlankNoteAndASecretAreNotDrawn() {
        #expect(AgentNoteDraw.plan(agent: "Scout", note: " ") == nil)
        #expect(AgentNoteDraw.plan(agent: " ", note: "tea at 4") == nil)
        #expect(AgentNoteDraw.plan(agent: "Scout", note: "my password is hidden") == nil)
        #expect(AgentNoteDraw.hides("the cvv is 123"))
        #expect(AgentNoteDraw.hides("social security number"))
        #expect(AgentNoteDraw.refused(agent: " ") == nil)
    }
}
