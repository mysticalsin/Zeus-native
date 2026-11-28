import Testing
@testable import ZeusCore

struct VolumeBlockDrawTests {
    @Test func aBlockedOutputShowsCantChange() throws {
        let plan = try #require(VolumeBlockDraw.from(line: VolumeBlockDraw.line))
        func cards(_ plan: VolumeBlockDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Volume", "Can't change"])
        #expect(plan.boltCaption(at: 0) == "Volume")
        #expect(plan.boltCaption(at: 100) == "Can't change")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func otherLinesAreNotABlockedVolume() {
        #expect(VolumeBlockDraw.from(line: "") == nil)
        #expect(VolumeBlockDraw.from(line: "Volume up") == nil)
        #expect(VolumeBlockDraw.from(line: "Safari didn't open.") == nil)
        #expect(VolumeBlockDraw.from(line: "This output doesn't let me change its volume") == nil)
    }
}
