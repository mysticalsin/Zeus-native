import Foundation
import Testing
@testable import ZeusCore

/// The facts both key reducers read: one picture of the keyboard, four plain answers about one shortcut.
@Suite struct KeyFactsTests {
    private static let ctrlL: UInt16 = 59, optL: UInt16 = 58, shiftL: UInt16 = 56, cmdL: UInt16 = 55, cmdR: UInt16 = 54
    private static let fn: UInt16 = 63, left: UInt16 = 123, space: UInt16 = 49, t: UInt16 = 17

    private func facts(_ events: [ShortcutEvent], _ key: Shortcut, chord: UInt16? = nil) -> KeyFacts {
        var state = ShortcutState()
        for event in events { state.apply(event) }
        return KeyFacts(of: state, key: key, chord: chord)
    }

    private let ctrl: ShortcutEvent = .flags(keyCode: ctrlL, modifiers: .control)
    private let ctrlOpt: ShortcutEvent = .flags(keyCode: optL, modifiers: [.control, .option])

    // MARK: Modifier-only key

    @Test func aModifierOnlyKeyIsDownWhenEveryModifierIs() {
        #expect(!facts([], .controlOption).ownDown)
        #expect(!facts([ctrl], .controlOption).ownDown)
        let both = facts([ctrl, ctrlOpt], .controlOption)
        #expect(both.ownDown && !both.foreignModifier && !both.foreignKey && !both.allUp)
    }

    @Test func anExtraModifierIsForeignAndFnIsOneToo() {
        let withShift = facts([ctrl, ctrlOpt, .flags(keyCode: Self.shiftL, modifiers: [.control, .option, .shift])], .controlOption)
        #expect(withShift.ownDown && withShift.foreignModifiers == .shift && withShift.foreignModifier)
        let withFn = facts([ctrl, ctrlOpt, .flags(keyCode: Self.fn, modifiers: [.control, .option, .function])], .controlOption)
        #expect(withFn.foreignModifiers == .function, "Fn joining a modifier-only key is a different chord")
    }

