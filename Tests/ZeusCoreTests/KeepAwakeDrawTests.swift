import Testing
@testable import ZeusCore

struct KeepAwakeDrawTests {
    private func cards(_ plan: KeepAwakeDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aSessionDrawsAwakeThenTheLength() {
        let plan = KeepAwakeDraw.plan(minutes: 30)
        #expect(plan.map(cards) == ["Awake", "30 minutes"])
        #expect(KeepAwakeAsk.lengthLine(minutes: 30) == "Awake for 30 minutes.")
        #expect(KeepAwakeAsk.lengthLine(minutes: 60) == "Awake for 1 hour.")
        #expect(plan?.boltCaption(at: 0) == "Awake")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "30 minutes")
        #expect(plan?.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(KeepAwakeDraw.plan(minutes: 0) == nil)
        #expect(cards(KeepAwakeDraw.openEnded()) == ["Awake", "On"])
        #expect(KeepAwakeAsk.openEnded == "Awake until you stop it.")
    }

    @Test func stoppingDrawsOffAndAFocusAskIsNotAwake() {
        #expect(cards(KeepAwakeDraw.stopped()) == ["Awake", "Off"])
        #expect(cards(KeepAwakeDraw.done()) == ["Awake", "Done"])
        #expect(KeepAwakeAsk.stopped == "Awake stopped.")
        #expect(KeepAwakeAsk.done == "Awake time is up.")
        #expect(KeepAwakeAsk.notOn == "Awake isn't on.")
        #expect(KeepAwakeAsk.command(in: "keep awake") == .startSaved)
        #expect(KeepAwakeAsk.command(in: "Hey Zeus, keep awake for 30 minutes") == .start(30))
        #expect(KeepAwakeAsk.command(in: "keep awake indefinitely") == .start(nil))
        #expect(KeepAwakeAsk.command(in: "let the mac sleep") == .stop)
        #expect(KeepAwakeAsk.command(in: "start focus") == nil)
        #expect(KeepAwakeAsk.command(in: "what's the weather") == nil)
    }
}
