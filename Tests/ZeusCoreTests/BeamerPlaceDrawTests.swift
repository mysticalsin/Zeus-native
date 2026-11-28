import Testing
@testable import ZeusCore

struct BeamerPlaceDrawTests {
    private func cards(_ plan: BeamerPlaceDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePlaceIsTheSecondCard() {
        let home = BeamerPlaceDraw.plan(phase: "This Mac")
        #expect(cards(home) == ["Beamer", "This Mac"])
        #expect(BeamerPlaceAsk.line(phase: "This Mac") == "Input is on this Mac.")
        #expect(home.boltCaption(at: 0) == "Beamer")
        #expect(home.boltCaption(at: ExplainBeatSchedule.gap) == "This Mac")
        #expect(home.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(BeamerPlaceDraw.plan(phase: "Driving", name: "MacBook")) == ["Beamer", "MacBook"])
        #expect(BeamerPlaceAsk.line(phase: "Driving", name: "MacBook") == "Your keyboard and mouse are on MacBook.")
        #expect(BeamerPlaceAsk.line(phase: "Driven", name: "Office") == "Office is driving this Mac.")
        #expect(BeamerPlaceAsk.line(phase: "Paused") == "Crossing is paused.")
        #expect(cards(BeamerPlaceDraw.plan(phase: "Driving", name: " ")) == ["Beamer", "Can't"])
        #expect(cards(BeamerPlaceDraw.plan(phase: "Banana")) == ["Beamer", "Can't"])
        #expect(BeamerPlaceAsk.line(phase: "") == "I can't see Beamer.")
    }

    @Test func commandsAndTheSoundStayOffThisAsk() {
        #expect(BeamerPlaceAsk.matches("where's my keyboard"))
        #expect(BeamerPlaceAsk.matches("Hey Zeus, how's Beamer?"))
        #expect(BeamerPlaceAsk.matches("is beamer running"))
        #expect(!BeamerPlaceAsk.matches("pause beamer"))
        #expect(!BeamerPlaceAsk.matches("start beamer"))
        #expect(!BeamerPlaceAsk.matches("where is the sound going"))
        #expect(!BeamerPlaceAsk.matches("how's face presence"))
        #expect(!BeamerPlaceAsk.matches("what's playing"))
    }
}
