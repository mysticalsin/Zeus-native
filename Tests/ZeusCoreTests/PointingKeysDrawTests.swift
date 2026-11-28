import Testing
@testable import ZeusCore

struct PointingKeysDrawTests {
    private func cards(_ plan: PointingKeysDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuTitleIsTheSecondCard() {
        let chord = PointingKeysDraw.plan(word: "Control-Option")
        #expect(cards(chord) == ["Pointing", "Control-Option"])
        #expect(PointingKeysAsk.line(word: "Control-Option") == "Pointing uses Control and Option.")
        #expect(chord.boltCaption(at: 0) == "Pointing")
        #expect(chord.boltCaption(at: ExplainBeatSchedule.gap) == "Control-Option")
        #expect(chord.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(PointingKeysAsk.line(word: "Right Option") == "Pointing uses the right Option key.")
        #expect(PointingKeysAsk.line(word: "Fn (Globe)") == "Pointing uses the Fn key.")
        #expect(cards(PointingKeysDraw.plan(word: "Banana")) == ["Pointing", "Can't"])
        #expect(PointingKeysAsk.line(word: "") == "I can't read the pointing keys.")
    }

    @Test func aPointAtAControlAndTheNotchStayOffThisAsk() {
        #expect(PointingKeysAsk.matches("what's the pointing key"))
        #expect(PointingKeysAsk.matches("Hey Zeus, which keys point?"))
        #expect(PointingKeysAsk.matches("how's pointing"))
        #expect(!PointingKeysAsk.matches("point at the File menu"))
        #expect(!PointingKeysAsk.matches("where's the notch"))
        #expect(!PointingKeysAsk.matches("can you drive"))
        #expect(!PointingKeysAsk.matches("which voice is this"))
    }
}
