import Testing
@testable import ZeusCore

struct MemoryUnreadDrawTests {
    @Test func anUnreadMemoryFileShowsUnread() throws {
        let plan = try #require(MemoryUnreadDraw.from(line: "I can't read my memory file, so I left it alone."))
        func cards(_ plan: MemoryUnreadDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Memory", "Unread"])
        #expect(plan.boltCaption(at: 0) == "Memory")
        #expect(plan.boltCaption(at: 100) == "Unread")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aSaveMissAndADeclinedStepAreNotUnread() {
        #expect(MemoryUnreadDraw.from(line: "") == nil)
        #expect(MemoryUnreadDraw.from(line: "I couldn't save that, so nothing changed.") == nil)
        #expect(MemoryUnreadDraw.from(line: "Got it. I'll remember that.") == nil)
        #expect(MemoryUnreadDraw.from(line: "Okay, I didn't click submit. I've stopped there.") == nil)
    }
}
