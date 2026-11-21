import Foundation
import Testing
@testable import ZeusCore

@Suite("One press, one action")
struct KeyActionRouterTests {
    @Test func aRightCommandTapIsMurmurAndNotTalk() {
        var router = KeyActionRouter()
        #expect(router.send(.rightCommand(down: true, at: 0, otherKeyDown: false)).isEmpty)
        #expect(router.send(.rightCommand(down: false, at: 0.12, otherKeyDown: false)) == [.murmur])
    }

    @Test func holdingRightOptionTalksOnce() {
        var router = KeyActionRouter()
        #expect(router.send(.rightOption(down: true, at: 0, otherKeyDown: false)).isEmpty)
        #expect(router.send(.tick(at: KeyActionRouter.optionHold - 0.001)).isEmpty)
        #expect(router.send(.tick(at: KeyActionRouter.optionHold)) == [.talk])
        #expect(router.send(.tick(at: KeyActionRouter.optionHold + 0.2)).isEmpty)
        #expect(router.send(.rightOption(down: false, at: 1, otherKeyDown: false)).isEmpty)
    }

    @Test func leftCommandSpoilsTheTap() {
        var router = KeyActionRouter()
        #expect(router.send(.leftCommand(down: true, at: 0)).isEmpty)
        #expect(router.send(.rightCommand(down: true, at: 0.01, otherKeyDown: false)).isEmpty)
        #expect(router.send(.rightCommand(down: false, at: 0.1, otherKeyDown: false)).isEmpty)
    }

    @Test func aCommandTapDuringTalkDoesNotStartASecondAction() {
        var router = KeyActionRouter()
        _ = router.send(.rightOption(down: true, at: 0, otherKeyDown: false))
        #expect(router.send(.tick(at: KeyActionRouter.optionHold)) == [.talk])
        #expect(router.send(.rightCommand(down: true, at: 1, otherKeyDown: false)).isEmpty)
        #expect(router.send(.rightCommand(down: false, at: 1.1, otherKeyDown: false)).isEmpty)
    }

    @Test func aLostRightCommandKeyUpDoesNotSwallowTheNextTap() {
        var router = KeyActionRouter()
        _ = router.send(.rightCommand(down: true, at: 0, otherKeyDown: false))
        #expect(router.send(.hardwareRightCommandUp(at: 2)).isEmpty)
        #expect(router.phase == .idle)
        _ = router.send(.rightCommand(down: true, at: 3, otherKeyDown: false))
        #expect(router.send(.rightCommand(down: false, at: 3.1, otherKeyDown: false)) == [.murmur])
    }

    @Test func aRepeatWhileTheKeyIsDownDoesNotRestartTheTapClock() {
        var router = KeyActionRouter()
        _ = router.send(.rightCommand(down: true, at: 0, otherKeyDown: false))
        #expect(router.send(.rightCommand(down: true, at: 0.2, otherKeyDown: false)).isEmpty)
        #expect(router.send(.rightCommand(down: false, at: 0.35, otherKeyDown: false)).isEmpty)
    }

    @Test func oneEventNeverReturnsMurmurAndTalk() {
        var router = KeyActionRouter()
        let events: [KeyActionRouter.Event] = [
            .rightCommand(down: true, at: 0, otherKeyDown: false),
            .rightOption(down: true, at: 0.05, otherKeyDown: false),
            .tick(at: 0.1),
            .otherKey(at: 0.12),
            .rightCommand(down: false, at: 0.2, otherKeyDown: false),
            .rightOption(down: false, at: 0.4, otherKeyDown: false),
            .leftCommand(down: true, at: 1),
            .rightCommand(down: true, at: 1.1, otherKeyDown: true),
            .cancel,
            .tick(at: 2),
            .hardwareRightCommandUp(at: 3),
            .rightOption(down: true, at: 4, otherKeyDown: false),
            .tick(at: 4.25),
            .tick(at: 4.5),
        ]
        for event in events {
            let actions = router.send(event)
            #expect(actions.count <= 1)
            #expect(actions != [.murmur, .talk])
            #expect(actions != [.talk, .murmur])
        }
    }
}

@Suite("Modifier key-up and key repeat")
struct ModifierFlagsRepeatTests {
    @Test func aRepeatWhileBothCommandKeysAreDownStaysDownWhenHardwareAgrees() {
        let still = ModifierFlagsRepeat.isHardwareStillDown(
            keyCode: 54, modifiers: .command, deviceKeys: [54, 55], hardwareDown: { $0 == 54 || $0 == 55 })
        #expect(still)
    }

