import Testing
@testable import ZeusCore

struct DriveAutonomyDrawTests {
    private func cards(_ plan: DriveAutonomyDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuTitleIsTheSecondCard() {
        let safe = DriveAutonomyDraw.plan(word: "Safe steps alone")
        #expect(cards(safe) == ["Drive", "Safe steps alone"])
        #expect(DriveAutonomyAsk.line(word: "Safe steps alone") == "Zeus runs safe steps on its own.")
        #expect(safe.boltCaption(at: 0) == "Drive")
        #expect(safe.boltCaption(at: ExplainBeatSchedule.gap) == "Safe steps alone")
        #expect(safe.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(DriveAutonomyAsk.line(word: "Always ask") == "Zeus always asks before it drives.")
        #expect(DriveAutonomyAsk.line(word: "Trusted") == "Zeus runs trusted steps on its own.")
        #expect(cards(DriveAutonomyDraw.plan(word: "Banana")) == ["Drive", "Can't"])
        #expect(DriveAutonomyAsk.line(word: "") == "I can't read how Zeus may drive.")
    }

    @Test func theScreenAndARunningDriveStayOffThisAsk() {
        #expect(DriveAutonomyAsk.matches("when may you drive"))
        #expect(DriveAutonomyAsk.matches("Hey Zeus, can you drive?"))
        #expect(DriveAutonomyAsk.matches("how's drive"))
        #expect(!DriveAutonomyAsk.matches("can you see the screen"))
        #expect(!DriveAutonomyAsk.matches("how's my license"))
        #expect(!DriveAutonomyAsk.matches("where's my keyboard"))
        #expect(!DriveAutonomyAsk.matches("I'm already driving"))
        #expect(!DriveAutonomyAsk.matches("pause beamer"))
    }
}
