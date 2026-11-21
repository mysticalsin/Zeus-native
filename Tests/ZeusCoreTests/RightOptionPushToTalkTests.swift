import Foundation
import Testing
@testable import ZeusCore

/// Right Option is strict push-to-talk. Hold starts listening, release stops it, and nothing latches.
@Suite("Right Option strict push-to-talk")
struct RightOptionPushToTalkTests {
    @Test func holdingRightOptionStartsListeningAndARepeatDoesNotToggle() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
        #expect(machine.phase == .listening)
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)).isEmpty)
        #expect(machine.phase == .listening)
    }

    @Test func releasingRightOptionStopsListening() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.rightOption(down: false, otherTurnOpen: false)) == [.stop])
        #expect(machine.phase == .idle)
        #expect(machine.send(.rightOption(down: false, otherTurnOpen: false)).isEmpty)
    }

    @Test func aQuickTapStartsAndStopsAndNeverLatches() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.rightOption(down: false, otherTurnOpen: false)) == [.stop])
        #expect(machine.phase == .idle)
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.rightOption(down: false, otherTurnOpen: false)) == [.stop])
        #expect(machine.phase == .idle)
        #expect(machine.send(.otherKey).isEmpty)
        #expect(machine.phase == .idle)
    }

    @Test func optionWithAnotherKeyDoesNotCancelOrToggle() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.otherKey).isEmpty)
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)).isEmpty)
        #expect(machine.phase == .listening)
        #expect(machine.send(.rightOption(down: false, otherTurnOpen: false)) == [.stop])
        #expect(machine.phase == .idle)
    }

    @Test func leftOptionDoesNothing() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.leftOption(down: true)).isEmpty)
        #expect(machine.send(.leftOption(down: false)).isEmpty)
        #expect(machine.phase == .idle)
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.leftOption(down: true)).isEmpty)
        #expect(machine.send(.leftOption(down: false)).isEmpty)
        #expect(machine.phase == .listening)
    }

    @Test func eachYieldKeepsRightOptionQuiet() {
        let chat = VoiceKey.secondTalkKey(
            chosen: .rightOption, explicit: false, heard: .controlOption, dictation: .rightCommand,
            pointing: nil, polyglot: nil, voiceOverOn: false,
            carbonHolders: [("Chat", ChatHotkey.optionSpace.shortcut)])
        let pointing = VoiceKey.secondTalkKey(
            chosen: .rightOption, explicit: false, heard: .controlOption, dictation: .rightCommand,
            pointing: .rightOption, polyglot: nil, voiceOverOn: false, carbonHolders: [])
        let dictation = VoiceKey.secondTalkKey(
            chosen: .rightOption, explicit: false, heard: .controlOption, dictation: .rightOption,
            pointing: nil, polyglot: nil, voiceOverOn: false, carbonHolders: [])
        let polyglot = VoiceKey.secondTalkKey(
            chosen: .rightOption, explicit: false, heard: .controlOption, dictation: .rightCommand,
            pointing: nil, polyglot: .rightOption, voiceOverOn: false, carbonHolders: [])
        let heard = VoiceKey.effectiveTalkKey(chosen: .rightOption, dictation: nil, pointing: nil, voiceOverOn: true)
        let voiceOver = VoiceKey.secondTalkKey(
            chosen: .controlOption, explicit: true, heard: heard, dictation: nil, pointing: nil,
            polyglot: nil, voiceOverOn: true, carbonHolders: [])
        let yields = [chat, pointing, dictation, polyglot, voiceOver]
        #expect(yields.map(\.yieldsTo) == ["Chat", "Pointing", "Dictation", "Polyglot", "VoiceOver"])
        for yield in yields {
            var machine = RightOptionPushToTalk()
            machine.yieldedTo = RightOptionPushToTalk.yield(named: yield.yieldsTo)
            #expect(machine.yieldedTo != nil)
            #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)).isEmpty)
            #expect(machine.phase != .listening)
        }
        #expect(RightOptionPushToTalk.yield(named: "Talk to Zeus") == nil)
    }

    @Test func aPressDuringAnotherTurnDoesNotStart() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: true)).isEmpty)
        #expect(machine.phase != .listening)
        #expect(machine.send(.rightOption(down: false, otherTurnOpen: false)).isEmpty)
        #expect(machine.phase == .idle)
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
    }

    @Test func aLostKeyUpOnFocusChangeStopsListening() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.focusChanged) == [.stop])
        #expect(machine.phase != .listening)
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)).isEmpty)
        #expect(machine.phase != .listening)
        #expect(machine.send(.rightOption(down: false, otherTurnOpen: false)).isEmpty)
        #expect(machine.phase == .idle)
        #expect(machine.send(.rightOption(down: true, otherTurnOpen: false)) == [.start])
        #expect(machine.phase == .listening)
    }

    @Test func aLostKeyUpOnTheLiveFlagsStopsListening() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, at: 1, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.liveFlags(ShortcutModifiers(), at: 1.2)) == [.stop])
        #expect(machine.phase != .listening)
        #expect(machine.send(.liveFlags(.option, at: 1.4)).isEmpty)
        #expect(machine.send(.rightOption(down: false, at: 1.5, otherTurnOpen: false)).isEmpty)
        #expect(machine.phase == .idle)
    }

    @Test func theThreeSecondLookStopsWhenRightOptionIsUp() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, at: 0, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.look(at: 3, flags: .option)).isEmpty)
        #expect(machine.phase == .listening)
        #expect(machine.send(.look(at: 6, flags: ShortcutModifiers())) == [.stop])
        #expect(machine.phase != .listening)
    }

    @Test func theHoldStopsAtTheTalkLimit() {
        var machine = RightOptionPushToTalk()
        let cap = FastTier.conversationWindowSeconds
        #expect(machine.send(.rightOption(down: true, at: 10, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.look(at: 10 + cap - 0.001, flags: .option)).isEmpty)
        #expect(machine.phase == .listening)
        #expect(machine.send(.look(at: 10 + cap, flags: .option)) == [.stop])
        #expect(machine.phase != .listening)
    }

    @Test func secureInputStopsAndFailsClosed() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, at: 0, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.secureInput(false)).isEmpty)
        #expect(machine.phase == .listening)
        #expect(machine.send(.secureInput(nil)) == [.stop])
        #expect(machine.phase != .listening)
        #expect(machine.send(.rightOption(down: false, at: 1, otherTurnOpen: false)).isEmpty)
        #expect(machine.send(.rightOption(down: true, at: 2, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.secureInput(true)) == [.stop])
    }

    @Test func aScreenLockStopsTheHold() {
        var machine = RightOptionPushToTalk()
        #expect(machine.send(.rightOption(down: true, at: 0, otherTurnOpen: false)) == [.start])
        #expect(machine.send(.screenLocked) == [.stop])
        #expect(machine.phase != .listening)
        #expect(machine.send(.otherKey).isEmpty)
        #expect(machine.phase != .listening)
    }

    @Test func theRightOptionHintSaysHoldToTalkReleaseToStop() {
        let only = RightOptionPushToTalk.hint(talk: .rightOption, second: nil, dictationOn: false, dictation: nil)
        #expect(only == "hold to talk, release to stop")
        #expect(!only.contains("double-tap"))
        let beside = RightOptionPushToTalk.hint(talk: .controlOption, second: .rightOption, dictationOn: false, dictation: nil)
        #expect(beside.contains("hold to talk, release to stop"))
        #expect(beside.contains("double-tap to latch"))
        let other = RightOptionPushToTalk.hint(talk: .controlOption, second: .function, dictationOn: true, dictation: .rightCommand)
        #expect(other == "hold Control + Option to talk, double-tap to latch (or hold Fn (Globe)); dictation: hold Right Command")
    }
}
