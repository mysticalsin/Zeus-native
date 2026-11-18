import Foundation
import Testing
@testable import ZeusCore

@Suite("Right Command tap")
struct RightCommandTapTests {
    @Test func soloTapTogglesListeningAndPlaysTheTalkCues() {
        var tap = RightCommandTap()
        #expect(tap.rightDown(at: 0, otherKeyDown: false).isEmpty)
        let started = tap.rightUp(at: 0.12)
        #expect(tap.listening)
        #expect(started == [.toggle(listening: true, cue: startCue)])
        let stopped = tap.rightUp(at: 1.2, afterDownAt: 1.05)
        #expect(!tap.listening)
        #expect(stopped == [.toggle(listening: false, cue: endCue)])
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

    @Test func toggleWhileListeningStops() {
        var tap = RightCommandTap()
        _ = tap.rightDown(at: 0, otherKeyDown: false)
        _ = tap.rightUp(at: 0.08)
        #expect(tap.listening)
        _ = tap.rightDown(at: 2, otherKeyDown: false)
        let stopped = tap.rightUp(at: 2.1)
        #expect(stopped == [.toggle(listening: false, cue: endCue)])
        #expect(!tap.listening)
    }

    @Test func aControlOptionHoldDiscardsAPendingRightCommandTap() {
        var tap = RightCommandTap()
        _ = tap.rightDown(at: 0, otherKeyDown: false)
        #expect(tap.holdOwnsKeyboard().isEmpty)
        #expect(tap.rightUp(at: 0.1).isEmpty)
        #expect(!tap.listening)
    }

    @Test func aMissingCueFileUsesTheNeutralMacSound() {
        var tap = RightCommandTap()
        let started = tap.rightUp(at: 0.1, afterDownAt: 0, fileIsReadable: { _ in false })
        #expect(started == [.toggle(listening: true, cue: TalkCuePlay(kind: .start, source: .system(TalkCueFiles.fallbackSystemSound)))])
    }

    @Test func aRejectedStartLeavesTheNextTapAbleToStart() {
        var tap = RightCommandTap()
        _ = tap.rightUp(at: 0.1, afterDownAt: 0)
        tap.noteStartRejected()
        #expect(!tap.listening)
        let again = tap.rightUp(at: 1.1, afterDownAt: 1)
        #expect(again == [.toggle(listening: true, cue: startCue)])
    }

    @Test func cuesStillPlayWhenReduceMotionIsOn() {
        #expect(RightCommandTap.playsAudio(reduceMotion: true))
        var tap = RightCommandTap()
        let started = tap.rightUp(at: 0.1, afterDownAt: 0, reduceMotion: true)
        #expect(started == [.toggle(listening: true, cue: startCue)])
    }

    private var startCue: TalkCuePlay {
        TalkCuePlay(kind: .start, source: .file(TalkCueFiles.startPath))
    }

    private var endCue: TalkCuePlay {
        TalkCuePlay(kind: .end, source: .file(TalkCueFiles.endPath))
    }
}
