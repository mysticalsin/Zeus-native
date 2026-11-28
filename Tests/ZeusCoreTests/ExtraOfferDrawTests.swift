import Testing
@testable import ZeusCore

struct ExtraOfferDrawTests {
    private func cards(_ plan: ExtraOfferDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func bothExtraAgentsCanBeOffered() {
        let usual = ExtraOfferDraw.plan(cursor: "On", gemini: "On")
        #expect(cards(usual) == ["More", "Cursor: On", "Gemini: On"])
        #expect(ExtraOfferAsk.line(cursor: "On", gemini: "On") == "Cursor is offered for new chats, and Gemini is offered for new chats.")
        #expect(usual.boltCaption(at: 0) == "More")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Gemini: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ExtraOfferAsk.line(cursor: "Off", gemini: "On") == "Cursor is not offered for new chats, and Gemini is offered for new chats.")
        #expect(cards(ExtraOfferDraw.plan(cursor: "Yes", gemini: "On")) == ["More", "Can't"])
        #expect(ExtraOfferAsk.line(cursor: "On", gemini: "Maybe") == "I can't read the extra agent offers.")
    }

    @Test func claudeAndCodexStayOffThisAsk() {
        #expect(ExtraOfferAsk.matches("are cursor and gemini offered"))
        #expect(ExtraOfferAsk.matches("Hey Zeus, is Cursor offered for new chats?"))
        #expect(ExtraOfferAsk.matches("which extra agents are offered"))
        #expect(!ExtraOfferAsk.matches("which agents are offered"))
        #expect(!ExtraOfferAsk.matches("how are finished agents shown"))
        #expect(!ExtraOfferAsk.matches("how is coding set"))
        #expect(!ExtraOfferAsk.matches("what is the second talk key"))
    }
}
