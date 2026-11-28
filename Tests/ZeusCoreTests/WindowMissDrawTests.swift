import Testing
@testable import ZeusCore

struct WindowMissDrawTests {
    @Test func aMissingWindowShowsItsName() throws {
        let plan = try #require(WindowMissDraw.from(line: "I couldn't find a Safari window called \u{201C}Notes\u{201D}."))
        func cards(_ plan: WindowMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Window", "\u{201C}Notes\u{201D}"])
        #expect(plan.boltCaption(at: 0) == "Window")
        #expect(plan.boltCaption(at: 100) == "\u{201C}Notes\u{201D}")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aDriveTargetAndADirectActionAreNotThisWindow() {
        #expect(WindowMissDraw.from(line: "") == nil)
        #expect(WindowMissDraw.from(line: "I couldn't find a window called \u{201C}Notes\u{201D}.") == nil)
        #expect(WindowMissDraw.from(line: "I couldn't find \u{201C}Save\u{201D}.") == nil)
        #expect(WindowMissDraw.from(line: "I couldn't find a project called Zeus.") == nil)
        #expect(WindowMissDraw.from(line: "I can't press \u{201C}Save\u{201D} directly.") == nil)
        #expect(WindowMissDraw.from(line: "I can't find the claude command line tool.") == nil)
        #expect(WindowMissDraw.from(line: "\u{201C}Save\u{201D} went away before I could press it.") == nil)
    }
}
