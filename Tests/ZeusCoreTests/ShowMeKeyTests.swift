import Foundation
import Testing
@testable import ZeusCore

@Suite("Show-me key")
struct ShowMeKeyTests {
    @Test func theShowMeKeyIsLeftControlAlone() {
        #expect(Shortcut.showMe == Shortcut(modifiers: .control, side: .left))
        #expect(Shortcut.showMe.isModifierOnly)
        #expect(ShowMeKey.keyCode == 59)
        #expect(ShortcutModifiers.keyCodes.first { $0.0 == .control }?.left == ShowMeKey.keyCode)
    }

    @Test func onlyLeftControlAloneArmsTheHold() {
        #expect(ShowMeKey.startsHold(modifiers: .control, keyCode: 59))
        #expect(!ShowMeKey.startsHold(modifiers: .control, keyCode: 62), "Right Control is not the key")
        #expect(!ShowMeKey.startsHold(modifiers: .command, keyCode: 55), "Left Command no longer arms show-me")
        #expect(!ShowMeKey.startsHold(modifiers: [.control, .option], keyCode: 59), "Control with another modifier is the talk chord")
        #expect(!ShowMeKey.startsHold(modifiers: [.control, .command], keyCode: 59))
        #expect(!ShowMeKey.startsHold(modifiers: [], keyCode: 59), "A release is not a press")
    }

    @Test func aQuickControlClickNeverArmsBecauseAMouseButtonIsDown() {
        #expect(ShowMeKey.mayArm(modifiers: .control, pressedMouseButtons: 0))
        #expect(!ShowMeKey.mayArm(modifiers: .control, pressedMouseButtons: 1), "Control-click is a right click: pass it through")
        #expect(!ShowMeKey.mayArm(modifiers: .control, pressedMouseButtons: 2))
        #expect(!ShowMeKey.mayArm(modifiers: [.control, .shift], pressedMouseButtons: 0))
        #expect(!ShowMeKey.mayArm(modifiers: [], pressedMouseButtons: 0))
    }

    @Test func theHoldHasAHalfSecondOrLessDelayBeforeItTakesTheMouse() {
        #expect(ShowMeKey.holdDelayMilliseconds == 350)
    }

    @Test func releasingControlEndsTheHoldAndAnotherModifierCancelsIt() {
        #expect(ShowMeKey.endsHold(modifiers: []))
        #expect(ShowMeKey.endsHold(modifiers: .shift))
        #expect(!ShowMeKey.endsHold(modifiers: .control))
        #expect(!ShowMeKey.endsHold(modifiers: [.control, .option]))
        #expect(ShowMeKey.cancelsHold(modifiers: [.control, .option]))
        #expect(!ShowMeKey.cancelsHold(modifiers: .control))
        #expect(!ShowMeKey.cancelsHold(modifiers: []))
    }

    @Test func theConflictsDefaultIsTheSharedKey() {
        let result = ShortcutConflicts.pointingWarnings(pointing: .function, talk: .rightOption, dictation: .rightCommand,
                                                        chat: .off, doubleControlTextEntry: false)
        #expect(!result.contains { $0.contains("Show me") }, "Fn pointing, right Option talk and right Command dictation do not touch left Control")
        let overlap = ShortcutConflicts.pointingWarnings(pointing: Shortcut(modifiers: .control), talk: .rightOption,
                                                         dictation: .rightCommand, chat: .off, doubleControlTextEntry: false)
        #expect(overlap.contains { $0.contains("Overlaps Show me") })
        let sameAsOldDefault = ShortcutConflicts.pointingWarnings(pointing: Shortcut(modifiers: .command), talk: .rightOption,
                                                                  dictation: .rightCommand, chat: .off, doubleControlTextEntry: false)
        #expect(!sameAsOldDefault.contains { $0.contains("Show me") }, "Command no longer overlaps Show me")
    }

    @Test func doubleTapControlTextEntryWarnsThatShowMeUsesControl() {
        let on = ShortcutConflicts.pointingWarnings(pointing: .function, talk: .rightOption, dictation: .rightCommand,
                                                    chat: .off, doubleControlTextEntry: true)
        #expect(on.contains { $0.contains("Show me") && $0.contains("left Control") })
        let off = ShortcutConflicts.pointingWarnings(pointing: .function, talk: .rightOption, dictation: .rightCommand,
                                                     chat: .off, doubleControlTextEntry: false)
        #expect(!off.contains { $0.contains("left Control") })
    }
}
