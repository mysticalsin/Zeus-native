import Testing
@testable import ZeusCore

struct ActionMissDrawTests {
    @Test func aMissNamesWhatFailed() throws {
        let closed = try #require(ActionMissDraw.from(line: "Safari didn't open."))
        let quiet = try #require(ActionMissDraw.from(line: "Music didn't respond."))
        let site = try #require(ActionMissDraw.from(line: "I couldn't open example.com."))
        let project = try #require(ActionMissDraw.from(line: "VS Code didn't open Zeus."))
        func cards(_ plan: ActionMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(closed) == ["Didn't open", "Safari"])
        #expect(cards(quiet) == ["No response", "Music"])
        #expect(cards(site) == ["Couldn't open", "example.com"])
        #expect(cards(project) == ["Didn't open", "VS Code", "Zeus"])
        #expect(closed.boltCaption(at: 0) == "Didn't open")
        #expect(closed.boltCaption(at: 100) == "Safari")
        #expect(project.boltCaption(at: 100) == "Zeus")
        #expect(closed.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(closed.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankNameAndOtherLinesAreNotAMiss() {
        #expect(ActionMissDraw.from(line: " didn't open.") == nil)
        #expect(ActionMissDraw.from(line: "I couldn't open .") == nil)
        #expect(ActionMissDraw.from(line: "The AI failed; try again.") == nil)
        #expect(ActionMissDraw.from(line: "One moment.") == nil)
        #expect(ActionMissDraw.plan(label: "Didn't open", name: " ", extra: nil) == nil)
    }
}