    @Test func aLoneKeyRepeatIsNotThisCase() {
        let lone = ModifierFlagsRepeat.isHardwareStillDown(
            keyCode: 54, modifiers: .command, deviceKeys: [54], hardwareDown: { _ in true })
        #expect(!lone)
    }

    @Test func hardwareUpIsAReleaseEvenWhenTheFlagStays() {
        let released = ModifierFlagsRepeat.isHardwareStillDown(
            keyCode: 54, modifiers: .command, deviceKeys: [54, 55], hardwareDown: { $0 == 55 })
        #expect(!released)
    }

    @Test func aMissedRightOptionUpWhileLeftOptionStaysIsOneFlagsEvent() {
        let events = ModifierFlagsRepeat.missedReleases(
            deviceKeys: [58, 61], flagModifiers: .option, hardwareDown: { $0 == 58 })
        #expect(events == [.flags(keyCode: 61, modifiers: .option)])
    }

    @Test func aMissedRightCommandUpClearsTheFlagWhenNothingElseHoldsIt() {
        let events = ModifierFlagsRepeat.missedReleases(
            deviceKeys: [54], flagModifiers: .command, hardwareDown: { _ in false })
        #expect(events == [.flags(keyCode: 54, modifiers: [])])
    }

    @Test func theGlobeKeyIsReportedOnce() {
        let events = ModifierFlagsRepeat.missedReleases(
            deviceKeys: [63], flagModifiers: .function, hardwareDown: { _ in false })
        #expect(events == [.flags(keyCode: 63, modifiers: [])])
    }

    /// Sentinel L-1 #112. The repeat-drop path reads the hardware and, when that read is still
    /// "down", the monitor keeps the key until a later tick. Right Option must not enter it.
    @Test func anUnrelatedModifierNeverTakesTheRepeatDropPathAndRightOptionStopsAtTheKeyUp() {
        var reads: [UInt16] = []
        func hardware(_ code: UInt16) -> Bool {
            reads.append(code)
            return true
        }

        let rightOption = ModifierFlagsRepeat.isHardwareStillDown(
            keyCode: 61, modifiers: .option, deviceKeys: [58, 61], hardwareDown: hardware)
        #expect(reads.isEmpty, "Right Option never takes the repeat-drop path")
        #expect(!rightOption)
        reads.removeAll()
        let shift = ModifierFlagsRepeat.isHardwareStillDown(
            keyCode: 60, modifiers: .shift, deviceKeys: [56, 60], hardwareDown: hardware)
        #expect(reads.isEmpty, "Shift is not a key this path owns")
        #expect(!shift)

        reads.removeAll()
        #expect(ModifierFlagsRepeat.isHardwareStillDown(
            keyCode: 54, modifiers: .command, deviceKeys: [54, 55], hardwareDown: hardware))
        #expect(reads == [54], "Right Command still asks the hardware")
        reads.removeAll()
        #expect(ModifierFlagsRepeat.isHardwareStillDown(
            keyCode: 55, modifiers: .command, deviceKeys: [54, 55], hardwareDown: hardware))
        #expect(reads == [55], "Left Command still asks the hardware")

        var state = ShortcutState()
        state.apply(.flags(keyCode: 58, modifiers: [.option]))
        state.apply(.flags(keyCode: 61, modifiers: [.option]))
        let releaseAt = 0.40
        let laterTick = 0.70
        let release = ShortcutEvent.flags(keyCode: 61, modifiers: [.option])
        reads.removeAll()
        let dropped = ModifierFlagsRepeat.isHardwareStillDown(
            keyCode: 61, modifiers: .option, deviceKeys: state.deviceKeys, hardwareDown: hardware)
        var stoppedAt: TimeInterval?
        if !dropped {
            state.apply(release)
            stoppedAt = releaseAt
        } else {
            let caughtUp = ModifierFlagsRepeat.missedReleases(
                deviceKeys: state.deviceKeys, flagModifiers: state.flagModifiers, hardwareDown: { $0 != 61 })
            for event in caughtUp { state.apply(event) }
            if !state.deviceKeys.contains(61) { stoppedAt = laterTick }
        }
        #expect(reads.isEmpty, "the key-up does not wait on a hardware read")
        #expect(stoppedAt == releaseAt, "Right Option stops at the key-up, not on a later tick")
        #expect(!state.deviceKeys.contains(61))
        #expect(state.deviceKeys.contains(58), "Left Option still holds the flag")
    }
}
