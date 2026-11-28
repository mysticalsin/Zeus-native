import Testing
@testable import ZeusCore

struct ClaudeToolDrawTests {
    @Test func aMissingClaudeToolShowsMissing() throws {
        let plan = try #require(ClaudeToolDraw.from(line: "I can't find the claude command line tool."))
        func cards(_ plan: ClaudeToolDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Claude", "Missing"])
        #expect(plan.boltCaption(at: 0) == "Claude")
        #expect(plan.boltCaption(at: 100) == "Missing")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anAnswerFailureAndAGoneControlAreNotThisTool() {
        #expect(ClaudeToolDraw.from(line: "") == nil)
        #expect(ClaudeToolDraw.from(line: "The AI failed; try again.") == nil)
        #expect(ClaudeToolDraw.from(line: "I couldn't reach Claude; check your connection.") == nil)
        #expect(ClaudeToolDraw.from(line: "I can't find the folder Notes.") == nil)
        #expect(ClaudeToolDraw.from(line: "\u{201C}Save\u{201D} went away before I could press it.") == nil)
        #expect(ClaudeToolDraw.from(line: "Polyglot is turned off in Settings.") == nil)
    }
}
