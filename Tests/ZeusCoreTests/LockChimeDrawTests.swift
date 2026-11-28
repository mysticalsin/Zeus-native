import Testing
@testable import ZeusCore

struct LockChimeDrawTests {
    private func cards(_ plan: LockChimeDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func workLockAndWakeFollowChimes() {
        let usual = LockChimeDraw.plan(work: "On", lock: "Built-in", wake: "Built-in")
        #expect(cards(usual) == ["Chimes", "Work: On", "Lock: Built-in", "Wake: Built-in"])
        #expect(LockChimeAsk.line(work: "On", lock: "Built-in", wake: "Built-in") == "Lock and wake chimes are on, the lock sound is built in, and the wake sound is built in.")
        #expect(usual.boltCaption(at: 0) == "Chimes")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Wake: Built-in")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(LockChimeAsk.line(work: "Off", lock: "Chosen", wake: "Chosen") == "Lock and wake chimes are off, the lock sound is a file you chose, and the wake sound is a file you chose.")
        #expect(cards(LockChimeDraw.plan(work: "On", lock: "Built-in", wake: "Chosen")) == ["Chimes", "Work: On", "Lock: Built-in", "Wake: Chosen"])
        #expect(cards(LockChimeDraw.plan(work: "On", lock: "File", wake: "Built-in")) == ["Chimes", "Can't"])
        #expect(LockChimeAsk.line(work: "Maybe", lock: "Built-in", wake: "Built-in") == "I can't read the lock and wake chimes.")
    }

    @Test func soundEventsStayOffThisAsk() {
        #expect(LockChimeAsk.matches("how's lock and wake set"))
        #expect(LockChimeAsk.matches("Hey Zeus, which lock chimes?"))
        #expect(LockChimeAsk.matches("lock and wake settings"))
        #expect(!LockChimeAsk.matches("which events play a sound"))
        #expect(!LockChimeAsk.matches("which cue sounds"))
        #expect(!LockChimeAsk.matches("how's the voice styled"))
        #expect(!LockChimeAsk.matches("how is the lid"))
    }
}
