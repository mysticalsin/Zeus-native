import Foundation
import Testing
@testable import ZeusCore

@Suite("Tab hold")
struct TabHoldPolicyTests {
    private let start = Date(timeIntervalSince1970: 2_000)

    @Test func tabDownModifiersAndReleaseReachTheGate() {
        var gate = TabHoldGate()
        #expect(TabHoldPolicy.tabDown(&gate, at: start, modifiersHeld: true, isRepeat: false).isEmpty)
        #expect(TabHoldPolicy.checkDue(&gate, at: start.addingTimeInterval(0.5)).isEmpty)

        #expect(TabHoldPolicy.tabDown(&gate, at: start, modifiersHeld: false, isRepeat: false) == [.scheduleCheck])
        #expect(TabHoldPolicy.otherKey(&gate) == [.cancelPending])
        #expect(TabHoldPolicy.checkDue(&gate, at: start.addingTimeInterval(0.5)).isEmpty)

        #expect(TabHoldPolicy.tabDown(&gate, at: start, modifiersHeld: false, isRepeat: false) == [.scheduleCheck])
        #expect(TabHoldPolicy.tabUp(&gate) == [.cancelPending])

        #expect(TabHoldPolicy.tabDown(&gate, at: start, modifiersHeld: false, isRepeat: false) == [.scheduleCheck])
        #expect(TabHoldPolicy.checkDue(&gate, at: start.addingTimeInterval(0.45)) == [.revealStrip])
        #expect(TabHoldPolicy.tabUp(&gate) == [.cancelPending, .fadeStrip])

        #expect(TabHoldPolicy.tabDown(&gate, at: start.addingTimeInterval(1), modifiersHeld: false, isRepeat: false) == [.scheduleCheck])
        #expect(TabHoldPolicy.checkDue(&gate, at: start.addingTimeInterval(1.5)) == [.revealStrip])
    }

    @Test func aRepeatOrAModifierFadesAStripThatIsAlreadyShowing() {
        var gate = TabHoldGate()
        _ = TabHoldPolicy.tabDown(&gate, at: start, modifiersHeld: false, isRepeat: false)
        #expect(TabHoldPolicy.checkDue(&gate, at: start.addingTimeInterval(0.45)) == [.revealStrip])
        #expect(TabHoldPolicy.tabDown(&gate, at: start.addingTimeInterval(0.5), modifiersHeld: false, isRepeat: true) == [.cancelPending, .fadeStrip])

        _ = TabHoldPolicy.tabDown(&gate, at: start, modifiersHeld: false, isRepeat: false)
        _ = TabHoldPolicy.checkDue(&gate, at: start.addingTimeInterval(0.45))
        #expect(TabHoldPolicy.flagsChanged(&gate, modifiersHeld: true) == [.cancelPending, .fadeStrip])
        #expect(TabHoldPolicy.flagsChanged(&gate, modifiersHeld: true).isEmpty)
    }
}
