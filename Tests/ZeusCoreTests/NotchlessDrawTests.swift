import Testing
@testable import ZeusCore

struct NotchlessDrawTests {
    private func cards(_ plan: NotchlessDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func shapeAndSeeFollowShape() {
        let usual = NotchlessDraw.plan(shape: "Pill", see: "No display")
        #expect(cards(usual) == ["Shape", "Shape: Pill", "See: No display"])
        #expect(NotchlessAsk.line(shape: "Pill", see: "No display") == "Displays without a notch draw a Pill, and there is no display without a notch.")
        #expect(usual.boltCaption(at: 0) == "Shape")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "See: No display")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(NotchlessAsk.line(shape: "Notch", see: "Shown") == "Displays without a notch draw a Notch, and it is shown.")
        #expect(NotchlessAsk.line(shape: "Notch", see: "Not shown") == "Displays without a notch draw a Notch, and it is not shown on that display.")
        #expect(cards(NotchlessDraw.plan(shape: "Pill", see: "Shown")) == ["Shape", "Shape: Pill", "See: Shown"])
        #expect(cards(NotchlessDraw.plan(shape: "Wide", see: "Shown")) == ["Shape", "Can't"])
        #expect(NotchlessAsk.line(shape: "Pill", see: "Hidden") == "I can't read the notchless shape.")
    }

    @Test func whereTheNotchIsStaysOffThisAsk() {
        #expect(NotchlessAsk.matches("how's the notchless shape"))
        #expect(NotchlessAsk.matches("Hey Zeus, pill or notch?"))
        #expect(NotchlessAsk.matches("notchless display settings"))
        #expect(!NotchlessAsk.matches("how is the notch"))
        #expect(!NotchlessAsk.matches("where is the notch"))
        #expect(!NotchlessAsk.matches("how's the waves set"))
        #expect(!NotchlessAsk.matches("which other notch lights"))
    }
}
