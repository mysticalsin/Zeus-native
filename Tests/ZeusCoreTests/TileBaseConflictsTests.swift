import Foundation
import Testing
@testable import ZeusCore

/// The tiling key pair against Zeus's other global keys. A pair that another Zeus key already holds is refused,
/// because the tiling tap consumes the chord before the other key's monitor can see it spoil the hold.
@Suite struct TileBaseConflictsTests {
    private func notes(_ base: TileModifierBase = .controlOption, talk: Shortcut = .controlOption,
                       dictation: Shortcut? = .rightCommand, pointing: Shortcut? = nil, chat: ChatHotkey = .off,
                       keymap: TileKeymap? = nil) -> [String] {
        TileBaseConflicts.notes(base: base, keymap: keymap ?? TileKeymap.defaults(base: base), talk: talk,
                                dictation: dictation, pointing: pointing, chat: chat)
    }

    @Test func theDefaultPairClashesWithTheDefaultTalkKey() {
        let found = notes()
        #expect(found.count == 1)
        #expect(found[0].contains("Control-Option") && found[0].contains("Talk to Zeus"))
    }

    @Test func aPairTheOtherKeysDoNotHoldIsClear() {
        #expect(notes(.optionCommand).isEmpty)
    }

    @Test func aLargerPairThanTheTalkKeyIsClearBecauseTheTalkHoldNeedsExactlyItsOwnModifiers() {
        #expect(notes(.controlOptionCommand).isEmpty)
    }

    @Test func pointingAndDictationAreNamedWhenTheyHoldThePair() {
        let found = notes(.optionCommand, talk: .rightOption, dictation: .optionCommand, pointing: .optionCommand)
        #expect(found.count == 1)
        #expect(found[0].contains("Pointing") && found[0].contains("Dictation") && !found[0].contains("Talk"))
    }

    @Test func oneKeyHeldByTalkAndPointingIsOneNoteNamingBoth() {
        let found = notes(.controlOption, dictation: nil, pointing: .controlOption)
        #expect(found.count == 1)
        #expect(found[0].contains("Talk to Zeus") && found[0].contains("Pointing"))
    }

    @Test func keysThatAreOffAreIgnored() {
        #expect(notes(.optionCommand, talk: .rightOption, dictation: nil, pointing: nil).isEmpty)
        #expect(notes(.controlOption, talk: .rightOption, dictation: nil, pointing: nil).isEmpty)
    }

    @Test func theChatShortcutClashesOnlyWhenTheKeymapBindsItsChord() throws {
        #expect(notes(.controlOption, talk: .rightOption, chat: .controlOptionSpace).isEmpty, "the default table never binds Space or C")
        var keymap = TileKeymap.defaults(base: .controlOption)
        try keymap.bind(Shortcut(keyCode: 8, modifiers: [.control, .option]), to: .retile)
        let found = notes(.controlOption, talk: .rightOption, chat: .controlOptionC, keymap: keymap)
        #expect(found.count == 1 && found[0].contains("Chat"))
        #expect(notes(.controlOption, talk: .rightOption, chat: .off, keymap: keymap).isEmpty)
        #expect(notes(.controlOption, talk: .rightOption, chat: .optionSpace, keymap: keymap).isEmpty)
    }

    @Test func theCopyIsPlainAndHasNoDashes() throws {
        var keymap = TileKeymap.defaults(base: .controlOption)
        try keymap.bind(Shortcut(keyCode: 8, modifiers: [.control, .option]), to: .retile)
        let found = notes(.controlOption, pointing: .controlOption, chat: .controlOptionC, keymap: keymap)
        #expect(found.count == 2)
        for text in found {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)")
        }
    }
}
