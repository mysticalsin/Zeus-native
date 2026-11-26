import Testing
@testable import ZeusCore

@Suite("Mascot pose cycle")
struct MascotPoseCycleTests {
    @Test func eachStateKeepsItsPosesAndHold() {
        #expect(MascotPoseCycle.cycle(for: "idle") == MascotPoseCycle(poses: ["idle"], hold: 4))
        #expect(MascotPoseCycle.cycle(for: "listening") == MascotPoseCycle(poses: ["listening"], hold: 3))
        #expect(MascotPoseCycle.cycle(for: "thinking") == MascotPoseCycle(poses: ["thinking", "curious"], hold: 3.2))
        #expect(MascotPoseCycle.cycle(for: "speaking") == MascotPoseCycle(poses: ["welcome", "guiding"], hold: 1.8))
        #expect(MascotPoseCycle.cycle(for: "pointing") == MascotPoseCycle(poses: ["guiding"], hold: 2))
        #expect(MascotPoseCycle.cycle(for: "clicking") == MascotPoseCycle(poses: ["working", "organizing"], hold: 2.4))
        #expect(MascotPoseCycle.cycle(for: "typing") == MascotPoseCycle(poses: ["typing"], hold: 2.4))
        #expect(MascotPoseCycle.cycle(for: "browsing") == MascotPoseCycle(poses: ["searching", "curious"], hold: 2.4))
        #expect(MascotPoseCycle.cycle(for: "agent") == MascotPoseCycle(poses: ["working", "typing", "searching", "organizing", "carrying"], hold: 2.4))
        #expect(MascotPoseCycle.cycle(for: "approval") == MascotPoseCycle(poses: ["approval_wait"], hold: 4))
        #expect(MascotPoseCycle.cycle(for: "error") == MascotPoseCycle(poses: ["error", "confused"], hold: 2))
        #expect(MascotPoseCycle.cycle(for: "done") == MascotPoseCycle(poses: ["success", "celebrate"], hold: 1.8))
        #expect(MascotPoseCycle.cycle(for: "teleprompter") == MascotPoseCycle(poses: ["guiding", "curious"], hold: 3))
    }

    @Test func anUnknownStateUsesTheIdleRow() {
        #expect(MascotPoseCycle.cycle(for: "nope") == MascotPoseCycle(poses: ["idle"], hold: 4))
    }

    @Test func agentWorkHasAtLeastFourPoses() {
        #expect(MascotPoseCycle.cycle(for: "agent").poses.count >= 4)
    }
}
