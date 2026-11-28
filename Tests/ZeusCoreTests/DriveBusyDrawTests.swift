import Testing
@testable import ZeusCore

struct DriveBusyDrawTests {
    @Test func anOngoingDriveShowsStop() throws {
        let plan = try #require(DriveBusyDraw.from(line: "I'm already driving. Press Esc to stop that first."))
        func cards(_ plan: DriveBusyDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Drive", "Stop"])
        #expect(plan.boltCaption(at: 0) == "Drive")
        #expect(plan.boltCaption(at: 100) == "Stop")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anAccessibilityNoticeAndAResearchNoticeAreNotThisDrive() {
        #expect(DriveBusyDraw.from(line: "") == nil)
        #expect(DriveBusyDraw.from(line: "I'm already driving. Press Esc to stop that first") == nil)
        #expect(DriveBusyDraw.from(line: "I'm already researching something. Stop it first.") == nil)
        #expect(DriveBusyDraw.from(line: "Stopped.") == nil)
        #expect(DriveBusyDraw.from(line: "I need Accessibility access to drive your Mac. It's in System Settings, Privacy.") == nil)
        #expect(DriveBusyDraw.from(line: "Okay, I won't touch anything.") == nil)
        #expect(DriveBusyDraw.from(line: "I'm already working on a web task. Say stop or press Esc to end it first.") == nil)
    }
}
