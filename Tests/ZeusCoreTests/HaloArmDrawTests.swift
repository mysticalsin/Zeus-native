import Testing
@testable import ZeusCore

struct HaloArmDrawTests {
    private func cards(_ plan: HaloArmDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theArmAndIslandFollowReach() {
        let usual = HaloArmDraw.plan(arm: "Medium", island: "Black")
        #expect(cards(usual) == ["Reach", "Arm: Medium", "Island: Black"])
        #expect(HaloArmAsk.line(arm: "Medium", island: "Black") == "The halo arm is Medium, and the island is Black.")
        #expect(usual.boltCaption(at: 0) == "Reach")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Island: Black")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(HaloArmAsk.line(arm: "Extra wide", island: "Transparent") == "The halo arm is Extra wide, and the island is Transparent.")
        #expect(cards(HaloArmDraw.plan(arm: "Narrow", island: "Black")) == ["Reach", "Arm: Narrow", "Island: Black"])
        #expect(cards(HaloArmDraw.plan(arm: "Huge", island: "Black")) == ["Reach", "Can't"])
        #expect(HaloArmAsk.line(arm: "Medium", island: "Glass") == "I can't read the halo arm.")
    }

    @Test func theLightPictureStaysOffThisAsk() {
        #expect(HaloArmAsk.matches("how's the halo arm"))
        #expect(HaloArmAsk.matches("Hey Zeus, what's the island background?"))
        #expect(HaloArmAsk.matches("halo arm settings"))
        #expect(!HaloArmAsk.matches("what's the halo"))
        #expect(!HaloArmAsk.matches("how's the halo"))
        #expect(!HaloArmAsk.matches("which everyday lights"))
        #expect(!HaloArmAsk.matches("how's the notch close"))
    }
}
