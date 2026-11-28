import Testing
@testable import ZeusCore

struct LidStatusDrawTests {
    private func cards(_ plan: LidStatusDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func thePageWordIsTheSecondCard() {
        let closed = LidStatusDraw.plan(word: "Closed, still working")
        #expect(cards(closed) == ["Lid", "Closed, still working"])
        #expect(LidStatusAsk.line(word: "Closed, still working") == "The lid is closed, and the Mac is still working.")
        #expect(closed.boltCaption(at: 0) == "Lid")
        #expect(closed.boltCaption(at: ExplainBeatSchedule.gap) == "Closed, still working")
        #expect(closed.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(LidStatusAsk.line(word: "Off") == "Lid-closed mode is off.")
        #expect(LidStatusAsk.line(word: "Open") == "The lid is open.")
        #expect(LidStatusAsk.line(word: "Arming\u{2026}") == "Lid-closed mode is arming.")
        #expect(LidStatusAsk.line(word: "Needs setup") == "Lid-closed mode needs setup.")
        #expect(LidStatusAsk.line(word: "No lid on this Mac") == "This Mac has no lid.")
        #expect(cards(LidStatusDraw.plan(word: "  ")) == ["Lid", "Can't"])
        #expect(LidStatusAsk.line(word: "") == "I can't read the lid.")
    }

    @Test func aLongArmingFailureStaysOffTheSpokenLine() {
        let reason = "Not armed: " + String(repeating: "x", count: 80)
        let plan = LidStatusDraw.plan(word: reason)
        #expect(cards(plan) == ["Lid", String(reason.prefix(TalkDraw.maxTextCharacters))])
        #expect(LidStatusAsk.line(word: reason) == "Lid-closed mode is not armed.")
        #expect(!LidStatusAsk.line(word: reason).contains("xxx"))
        #expect(LidStatusAsk.matches("how's the lid"))
        #expect(LidStatusAsk.matches("Hey Zeus, is the lid closed?"))
        #expect(!LidStatusAsk.matches("keep awake"))
        #expect(!LidStatusAsk.matches("how's the prompter"))
        #expect(!LidStatusAsk.matches("how much did I use today"))
        #expect(!LidStatusAsk.matches("what's my battery"))
    }
}
