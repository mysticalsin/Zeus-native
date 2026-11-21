import Foundation
import Testing
@testable import ZeusCore

@Suite("Right Command tap")
struct RightCommandTapTests {
    @Test func aSoloTapAsksForMurmurAndDoesNotArmTalk() {
        var tap = RightCommandTap()
        #expect(tap.rightDown(at: 0, otherKeyDown: false).isEmpty)
        let started = tap.rightUp(at: 0.12)
        #expect(started == [.murmur])
        #expect(!tap.listening)
        let again = tap.rightUp(at: 1.2, afterDownAt: 1.05)
        #expect(again == [.murmur])
        #expect(!tap.listening)
    }

    @Test func leftCommandHeldAcrossARightCommandTapDoesNotStartListening() {
        var tap = RightCommandTap()
        #expect(tap.leftDown(at: 0).isEmpty)
        #expect(tap.rightDown(at: 0.01, otherKeyDown: false).isEmpty)
        #expect(tap.rightUp(at: 0.12).isEmpty)
        #expect(!tap.listening)
    }

    @Test func aSoloRightCommandTapDoesNotArmTalk() {
        var tap = RightCommandTap()
        #expect(tap.rightDown(at: 0, otherKeyDown: false).isEmpty)
        _ = tap.rightUp(at: 0.12)
        #expect(!tap.listening)
    }

    @Test func chordedOrLongHeldOrLeftCommandDoesNothing() {
        var chord = RightCommandTap()
        _ = chord.rightDown(at: 0, otherKeyDown: false)
        #expect(chord.otherKey().isEmpty)
        #expect(chord.rightUp(at: 0.1).isEmpty)
        #expect(!chord.listening)

        var alreadyChorded = RightCommandTap()
        #expect(alreadyChorded.rightDown(at: 0, otherKeyDown: true).isEmpty)
        #expect(alreadyChorded.rightUp(at: 0.1).isEmpty)
        #expect(!alreadyChorded.listening)

        var held = RightCommandTap()
        _ = held.rightDown(at: 0, otherKeyDown: false)
        #expect(held.rightUp(at: RightCommandTap.maximumTap + 0.05).isEmpty)
        #expect(!held.listening)

        var left = RightCommandTap()
        #expect(left.leftDown(at: 0).isEmpty)
        #expect(left.leftUp(at: 0.1).isEmpty)
        #expect(!left.listening)
    }

    @Test func aSecondTapIsAnotherMurmurNotATalkStop() {
        var tap = RightCommandTap()
        _ = tap.rightDown(at: 0, otherKeyDown: false)
        #expect(tap.rightUp(at: 0.08) == [.murmur])
        #expect(!tap.listening)
        _ = tap.rightDown(at: 2, otherKeyDown: false)
        #expect(tap.rightUp(at: 2.1) == [.murmur])
        #expect(!tap.listening)
    }

    @Test func aControlOptionHoldDiscardsAPendingRightCommandTap() {
        var tap = RightCommandTap()
        _ = tap.rightDown(at: 0, otherKeyDown: false)
        #expect(tap.holdOwnsKeyboard().isEmpty)
        #expect(tap.rightUp(at: 0.1).isEmpty)
        #expect(!tap.listening)
    }

    @Test func aTapDoesNotCarryATalkCue() {
        var tap = RightCommandTap()
        let started = tap.rightUp(at: 0.1, afterDownAt: 0, fileIsReadable: { _ in false })
        #expect(started == [.murmur])
    }

    @Test func aRefusedTalkFlagDoesNotTurnTheNextTapIntoAStop() {
        var tap = RightCommandTap()
        _ = tap.rightUp(at: 0.1, afterDownAt: 0)
        tap.noteSession(listening: true)
        tap.noteStartRejected()
        #expect(!tap.listening)
        #expect(tap.rightUp(at: 1.1, afterDownAt: 1) == [.murmur])
    }

    @Test func reduceMotionDoesNotChangeTheTap() {
        #expect(RightCommandTap.playsAudio(reduceMotion: true))
        var tap = RightCommandTap()
        let started = tap.rightUp(at: 0.1, afterDownAt: 0, reduceMotion: true)
        #expect(started == [.murmur])
    }

    @Test func aMissedKeyUpLetsTheNextTapStartMurmur() {
        var tap = RightCommandTap()
        _ = tap.rightDown(at: 0, otherKeyDown: false)
        #expect(tap.hardwareRightCommandUp(at: 1).isEmpty)
        _ = tap.rightDown(at: 2, otherKeyDown: false)
        #expect(tap.rightUp(at: 2.1) == [.murmur])
    }

    @Test func theTapBoundaryIsClosedAtTheMaximum() {
        var inside = RightCommandTap()
        _ = inside.rightDown(at: 0, otherKeyDown: false)
        #expect(inside.rightUp(at: RightCommandTap.maximumTap) == [.murmur])
        var outside = RightCommandTap()
        _ = outside.rightDown(at: 0, otherKeyDown: false)
        #expect(outside.rightUp(at: RightCommandTap.maximumTap + 0.001).isEmpty)
    }
}
