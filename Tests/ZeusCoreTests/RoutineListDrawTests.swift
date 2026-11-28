import Testing
@testable import ZeusCore

struct RoutineListDrawTests {
    private func cards(_ plan: RoutineListDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshListHasNoRoutines() {
        let usual = RoutineListDraw.plan(saved: "0", on: "0")
        #expect(cards(usual) == ["Routines", "Saved: 0", "On: 0"])
        #expect(RoutineListAsk.line(saved: "0", on: "0") == "No routines are saved.")
        #expect(usual.boltCaption(at: 0) == "Routines")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "On: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(RoutineListAsk.line(saved: "1", on: "1") == "1 routine is saved, and it is on.")
        #expect(RoutineListAsk.line(saved: "5", on: "2") == "5 routines are saved, and 2 are on.")
        #expect(RoutineListAsk.line(saved: "5", on: "0") == "5 routines are saved, and none are on.")
        #expect(cards(RoutineListDraw.plan(saved: "2", on: "3")) == ["Routines", "Can't"])
        #expect(RoutineListAsk.line(saved: "1000", on: "0") == "I can't read the routines.")
    }

    @Test func aToDoCountStaysOffThisAsk() {
        #expect(RoutineListAsk.matches("how are routines set"))
        #expect(RoutineListAsk.matches("Hey Zeus, how many routines are on?"))
        #expect(RoutineListAsk.matches("are any routines on"))
        #expect(!RoutineListAsk.matches("how many to-dos"))
        #expect(!RoutineListAsk.matches("how are to-dos set"))
        #expect(!RoutineListAsk.matches("does zeus move the system pointer"))
        #expect(!RoutineListAsk.matches("are quick cues on"))
    }
}
