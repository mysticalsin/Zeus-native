import Testing
@testable import ZeusCore

struct WentAwayDrawTests {
    @Test func aControlThatWentAwayShowsItsName() throws {
        let plan = try #require(WentAwayDraw.from(line: "\u{201C}Save\u{201D} went away before I could press it."))
        func cards(_ plan: WentAwayDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Gone", "\u{201C}Save\u{201D}"])
        #expect(plan.boltCaption(at: 0) == "Gone")
        #expect(plan.boltCaption(at: 100) == "\u{201C}Save\u{201D}")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        let window = try #require(WentAwayDraw.from(line: "that window went away before I could raise it."))
        #expect(cards(window) == ["Gone", "that window"])
    }

    @Test func aMissingTargetAndAStaleScreenAreNotThisGone() {
        #expect(WentAwayDraw.from(line: "") == nil)
        #expect(WentAwayDraw.from(line: "went away before I could press it.") == nil)
        #expect(WentAwayDraw.from(line: "I couldn't find \u{201C}Save\u{201D}.") == nil)
        #expect(WentAwayDraw.from(line: "That screen changed before I got to the button.") == nil)
        #expect(WentAwayDraw.from(line: "I can't press \u{201C}Save\u{201D} directly.") == nil)
        #expect(WentAwayDraw.from(line: "Polyglot is turned off in Settings.") == nil)
        #expect(WentAwayDraw.from(line: "I can't find the folder Notes.") == nil)
    }
}
