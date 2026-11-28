import Testing
@testable import ZeusCore

struct ProjectMissDrawTests {
    @Test func aMissingProjectShowsItsName() throws {
        let plan = try #require(ProjectMissDraw.from(line: "I couldn't find a project called Zeus."))
        func cards(_ plan: ProjectMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Project", "Zeus"])
        #expect(plan.boltCaption(at: 0) == "Project")
        #expect(plan.boltCaption(at: 100) == "Zeus")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        let long = "I couldn't find a project called " + String(repeating: "North ", count: 20) + "."
        let clipped = try #require(ProjectMissDraw.from(line: long))
        #expect(clipped.name.count == TalkDraw.maxTextCharacters)
        #expect(clipped.boltCaption(at: 100).count <= 40)
    }

    @Test func aBlankNameAndOtherLinesAreNotAMiss() {
        #expect(ProjectMissDraw.from(line: "") == nil)
        #expect(ProjectMissDraw.from(line: "I couldn't find a project called .") == nil)
        #expect(ProjectMissDraw.from(line: "I couldn't find a project called") == nil)
        #expect(ProjectMissDraw.from(line: "Opening Zeus in Cursor.") == nil)
        #expect(ProjectMissDraw.from(line: "Okay, I won't start it.") == nil)
    }
}
