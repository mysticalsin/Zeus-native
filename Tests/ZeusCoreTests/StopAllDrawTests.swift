import Testing
@testable import ZeusCore

struct StopAllDrawTests {
    @Test func namesAndAnEmptyStop() throws {
        let halted = try #require(StopAllDraw.halted(names: ["Claude", "Codex", "Cursor"]))
        let one = try #require(StopAllDraw.halted(names: [" ", "Claude"]))
        let unnamed = try #require(StopAllDraw.halted(names: [" ", ""]))
        let idle = try #require(StopAllDraw.idle())
        func cards(_ plan: StopAllDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(halted) == ["Stop", "Claude", "Codex"])
        #expect(halted.boltCaption(at: 0) == "Stop")
        #expect(halted.boltCaption(at: ExplainBeatSchedule.gap) == "Claude")
        #expect(halted.boltCaption(at: 100) == "Codex")
        #expect(halted.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(halted.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 230))
        #expect(cards(one) == ["Stop", "Claude"])
        #expect(cards(unnamed) == ["Stop", "Agents"])
        #expect(cards(idle) == ["Stop", "Nothing"])
        #expect(idle.boltCaption(at: 100) == "Nothing")
    }
}
