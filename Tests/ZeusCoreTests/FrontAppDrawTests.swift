import Testing
@testable import ZeusCore

struct FrontAppDrawTests {
    private func cards(_ plan: FrontAppDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theFrontAppDrawsTheName() {
        let plan = FrontAppDraw.plan(name: "Safari")
        #expect(plan.map(cards) == ["Front", "Safari"])
        #expect(FrontAppAsk.line(name: "Safari") == "Safari is in front.")
        #expect(plan?.boltCaption(at: 0) == "Front")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Safari")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(FrontAppDraw.plan(name: "  ") == nil)
        #expect(cards(FrontAppDraw.unseen()) == ["Front", "Can't"])
        #expect(FrontAppAsk.unseen == "I can't see the front app.")
    }

    @Test func aLongNameStaysOnTheCardAndTheWindowTitleIsNotThisAsk() {
        let long = String(repeating: "A", count: 70)
        let plan = FrontAppDraw.plan(name: long)
        let shown = plan.map(cards) ?? []
        #expect(shown.first == "Front")
        #expect(shown.dropFirst().first?.count == 60)
        #expect(!(shown.joined(separator: " ").contains(String(repeating: "A", count: 61))))
        #expect(FrontAppAsk.line(name: long) == "\(String(repeating: "A", count: 60)) is in front.")
        #expect(FrontAppAsk.matches("what's in front"))
        #expect(FrontAppAsk.matches("Hey Zeus, what app is this?"))
        #expect(FrontAppAsk.matches("which app is in front"))
        #expect(!FrontAppAsk.matches("what's playing"))
        #expect(!FrontAppAsk.matches("open Safari"))
        #expect(!FrontAppAsk.matches("what's on my clipboard"))
        #expect(!FrontAppAsk.matches("how many clips"))
        #expect(!FrontAppAsk.matches("what's my week"))
    }
}