    @Test func anOrdinaryKeyOrASpoiledChordIsAForeignKey() {
        let typed = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.left, modifiers: [.control, .option, .function])], .controlOption)
        #expect(typed.foreignKey && typed.ownDown)
        let released = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.left, modifiers: [.control, .option]), .keyUp(keyCode: Self.left)],
                             .controlOption)
        #expect(released.foreignKey, "the chord stays spoiled until every modifier is up")
        let clear = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.left, modifiers: [.control, .option]), .keyUp(keyCode: Self.left),
                           .flags(keyCode: Self.ctrlL, modifiers: .option), .flags(keyCode: Self.optL, modifiers: [])], .controlOption)
        #expect(!clear.foreignKey && clear.allUp)
    }

    // MARK: Sided key

    @Test func aSidedKeyNeedsItsOwnPhysicalKeyAndTheOtherSideIsForeign() {
        let leftOnly = facts([.flags(keyCode: Self.cmdL, modifiers: .command)], .rightCommand)
        #expect(!leftOnly.ownDown && leftOnly.otherSideDown && leftOnly.foreignModifier, "Left Command alone is not the key, and is foreign to it")
        let rightOnly = facts([.flags(keyCode: Self.cmdR, modifiers: .command)], .rightCommand)
        #expect(rightOnly.ownDown && !rightOnly.foreignModifier)
        let both = facts([.flags(keyCode: Self.cmdR, modifiers: .command), .flags(keyCode: Self.cmdL, modifiers: .command)], .rightCommand)
        #expect(both.ownDown && both.otherSideDown && both.foreignModifier, "Left Command beside Right Command is foreign")
        let leftLetGo = facts([.flags(keyCode: Self.cmdR, modifiers: .command), .flags(keyCode: Self.cmdL, modifiers: .command),
                               .flags(keyCode: Self.cmdL, modifiers: .command)], .rightCommand)
        #expect(leftLetGo.ownDown && !leftLetGo.otherSideDown)
    }

    // MARK: Keyed key

    @Test func aKeyedKeyNeedsItsKeyCodeAndTreatsAnotherKeyAsForeign() {
        let optionSpace = Shortcut(keyCode: Self.space, modifiers: .option)
        let option: ShortcutEvent = .flags(keyCode: Self.optL, modifiers: .option)
        #expect(!facts([option], optionSpace).ownDown)
        let held = facts([option, .keyDown(keyCode: Self.space, modifiers: .option)], optionSpace)
        #expect(held.ownDown && !held.foreignKey && !held.foreignModifier)
        let rollover = facts([.keyDown(keyCode: 0, modifiers: []), option, .keyDown(keyCode: Self.space, modifiers: .option)], optionSpace)
        #expect(rollover.ownDown && rollover.foreignKey, "a key still down from before is foreign")
        let command = facts([option, .flags(keyCode: Self.cmdL, modifiers: [.option, .command]),
                             .keyDown(keyCode: Self.space, modifiers: [.option, .command])], optionSpace)
        #expect(command.foreignModifiers == .command)
    }

    @Test func fnIsNotForeignToAKeyedKeyThatDoesNotAskForIt() {
        let controlOptionLeft = Shortcut(keyCode: Self.left, modifiers: [.control, .option])
        let held = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.left, modifiers: [.control, .option, .function])], controlOptionLeft)
        #expect(held.ownDown && !held.foreignModifier)
        let globe = Shortcut(keyCode: Self.t, modifiers: .function)
        let asked = facts([.flags(keyCode: Self.fn, modifiers: .function), .keyDown(keyCode: Self.t, modifiers: .function)], globe)
        #expect(asked.ownDown && !asked.foreignModifier)
    }

    // MARK: A chord key beside a modifier-only key

    @Test func aChordKeyJoiningTheOwnSetIsNotForeign() {
        let joined = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.space, modifiers: [.control, .option])], .controlOption, chord: Self.space)
        #expect(joined.ownDown && joined.chordDown && !joined.foreignKey && !joined.foreignModifier)
        let released = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.space, modifiers: [.control, .option]), .keyUp(keyCode: Self.space)],
                             .controlOption, chord: Self.space)
        #expect(released.ownDown && !released.chordDown && !released.foreignKey, "letting go of the chord key leaves the hold clean")
    }

    @Test func aChordKeyWithShiftOrAnotherKeyIsForeign() {
        let shift = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.space, modifiers: [.control, .option]),
                           .flags(keyCode: Self.shiftL, modifiers: [.control, .option, .shift])], .controlOption, chord: Self.space)
        #expect(shift.chordDown && shift.foreignModifiers == .shift)
        let other = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.space, modifiers: [.control, .option]),
                           .keyDown(keyCode: Self.t, modifiers: [.control, .option])], .controlOption, chord: Self.space)
        #expect(other.foreignKey && other.chordDown)
    }

    @Test func aKeyThatSpoiledTheChordStaysForeignAfterItIsUp() {
        let tUp = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.space, modifiers: [.control, .option]),
                         .keyDown(keyCode: Self.t, modifiers: [.control, .option]), .keyUp(keyCode: Self.t),
                         .keyUp(keyCode: Self.space)], .controlOption, chord: Self.space)
        #expect(tUp.foreignKey, "T spoiled the hold; only the chord key is forgiven")
        let tFirst = facts([ctrl, ctrlOpt, .keyDown(keyCode: Self.t, modifiers: [.control, .option]), .keyUp(keyCode: Self.t)],
                           .controlOption, chord: Self.space)
        #expect(tFirst.foreignKey)
    }

    @Test func withoutAChordSpaceSpoilsAsBefore() {
        let events: [ShortcutEvent] = [ctrl, ctrlOpt, .keyDown(keyCode: Self.space, modifiers: [.control, .option]), .keyUp(keyCode: Self.space)]
        #expect(facts(events, .controlOption).foreignKey)
        #expect(facts(events, .controlOption, chord: nil) == facts(events, .controlOption))
        #expect(!facts(events, .controlOption, chord: nil).chordDown)
        let held = facts(Array(events.dropLast()), .controlOption)
        #expect(held.foreignKey && !held.chordDown)
    }

    @Test func spoilersClearWhenEveryModifierIsUp() {
        var state = ShortcutState()
        state.apply(ctrl); state.apply(ctrlOpt)
        state.apply(.keyDown(keyCode: Self.space, modifiers: [.control, .option]))
        state.apply(.keyDown(keyCode: Self.t, modifiers: [.control, .option]))
        #expect(state.spoilers == [Self.space, Self.t] && state.spoiled)
        state.apply(.keyUp(keyCode: Self.space)); state.apply(.keyUp(keyCode: Self.t))
        #expect(state.spoilers == [Self.space, Self.t], "a key up does not clear the spoilers")
        state.apply(.flags(keyCode: Self.ctrlL, modifiers: .option))
        #expect(state.spoiled)
        state.apply(.flags(keyCode: Self.optL, modifiers: []))
        #expect(state.spoilers.isEmpty && !state.spoiled)
        var typed = ShortcutState()
        typed.apply(.keyDown(keyCode: Self.space, modifiers: []))
        #expect(typed.spoilers.isEmpty, "a key typed with nothing held spoils nothing")
    }

    // MARK: The picture

    @Test func everythingIsUpAtLaunchAndAfterEveryKeyIsLetGo() {
        #expect(facts([], .controlOption).allUp)
        #expect(!facts([ctrl], .controlOption).allUp)
        #expect(!facts([.keyDown(keyCode: Self.left, modifiers: [])], .controlOption).allUp)
        #expect(facts([.keyDown(keyCode: Self.left, modifiers: []), .keyUp(keyCode: Self.left)], .controlOption).allUp)
        #expect(facts([ctrl, .flags(keyCode: Self.ctrlL, modifiers: [])], .controlOption).allUp)
    }

    @Test func aKeyDownCarryingCommandLeavesNoModifierBehind() {
        var state = ShortcutState()
        state.apply(.keyDown(keyCode: 9, modifiers: .command))
        state.apply(.keyUp(keyCode: 9))
        #expect(state.flagModifiers.isEmpty, "a pasted shortcut is not a modifier press")
        #expect(KeyFacts(of: state, key: .rightCommand).allUp)
        #expect(!KeyFacts(of: state, key: .rightCommand).ownDown)
    }

    @Test func anArrowKeyAndItsFnFlagLeaveAnFnKeyNotHeld() {
        var state = ShortcutState()
        state.apply(.keyDown(keyCode: Self.left, modifiers: .function))
        #expect(!KeyFacts(of: state, key: .function).ownDown)
        state.apply(.keyUp(keyCode: Self.left))
        #expect(state.isHeld(.function), "isHeld still reads the last event's modifiers, as before")
        let facts = KeyFacts(of: state, key: .function)
        #expect(!facts.ownDown && facts.allUp, "the facts read only flags events")
    }

    @Test func aResyncTakesTheLiveModifiersAndForgetsOrdinaryKeys() {
        var state = ShortcutState()
        state.apply(ctrl); state.apply(ctrlOpt)
        state.apply(.keyDown(keyCode: Self.left, modifiers: [.control, .option]))
        state.resync(to: .control)
        #expect(state.flagModifiers == .control && state.modifiers == .control)
        #expect(state.keysDown.isEmpty)
        #expect(state.deviceKeys == [Self.ctrlL], "the Option key is gone, the Control key stays")
        #expect(KeyFacts(of: state, key: .controlOption).ownDown == false)
    }

    @Test func aResyncKeepsAHeldModifierSoLettingItGoAndPressingItAgainIsNeverAllUp() {
        var state = ShortcutState()
        state.apply(ctrl); state.apply(ctrlOpt)
        state.resync(to: [.control, .option])
        #expect(!KeyFacts(of: state, key: .controlOption).allUp)
        state.apply(.flags(keyCode: Self.optL, modifiers: .control))
        #expect(!KeyFacts(of: state, key: .controlOption).allUp)
        state.apply(.flags(keyCode: Self.optL, modifiers: [.control, .option]))
        #expect(!KeyFacts(of: state, key: .controlOption).allUp)
        state.resync(to: [])
        #expect(KeyFacts(of: state, key: .controlOption).allUp)
        #expect(!state.spoiled)
    }

    private static let tab: UInt16 = 48

    @Test func aKeyDownWithNoKeyUpIsForeignUntilThePictureIsPruned() {
        var state = ShortcutState()
        state.apply(.keyDown(keyCode: Self.tab, modifiers: []))
        state.apply(.flags(keyCode: Self.cmdR, modifiers: .command))
        var facts = KeyFacts(of: state, key: .rightCommand)
        #expect(facts.ownDown && facts.foreignKey && !facts.allUp)
        state.prune(keysDown: [Self.tab])
        #expect(KeyFacts(of: state, key: .rightCommand).foreignKey, "the system still reports Tab down")
        state.prune(keysDown: [])
        facts = KeyFacts(of: state, key: .rightCommand)
        #expect(facts.ownDown && !facts.foreignKey, "the system says Tab is up")
        state.apply(.flags(keyCode: Self.cmdR, modifiers: []))
        #expect(KeyFacts(of: state, key: .rightCommand).allUp)
    }

    @Test func aPruneLeavesModifiersAndTheKeysStillDownAlone() {
        var state = ShortcutState()
        state.apply(ctrl); state.apply(ctrlOpt)
        state.apply(.keyDown(keyCode: Self.left, modifiers: [.control, .option]))
        state.apply(.keyDown(keyCode: Self.t, modifiers: [.control, .option]))
        state.prune(keysDown: [Self.left])
        #expect(state.keysDown == [Self.left])
        #expect(state.flagModifiers == [.control, .option] && state.deviceKeys == [Self.ctrlL, Self.optL])
    }

    @Test func theStateIsEquatableAndHashable() {
        var a = ShortcutState(), b = ShortcutState()
        #expect(a == b)
        a.apply(ctrl)
        #expect(a != b)
        b.apply(ctrl)
        #expect(a == b && Set([a, b]).count == 1)
    }
}
