import Testing
@testable import ZeusCore

struct DrawnSizeDrawTests {
    private func cards(_ plan: DrawnSizeDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallIsTheDefaultSize() {
        let usual = DrawnSizeDraw.plan(width: "185", height: "32", place: "Centre")
        #expect(cards(usual) == ["Size", "Wide: 185", "Tall: 32", "Place: Centre"])
        #expect(DrawnSizeAsk.line(width: "185", height: "32", place: "Centre") == "The drawn notch is 185 points wide, 32 points tall, and centred.")
        #expect(usual.boltCaption(at: 0) == "Size")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Place: Centre")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(DrawnSizeAsk.line(width: "140", height: "30", place: "5 pt left") == "The drawn notch is 140 points wide, 30 points tall, and 5 points to the left.")
        #expect(DrawnSizeAsk.line(width: "280", height: "44", place: "400 pt right") == "The drawn notch is 280 points wide, 44 points tall, and 400 points to the right.")
        #expect(cards(DrawnSizeDraw.plan(width: "141", height: "32", place: "Centre")) == ["Size", "Can't"])
        #expect(DrawnSizeAsk.line(width: "185", height: "32", place: "Middle") == "I can't read the drawn notch size.")
    }

    @Test func theShapeStaysOffThisAsk() {
        #expect(DrawnSizeAsk.matches("how big is the drawn notch"))
        #expect(DrawnSizeAsk.matches("Hey Zeus, where does the drawn notch sit?"))
        #expect(DrawnSizeAsk.matches("drawn notch size settings"))
        #expect(!DrawnSizeAsk.matches("what is the drawn notch"))
        #expect(!DrawnSizeAsk.matches("how is the notchless shape"))
        #expect(!DrawnSizeAsk.matches("how is talk sight set"))
        #expect(!DrawnSizeAsk.matches("how is the closed notch set"))
    }
}
