import Testing
@testable import ZeusCore

@Suite("Chat hotkey")
struct ChatHotkeyTests {
    @Test func symbolsAndCodes() {
        #expect(ChatHotkey.standard.symbols == "⌃⌥Space")
        #expect(ChatHotkey.commandShiftSpace.symbols == "⇧⌘Space")
        #expect(ChatHotkey.controlOptionC.symbols == "⌃⌥C")
        #expect(ChatHotkey.controlOptionC.keyCode == 8)
        #expect(ChatHotkey.optionSpace.keyCode == 49)
        #expect(ChatHotkey.off.keyCode == nil && ChatHotkey.off.symbols == "Off")
        #expect(ChatHotkey.optionShiftSpace.spoken == "Option Shift Space")
        #expect(ChatHotkey.controlOptionSpace.modifiers.rawValue == (1 << 12 | 1 << 11))
    }

    @Test func storedValueFallsBack() {
        #expect(ChatHotkey.stored(nil) == .standard)
        #expect(ChatHotkey.stored("nonsense") == .standard)
        #expect(ChatHotkey.stored("off") == .off)
    }

    @Test func noChoiceUsesARightSideModifierAlone() {
        // Dictation and push-to-talk are single right-hand modifier keys; every chat
        // shortcut needs a real key, so they can never collide.
        #expect(ChatHotkey.allCases.allSatisfy { $0 == .off || $0.keyCode != nil })
    }
}
