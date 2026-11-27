import Testing
@testable import ZeusCore

struct DriveAccessDrawTests {
    @Test func aMissingAccessibilityGrantShowsDrive() throws {
        let clipped = "I need Accessibility access to drive your Mac. It's in."
        for line in [DriveAccessDraw.line, clipped, "I need Accessibility access to drive your Mac."] {
            let plan = try #require(DriveAccessDraw.from(line: line))
            func cards(_ plan: DriveAccessDraw) -> [String] {
                plan.draw.marks.compactMap { mark in
                    if case .card(_, let text) = mark.shape { return text }
                    return nil
                }
            }
            #expect(cards(plan) == ["Accessibility", "Drive"])
            #expect(plan.boltCaption(at: 0) == "Accessibility")
            #expect(plan.boltCaption(at: 100) == "Drive")
            #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
            #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        }
    }

    @Test func otherDriveLinesAreNotTheGrant() {
        #expect(DriveAccessDraw.from(line: "") == nil)
        #expect(DriveAccessDraw.from(line: "I'm already driving. Press Esc to stop that first.") == nil)
        #expect(DriveAccessDraw.from(line: "Stopped.") == nil)
        #expect(DriveAccessDraw.from(line: "Okay, I won't touch anything.") == nil)
        #expect(DriveAccessDraw.from(line: "I couldn't lock the screen.") == nil)
    }
}
