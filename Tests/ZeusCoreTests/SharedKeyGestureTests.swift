import Testing
@testable import ZeusCore

@Suite struct SharedKeyGestureTests {
    @Test func holdDictates() {
        var g = SharedKeyGesture()
        g.keyDown(at: 0)
        #expect(g.holdTimerFired(at: 0.25) == .holdBegan)
        #expect(g.keyUp(at: 2) == .holdEnded)
    }

    @Test func doubleTapIsCommandMode() {
        var g = SharedKeyGesture()
        g.keyDown(at: 0)
        #expect(g.keyUp(at: 0.1) == nil)
        g.keyDown(at: 0.3)
        #expect(g.holdTimerFired(at: 0.25) == nil)
        #expect(g.keyUp(at: 0.4) == .doubleTap)
    }

    @Test func shortcutIsIgnored() {
        var g = SharedKeyGesture()
        g.keyDown(at: 0)
        #expect(g.otherKey() == nil)            // ⌘C
        #expect(g.holdTimerFired(at: 0.25) == nil)
        #expect(g.keyUp(at: 0.6) == nil)
        g.keyDown(at: 0.7)                       // a later single tap is not a double tap
        #expect(g.keyUp(at: 0.75) == nil)
    }

    @Test func shortcutAfterHoldCancelsDictation() {
        var g = SharedKeyGesture()
        g.keyDown(at: 0)
        #expect(g.holdTimerFired(at: 0.3) == .holdBegan)
        #expect(g.otherKey() == .holdCancelled)
        #expect(g.keyUp(at: 1) == nil)
    }

    @Test func slowSecondTapIsNotDoubleTap() {
        var g = SharedKeyGesture()
        g.keyDown(at: 0)
        _ = g.keyUp(at: 0.1)
        g.keyDown(at: 1)
        #expect(g.keyUp(at: 1.1) == nil)
    }
}
