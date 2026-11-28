import Testing
@testable import ZeusCore

struct FacePresenceSetDrawTests {
    private func cards(_ plan: FacePresenceSetDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func workAndWaitFollowAbsent() {
        let usual = FacePresenceSetDraw.plan(work: "Off", wait: "2 minutes")
        #expect(cards(usual) == ["Absent", "Work: Off", "Wait: 2 minutes"])
        #expect(FacePresenceSetAsk.line(work: "Off", wait: "2 minutes") == "Face presence is off, and it locks after you have been absent for 2 minutes.")
        #expect(usual.boltCaption(at: 0) == "Absent")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Wait: 2 minutes")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(FacePresenceSetAsk.line(work: "On", wait: "30 seconds") == "Face presence is on, and it locks after you have been absent for 30 seconds.")
        #expect(cards(FacePresenceSetDraw.plan(work: "On", wait: "10 minutes")) == ["Absent", "Work: On", "Wait: 10 minutes"])
        #expect(cards(FacePresenceSetDraw.plan(work: "Off", wait: "3 minutes")) == ["Absent", "Can't"])
        #expect(FacePresenceSetAsk.line(work: "Maybe", wait: "2 minutes") == "I can't read the face presence settings.")
    }

    @Test func beingPresentStaysOffThisAsk() {
        #expect(FacePresenceSetAsk.matches("how's face presence set"))
        #expect(FacePresenceSetAsk.matches("Hey Zeus, which lock after?"))
        #expect(FacePresenceSetAsk.matches("face presence settings"))
        #expect(!FacePresenceSetAsk.matches("how is face presence"))
        #expect(!FacePresenceSetAsk.matches("is face presence on"))
        #expect(!FacePresenceSetAsk.matches("is my face present"))
        #expect(!FacePresenceSetAsk.matches("how's lock and wake set"))
    }
}
