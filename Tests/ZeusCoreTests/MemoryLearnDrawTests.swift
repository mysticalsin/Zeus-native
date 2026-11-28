import Testing
@testable import ZeusCore

struct MemoryLearnDrawTests {
    private func cards(_ plan: MemoryLearnDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func learningAndForgottenMeetings() {
        let usual = MemoryLearnDraw.plan(state: "On", forgotten: "0")
        #expect(cards(usual) == ["Learn", "State: On", "Forgotten: 0"])
        #expect(MemoryLearnAsk.line(state: "On", forgotten: "0") == "Memory learning is on, and no meetings are forgotten.")
        #expect(usual.boltCaption(at: 0) == "Learn")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Forgotten: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(MemoryLearnAsk.line(state: "Paused", forgotten: "1") == "Memory learning is paused, and 1 meeting is forgotten.")
        #expect(MemoryLearnAsk.line(state: "Paused", forgotten: "3") == "Memory learning is paused, and 3 meetings are forgotten.")
        #expect(cards(MemoryLearnDraw.plan(state: "Bad", forgotten: "0")) == ["Learn", "Can't"])
        #expect(MemoryLearnAsk.line(state: "On", forgotten: "1000") == "I can't read memory learning.")
    }

    @Test func theSecondBrainStaysOffThisAsk() {
        #expect(MemoryLearnAsk.matches("is memory learning on"))
        #expect(MemoryLearnAsk.matches("Hey Zeus, how many meetings are forgotten?"))
        #expect(MemoryLearnAsk.matches("is memory learning paused"))
        #expect(!MemoryLearnAsk.matches("how is memory set"))
        #expect(!MemoryLearnAsk.matches("memory settings"))
        #expect(!MemoryLearnAsk.matches("how is the second brain set"))
        #expect(!MemoryLearnAsk.matches("is chrome connected"))
    }
}
