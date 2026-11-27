import Testing
@testable import ZeusCore

struct FileFoundDrawTests {
    @Test func aFoundFileAndAMissNameTheCard() throws {
        let found = try #require(FileFoundDraw.plan(name: "Quarterly report"))
        let missing = try #require(FileFoundDraw.missing())
        func cards(_ plan: FileFoundDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(found) == ["File", "Quarterly report"])
        #expect(found.boltCaption(at: 0) == "File")
        #expect(found.boltCaption(at: 100) == "Quarterly report")
        #expect(found.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(found.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(missing) == ["File", "Not found"])
        #expect(missing.boltCaption(at: 100) == "Not found")
    }

    @Test func aBlankNameIsNotDrawn() {
        #expect(FileFoundDraw.plan(name: "") == nil)
        #expect(FileFoundDraw.plan(name: " ") == nil)
        #expect(FileFoundDraw.plan(name: "\n") == nil)
    }
}
