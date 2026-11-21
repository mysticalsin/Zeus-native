import Foundation
import Testing
@testable import ZeusCore

@Suite("Shift peek hold")
struct ShiftPeekPolicyTests {
    @Test func aSecondShiftHoldFiresAfterRelease() {
        var gate = ShiftPeekGate()
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(ShiftPeekPolicy.shiftDown(&gate, at: start) == [.scheduleCheck])
        #expect(ShiftPeekPolicy.checkDue(&gate, at: start.addingTimeInterval(0.5)) == [.showCrest])
        let revealed = gate.release()
        #expect(revealed)
        #expect(ShiftPeekPolicy.shiftedUp(revealed: revealed) == [.cancelPending, .fadeExistingCrest])
        #expect(ShiftPeekPolicy.shiftDown(&gate, at: start.addingTimeInterval(1)) == [.scheduleCheck])
        #expect(ShiftPeekPolicy.checkDue(&gate, at: start.addingTimeInterval(1.6)) == [.showCrest])
    }

    @Test func releasingBeforeTheHoldFadesNothing() {
        var gate = ShiftPeekGate()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = ShiftPeekPolicy.shiftDown(&gate, at: start)
        #expect(ShiftPeekPolicy.checkDue(&gate, at: start.addingTimeInterval(0.3)).isEmpty)
        let revealed = gate.release()
        #expect(!revealed)
        #expect(ShiftPeekPolicy.shiftedUp(revealed: revealed) == [.cancelPending])
    }

    @Test func anotherKeyCancelsThePendingHold() {
        var gate = ShiftPeekGate()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = ShiftPeekPolicy.shiftDown(&gate, at: start)
        #expect(ShiftPeekPolicy.otherKey(&gate) == [.cancelPending])
        #expect(ShiftPeekPolicy.checkDue(&gate, at: start.addingTimeInterval(0.6)).isEmpty)
    }
}
