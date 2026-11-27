import Testing
@testable import ZeusCore

struct LockFailDrawTests {
    @Test func aRefusedLockShowsCant() throws {
        let plan = try #require(LockFailDraw.from(line: LockFailDraw.line))
        func cards(_ plan: LockFailDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Lock", "Can't"])
        #expect(plan.boltCaption(at: 0) == "Lock")
        #expect(plan.boltCaption(at: 100) == "Can't")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherLinesAreNotALockRefusal() {
        #expect(LockFailDraw.from(line: "") == nil)
        #expect(LockFailDraw.from(line: "Lock screen") == nil)
        #expect(LockFailDraw.from(line: "I couldn't open example.com.") == nil)
        #expect(LockFailDraw.from(line: "This output doesn't let me change its volume.") == nil)
    }
}
