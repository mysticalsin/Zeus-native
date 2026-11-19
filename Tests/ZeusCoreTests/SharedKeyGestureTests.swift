import Foundation
import Testing
@testable import ZeusCore

/// One key, two gestures (right Command by default): hold to dictate, double-tap to talk. The voice key machine runs
/// each side of the shared key as its own machine, and these tests feed the same keys to both
/// (docs/VOICE-KEY-MACHINE-PLAN.md part 5). The old gesture's outputs read: `holdBegan` is the dictation `.start` after
/// 0.25 s, `holdEnded` its `.send`, `holdCancelled` its `.cancel`, `doubleTap` the talk side's `.start`.
@Suite struct SharedKeyGestureTests {
    typealias Rig = VoiceKeyMachineTests.Rig
    private static let cmdR = VoiceKeyMachineTests.cmdR, c = VoiceKeyMachineTests.c

    private func makeDictation() -> Rig { Rig(Config(key: .rightCommand, role: .dictation, mode: .shared)) }
    private func makeTalk() -> Rig { Rig(Config(key: .rightCommand, role: .talk, mode: .shared)) }
    private typealias Config = VoiceKeyMachine.Config

    @Test func holdDictates() {
        var rig = makeDictation()
        #expect(rig.press(Self.cmdR, at: 0) == [.wake(after: 0.25)])
        #expect(rig.tick(at: 0.25) == [.start, .wake(after: 0.25)])
        #expect(rig.release(Self.cmdR, at: 2) == [.send])
    }

    @Test func doubleTapIsCommandMode() {
        var dictation = makeDictation(), talk = makeTalk()
        #expect(dictation.press(Self.cmdR, at: 0) == [.wake(after: 0.25)])
        #expect(talk.press(Self.cmdR, at: 0) == [])
        #expect(dictation.release(Self.cmdR, at: 0.1) == [])
        #expect(talk.release(Self.cmdR, at: 0.1) == [])
        #expect(dictation.press(Self.cmdR, at: 0.3) == [.wake(after: 0.25)])
        #expect(talk.press(Self.cmdR, at: 0.3) == [])
        #expect(dictation.tick(at: 0.25) == [], "the wake of the first press is not due for the second")
        #expect(talk.tick(at: 0.25) == [])
        #expect(dictation.release(Self.cmdR, at: 0.4) == [], "dictation never starts on a double tap")
        #expect(talk.release(Self.cmdR, at: 0.4) == [.start])
        #expect(talk.machine.isLatched)
    }

    @Test func shortcutIsIgnored() {
        var dictation = makeDictation(), talk = makeTalk()
        dictation.press(Self.cmdR, at: 0)
        talk.press(Self.cmdR, at: 0)
        #expect(dictation.type(Self.c, at: 0.05) == [])            // Command-C
        #expect(talk.type(Self.c, at: 0.05) == [])
        #expect(dictation.tick(at: 0.25) == [])
        #expect(talk.tick(at: 0.25) == [])
        dictation.untype(Self.c, at: 0.3)
        talk.untype(Self.c, at: 0.3)
        #expect(dictation.release(Self.cmdR, at: 0.6) == [])
        #expect(talk.release(Self.cmdR, at: 0.6) == [])
        dictation.press(Self.cmdR, at: 0.7)                          // a later single tap is not a double tap
        talk.press(Self.cmdR, at: 0.7)
        #expect(dictation.release(Self.cmdR, at: 0.75) == [])
        #expect(talk.release(Self.cmdR, at: 0.75) == [])
        #expect(!talk.machine.isLatched)
    }

    @Test func shortcutAfterHoldCancelsDictation() {
        var rig = makeDictation()
        rig.press(Self.cmdR, at: 0)
        #expect(rig.tick(at: 0.3) == [.start, .wake(after: 0.25)])
        #expect(rig.type(Self.c, at: 0.5) == [.cancel])
        rig.untype(Self.c, at: 0.6)
        #expect(rig.release(Self.cmdR, at: 1) == [])
    }

    @Test func slowSecondTapIsNotDoubleTap() {
        var dictation = makeDictation(), talk = makeTalk()
        dictation.press(Self.cmdR, at: 0)
        talk.press(Self.cmdR, at: 0)
        dictation.release(Self.cmdR, at: 0.1)
        talk.release(Self.cmdR, at: 0.1)
        dictation.press(Self.cmdR, at: 1)
        talk.press(Self.cmdR, at: 1)
        #expect(dictation.release(Self.cmdR, at: 1.1) == [])
        #expect(talk.release(Self.cmdR, at: 1.1) == [])
        #expect(!talk.machine.isLatched)
    }
}
