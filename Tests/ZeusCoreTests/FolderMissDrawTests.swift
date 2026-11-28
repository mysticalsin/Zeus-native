import Testing
@testable import ZeusCore

struct FolderMissDrawTests {
    @Test func aMissingFolderShowsItsName() throws {
        let plan = try #require(FolderMissDraw.from(line: "I can't find the folder Notes."))
        func cards(_ plan: FolderMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Folder", "Notes"])
        #expect(plan.boltCaption(at: 0) == "Folder")
        #expect(plan.boltCaption(at: 100) == "Notes")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aDriveTargetAndAProjectAreNotThisFolder() {
        #expect(FolderMissDraw.from(line: "") == nil)
        #expect(FolderMissDraw.from(line: "I can't find the folder.") == nil)
        #expect(FolderMissDraw.from(line: "I can't find the folder .") == nil)
        #expect(FolderMissDraw.from(line: "I couldn't find \u{201C}Save\u{201D}.") == nil)
        #expect(FolderMissDraw.from(line: "I couldn't find a project called Zeus.") == nil)
        #expect(FolderMissDraw.from(line: "I don't know the key return.") == nil)
        #expect(FolderMissDraw.from(line: "Did you mean Zeus or ZeusApp?") == nil)
    }
}
