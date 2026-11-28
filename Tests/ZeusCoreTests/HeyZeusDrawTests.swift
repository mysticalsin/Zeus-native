import Testing
@testable import ZeusCore

struct HeyZeusDrawTests {
    private func cards(_ plan: HeyZeusDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePillIsTheSecondCard() {
        let listening = HeyZeusDraw.plan(word: "Listening")
        #expect(cards(listening) == ["Hey Zeus", "Listening"])
        #expect(HeyZeusAsk.line(word: "Listening") == "Hey Zeus is listening.")
        #expect(listening.boltCaption(at: 0) == "Hey Zeus")
        #expect(listening.boltCaption(at: ExplainBeatSchedule.gap) == "Listening")
        #expect(listening.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(HeyZeusAsk.line(word: "Off") == "Hey Zeus is off.")
        #expect(HeyZeusAsk.line(word: "Not asked yet") == "Hey Zeus has not asked yet.")
        #expect(HeyZeusAsk.line(word: "Denied") == "Hey Zeus was denied.")
        #expect(HeyZeusAsk.line(word: "Paused") == "Hey Zeus is paused.")
        #expect(cards(HeyZeusDraw.plan(word: "Banana")) == ["Hey Zeus", "Can't"])
        #expect(HeyZeusAsk.line(word: "") == "I can't read Hey Zeus.")
    }

    @Test func heatAndDictationStayOffThisAsk() {
        #expect(HeyZeusAsk.matches("how's hey zeus"))
        #expect(HeyZeusAsk.matches("Hey Zeus, is Hey Zeus on?"))
        #expect(HeyZeusAsk.matches("are you listening for hey zeus"))
        #expect(!HeyZeusAsk.matches("how's the heat"))
        #expect(!HeyZeusAsk.matches("is dictation on"))
        #expect(!HeyZeusAsk.matches("is translation on"))
        #expect(!HeyZeusAsk.matches("how many chats"))
        #expect(!HeyZeusAsk.matches("start live translation"))
    }
}
