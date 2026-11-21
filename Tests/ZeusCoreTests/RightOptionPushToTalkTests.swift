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
}
