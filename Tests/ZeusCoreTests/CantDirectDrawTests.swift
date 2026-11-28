import Testing
@testable import ZeusCore

struct CantDirectDrawTests {
    @Test func aControlZeusCannotUseDirectlyShowsItsName() throws {
        let plan = try #require(CantDirectDraw.from(line: "I can't press \u{201C}Save\u{201D} directly."))
        func cards(_ plan: CantDirectDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Can't", "\u{201C}Save\u{201D}"])
        #expect(plan.boltCaption(at: 0) == "Can't")
        #expect(plan.boltCaption(at: 100) == "\u{201C}Save\u{201D}")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        let window = try #require(CantDirectDraw.from(line: "I can't raise that window directly."))
        #expect(cards(window) == ["Can't", "that window"])
    }

    @Test func aGoneControlAndAMissingToolAreNotThisDirect() {
        #expect(CantDirectDraw.from(line: "") == nil)
        #expect(CantDirectDraw.from(line: "I can't press directly.") == nil)
        #expect(CantDirectDraw.from(line: "I can't expand Dark Mode.") == nil)
        #expect(CantDirectDraw.from(line: "\u{201C}Save\u{201D} went away before I could press it.") == nil)
        #expect(CantDirectDraw.from(line: "I can't find the claude command line tool.") == nil)
        #expect(CantDirectDraw.from(line: "I can't tell whether Dark Mode is on or off.") == nil)
        #expect(CantDirectDraw.from(line: "I can't find the folder Notes.") == nil)
    }
}
