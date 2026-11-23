import Foundation
import Testing
@testable import ZeusCore

@Suite("Tile preset bits")
struct TilePresetBitsTests {
    @Test func eachModifierBitAndAMissingKeyCode() {
        let missing = TilePresetBits.shortcut(keyCode: nil, mask: TilePresetBits.command)
        #expect(missing == nil)

        let control = TilePresetBits.shortcut(keyCode: 17, mask: TilePresetBits.control)
        #expect(control == Shortcut(keyCode: 17, modifiers: .control))

        let option = TilePresetBits.shortcut(keyCode: 17, mask: TilePresetBits.option)
        #expect(option == Shortcut(keyCode: 17, modifiers: .option))

        let shift = TilePresetBits.shortcut(keyCode: 17, mask: TilePresetBits.shift)
        #expect(shift == Shortcut(keyCode: 17, modifiers: .shift))

        let command = TilePresetBits.shortcut(keyCode: 6, mask: TilePresetBits.command)
        #expect(command == Shortcut(keyCode: 6, modifiers: .command))
    }
}
