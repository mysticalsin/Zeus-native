import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing key gesture")
struct PointingKeyGestureTests {
    private let control = ShortcutEvent.flags(keyCode: 59, modifiers: [.control])
    private let controlOption = ShortcutEvent.flags(keyCode: 58, modifiers: [.control, .option])

    private func hold(_ gesture: inout PointingKeyGesture, at time: Double = 0) -> PointingKeyGesture.Output? {
        _ = gesture.feed(control, at: time)
        return gesture.feed(controlOption, at: time + 0.01)
    }

    @Test func holdStartsImmediately() {
        var gesture = PointingKeyGesture()
        #expect(gesture.feed(control, at: 0) == nil)
        #expect(gesture.feed(controlOption, at: 0.01) == .began)
        #expect(gesture.isActive)
    }

    @Test func releasingAChordKeyEndsTheHold() {
        var gesture = PointingKeyGesture()
        _ = hold(&gesture)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: [.control]), at: 1) == .ended)
        #expect(gesture.feed(.flags(keyCode: 59, modifiers: []), at: 1.1) == nil)
        #expect(!gesture.isActive)
    }

    @Test func chatHotkeySpaceSpoilsAndCancelsWithoutSubmit() {
        var gesture = PointingKeyGesture()
        _ = hold(&gesture)
        #expect(gesture.feed(.keyDown(keyCode: 49, modifiers: [.control, .option]), at: 0.5) == .cancelled)
        // Nothing ends or restarts the turn while the modifiers are still down.
        #expect(gesture.feed(.keyUp(keyCode: 49), at: 0.6) == nil)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: [.control]), at: 0.7) == nil)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: [.control, .option]), at: 0.8) == nil)
        #expect(gesture.feed(.flags(keyCode: 58, modifiers: []), at: 0.9) == nil)
        // A clean press after a full release works again.
        #expect(hold(&gesture, at: 2) == .began)
    }

    @Test func commandJoiningCancels() {
        var gesture = PointingKeyGesture()
        _ = hold(&gesture)
        #expect(gesture.feed(.flags(keyCode: 55, modifiers: [.control, .option, .command]), at: 0.4) == .cancelled)
        #expect(gesture.feed(.flags(keyCode: 55, modifiers: [.control, .option]), at: 0.5) == nil)
        #expect(!gesture.isActive)
    }

    @Test func voiceOverBlocksControlOption() {
        var gesture = PointingKeyGesture()
        _ = gesture.feed(control, at: 0, voiceOverOn: true)
        #expect(gesture.feed(controlOption, at: 0.01, voiceOverOn: true) == nil)
        #expect(gesture.blockedByVoiceOver)
        #expect(!gesture.isActive)
    }

    @Test func aConfiguredSingleKeyShortcutWorks() {
        var gesture = PointingKeyGesture(shortcut: .rightOption)
        #expect(gesture.feed(.flags(keyCode: 61, modifiers: [.option]), at: 0) == .began)
        #expect(gesture.feed(.flags(keyCode: 61, modifiers: []), at: 1) == .ended)
    }

    @Test func escapeWithoutAHoldInterruptsSpeech() {
        var gesture = PointingKeyGesture()
        #expect(gesture.feed(.keyDown(keyCode: 53, modifiers: []), at: 0) == .escape)
    }

    @Test func twoQuickControlTapsAreDetectedButAChordIsNot() {
        var gesture = PointingKeyGesture()
        #expect(gesture.feed(control, at: 0) == nil)
        #expect(gesture.feed(.flags(keyCode: 59, modifiers: []), at: 0.1) == nil)
        #expect(gesture.feed(control, at: 0.2) == nil)
        #expect(gesture.feed(.flags(keyCode: 59, modifiers: []), at: 0.3) == .doubleTapControl)

        var chord = PointingKeyGesture()
        _ = hold(&chord, at: 0)
        _ = chord.feed(.flags(keyCode: 58, modifiers: [.control]), at: 0.1)
        _ = chord.feed(.flags(keyCode: 59, modifiers: []), at: 0.15)
        _ = chord.feed(control, at: 0.2)
        #expect(chord.feed(.flags(keyCode: 59, modifiers: []), at: 0.3) == nil)
    }

    @Test func aSlowControlPressIsNotATap() {
        var gesture = PointingKeyGesture()
        _ = gesture.feed(control, at: 0)
        _ = gesture.feed(.flags(keyCode: 59, modifiers: []), at: 1)
        _ = gesture.feed(control, at: 1.1)
        #expect(gesture.feed(.flags(keyCode: 59, modifiers: []), at: 1.2) == nil)
    }
}
