import Testing
@testable import ZeusCore

struct OutputDrawTests {
    private func cards(_ plan: OutputDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuNameIsTheSecondCard() {
        let plan = OutputDraw.plan(name: "MacBook Speakers")
        #expect(cards(plan) == ["Output", "MacBook Speakers"])
        #expect(OutputAsk.line(name: "MacBook Speakers") == "The sound is going to MacBook Speakers.")
        #expect(plan.boltCaption(at: 0) == "Output")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "MacBook Speakers")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(OutputAsk.cardName("Air\nPods Pro") == "Air Pods Pro")
        #expect(cards(OutputDraw.plan(name: "  ")) == ["Output", "Can't"])
        #expect(OutputAsk.line(name: "") == "I can't see the output.")
        let long = String(repeating: "A", count: 80)
        #expect(cards(OutputDraw.plan(name: long)) == ["Output", String(long.prefix(TalkDraw.maxTextCharacters))])
    }

    @Test func earbudsAndTheLidStayOffThisAsk() {
        #expect(OutputAsk.matches("where's the sound going"))
        #expect(OutputAsk.matches("Hey Zeus, which output?"))
        #expect(OutputAsk.matches("what's the output"))
        #expect(!OutputAsk.matches("are my earbuds connected"))
        #expect(!OutputAsk.matches("how's the lid"))
        #expect(!OutputAsk.matches("what's the volume"))
        #expect(!OutputAsk.matches("what's playing"))
        #expect(!OutputAsk.matches("how's the prompter"))
    }
}
