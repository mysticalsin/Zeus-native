import Testing
@testable import ZeusCore

struct FindMissDrawTests {
    @Test func aMissingDriveTargetShowsItsName() throws {
        let plan = try #require(FindMissDraw.from(line: "I couldn't find \u{201C}Save\u{201D}."))
        func cards(_ plan: FindMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Find", "\u{201C}Save\u{201D}"])
        #expect(plan.boltCaption(at: 0) == "Find")
        #expect(plan.boltCaption(at: 100) == "\u{201C}Save\u{201D}")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        let control = try #require(FindMissDraw.from(line: "I couldn't find that control."))
        #expect(cards(control) == ["Find", "that control"])
    }

    @Test func aProjectAFileAndAKeyAreNotThisMiss() {
        #expect(FindMissDraw.from(line: "") == nil)
        #expect(FindMissDraw.from(line: "I couldn't find.") == nil)
        #expect(FindMissDraw.from(line: "I couldn't find .") == nil)
        #expect(FindMissDraw.from(line: "I couldn't find that.") == nil)
        #expect(FindMissDraw.from(line: "I couldn't find a project called Zeus.") == nil)
        #expect(FindMissDraw.from(line: "I couldn't find a to-do called tea.") == nil)
        #expect(FindMissDraw.from(line: "I couldn't find that on screen, so I'll keep going.") == nil)
        #expect(FindMissDraw.from(line: "I couldn't find a Safari window called \u{201C}Notes\u{201D}.") == nil)
        #expect(FindMissDraw.from(line: "I don't know the key return.") == nil)
        #expect(FindMissDraw.from(line: "The separate browser stopped.") == nil)
        #expect(FindMissDraw.from(line: "I can't tell whether Dark Mode is on or off.") == nil)
    }
}
