import Testing
@testable import ZeusCore

struct MemoryUnchangedDrawTests {
    @Test func aMemoryThatCouldNotBeSavedShowsUnchanged() throws {
        let plan = try #require(MemoryUnchangedDraw.from(line: "I couldn't save that, so nothing changed."))
        func cards(_ plan: MemoryUnchangedDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Memory", "Unchanged"])
        #expect(plan.boltCaption(at: 0) == "Memory")
        #expect(plan.boltCaption(at: 100) == "Unchanged")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aKeptFactAndASavedReportAreNotUnchanged() {
        #expect(MemoryUnchangedDraw.from(line: "") == nil)
        #expect(MemoryUnchangedDraw.from(line: "Got it. I'll remember that.") == nil)
        #expect(MemoryUnchangedDraw.from(line: "I can't read my memory file, so I left it alone.") == nil)
        #expect(MemoryUnchangedDraw.from(line: "Done. The report is saved.") == nil)
    }
}
