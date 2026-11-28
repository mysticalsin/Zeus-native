import Testing
@testable import ZeusCore

struct NotchFitDrawTests {
    private func cards(_ plan: NotchFitDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallSitsFlush() {
        let usual = NotchFitDraw.plan(bar: "0", waves: "100")
        #expect(cards(usual) == ["Fit", "Bar: 0", "Waves: 100"])
        #expect(NotchFitAsk.line(bar: "0", waves: "100") == "The closed notch is flush with the top, and the waves react at 100.")
        #expect(usual.boltCaption(at: 0) == "Fit")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Waves: 100")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(NotchFitAsk.line(bar: "12", waves: "150") == "The closed notch is 12 points lower, and the waves react at 150.")
        #expect(cards(NotchFitDraw.plan(bar: "24", waves: "50")) == ["Fit", "Bar: 24", "Waves: 50"])
        #expect(cards(NotchFitDraw.plan(bar: "1", waves: "100")) == ["Fit", "Can't"])
        #expect(NotchFitAsk.line(bar: "0", waves: "49") == "I can't read the closed notch.")
    }

    @Test func theWavesStyleStaysOffThisAsk() {
        #expect(NotchFitAsk.matches("how low is the top bar"))
        #expect(NotchFitAsk.matches("Hey Zeus, how sensitive are the waves?"))
        #expect(NotchFitAsk.matches("what is the top bar position"))
        #expect(!NotchFitAsk.matches("how is the waves set"))
        #expect(!NotchFitAsk.matches("where is the notch"))
        #expect(!NotchFitAsk.matches("how is command line control set"))
        #expect(!NotchFitAsk.matches("which dictation microphone"))
    }
}
