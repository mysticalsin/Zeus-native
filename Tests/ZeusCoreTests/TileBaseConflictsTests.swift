import Foundation
import Testing
@testable import ZeusCore

/// The tiling key pair against Zeus's other global keys. A pair that another Zeus key already holds is refused,
/// because the tiling tap consumes the chord before the other key's monitor can see it spoil the hold.
@Suite struct TileBaseConflictsTests {
    /// `talk` is the key the owner chose; the rule works out the key the talk monitor really listens on.
    private func notes(_ base: TileModifierBase = .controlOption, talk: Shortcut = .controlOption,
                       dictation: Shortcut? = .rightCommand, pointing: Shortcut? = nil, chat: ChatHotkey = .off,
                       voiceOverOn: Bool = false, keymap: TileKeymap? = nil) -> [String] {
        TileBaseConflicts.notes(base: base, keymap: keymap ?? TileKeymap.defaults(base: base), talk: talk,
                                dictation: dictation, pointing: pointing, chat: chat, voiceOverOn: voiceOverOn)
    }

    /// A keyed chord on `modifiers`: left arrow, J and Space.
    private func chord(_ code: UInt16, _ modifiers: ShortcutModifiers) -> Shortcut { Shortcut(keyCode: code, modifiers: modifiers) }
    private let leftArrow: UInt16 = 123, keyJ: UInt16 = 38, keyT: UInt16 = 17, space: UInt16 = 49

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

    // MARK: The key the talk monitor really listens on

    @Test func whileVoiceOverRunsTheTalkKeyThatMovedToOptionCommandHoldsTheOptionCommandPair() {
        let found = notes(.optionCommand, talk: .controlOption, voiceOverOn: true)
        #expect(found.count == 1)
        #expect(found[0].contains("Option-Command") && found[0].contains("Talk to Zeus") && found[0].contains("VoiceOver"), "\(found)")
        #expect(notes(.optionCommand, talk: .controlOption, voiceOverOn: false).isEmpty, "with VoiceOver off the talk key stays on Control-Option")
    }

    @Test func theMovedTalkKeySkipsAFallbackAnotherKeyUses() {
        let found = notes(.optionCommand, talk: .controlOption, dictation: .optionCommand, voiceOverOn: true)
        #expect(found.count == 1 && found[0].contains("Dictation") && !found[0].contains("Talk"), "talk moved on to Right Option: \(found)")
        #expect(notes(.optionCommand, talk: .controlOption, dictation: nil, pointing: .optionCommand, voiceOverOn: true).count == 1)
        #expect(notes(.controlOptionCommand, talk: .controlOption, voiceOverOn: true).isEmpty, "a larger pair is clear whichever key the talk hold uses")
    }

    @Test func aTalkKeyTheOwnerChoseIsNotMovedByVoiceOver() {
        let found = notes(.optionCommand, talk: .optionCommand, voiceOverOn: true)
        #expect(found.count == 1 && found[0].contains("Talk to Zeus"))
        #expect(notes(.controlOption, talk: .rightOption, dictation: nil, voiceOverOn: true).count == 1, "only the VoiceOver note")
    }

    // MARK: VoiceOver's own pair

    @Test func theControlOptionPairIsRefusedWhileVoiceOverRunsWhoeverHoldsTheOtherKeys() {
        let found = notes(.controlOption, talk: .rightOption, dictation: nil, voiceOverOn: true)
        #expect(found.count == 1)
        #expect(found[0].contains("VoiceOver") && found[0].contains("Control-Option"), "\(found)")
        #expect(notes(.controlOption, talk: .rightOption, dictation: nil, voiceOverOn: false).isEmpty)
    }

    @Test func voiceOverDoesNotRefuseTheOtherPairs() {
        #expect(notes(.optionCommand, talk: .rightOption, dictation: nil, voiceOverOn: true).isEmpty)
        #expect(notes(.controlOptionCommand, talk: .rightOption, dictation: nil, voiceOverOn: true).isEmpty)
    }

    @Test func theVoiceOverNoteComesFirstSoThePageShowsIt() {
        let found = notes(.controlOption, talk: .controlOption, dictation: nil, pointing: .controlOption, voiceOverOn: true)
        #expect(found.first?.contains("VoiceOver") == true, "\(found)")
    }

    // MARK: Keyed Zeus shortcuts against every tiling chord

    @Test func aKeyedTalkDictationOrPointingShortcutTheKeymapBindsIsAClash() {
        let talk = notes(.controlOption, talk: chord(leftArrow, [.control, .option]), dictation: nil)
        #expect(talk.count == 1 && talk[0].contains("Talk to Zeus") && talk[0].contains("tiling key"), "\(talk)")
        let dictation = notes(.controlOption, talk: .rightOption, dictation: chord(keyJ, [.control, .option]))
        #expect(dictation.count == 1 && dictation[0].contains("Dictation"), "\(dictation)")
        let pointing = notes(.controlOption, talk: .rightOption, dictation: nil, pointing: chord(keyT, [.control, .option]))
        #expect(pointing.count == 1 && pointing[0].contains("Pointing"), "\(pointing)")
    }

    @Test func theNoteNamesTheChordSoTheOwnerCanFindIt() {
        let found = notes(.controlOption, talk: chord(leftArrow, [.control, .option]), dictation: nil)
        #expect(found[0].contains("\u{2303}\u{2325}\u{2190}"), "\(found)")
    }

    @Test func aShiftedChordOfTheKeymapAndAChordWithTheFnFlagAreCaught() {
        #expect(notes(.controlOption, talk: chord(leftArrow, [.control, .option, .shift]), dictation: nil).count == 1, "swap left")
        #expect(notes(.controlOption, talk: chord(leftArrow, [.control, .option, .function]), dictation: nil).count == 1,
                "macOS adds fn to an arrow key, and the tap strips it before it looks the chord up")
    }

    @Test func aKeyedShortcutTheKeymapDoesNotBindIsClear() {
        #expect(notes(.controlOption, talk: chord(space, [.control, .option]), dictation: nil).isEmpty, "the default table never binds Space")
        #expect(notes(.controlOption, talk: chord(leftArrow, [.control, .option, .command]), dictation: nil).isEmpty, "a different modifier set")
        #expect(notes(.controlOptionCommand, talk: chord(leftArrow, [.control, .option]), dictation: nil).isEmpty, "another base binds other chords")
        #expect(notes(.controlOption, talk: .rightOption, dictation: nil, pointing: nil).isEmpty)
    }

    @Test func aKeyedShortcutIsComparedWithEveryBoundChordNotOnlyTheDefaultTable() throws {
        var keymap = TileKeymap.defaults(base: .optionCommand)
        let own = chord(space, [.option, .command])
        #expect(notes(.optionCommand, talk: own, dictation: nil, keymap: keymap).isEmpty)
        try keymap.bind(own, to: .retile)
        let found = notes(.optionCommand, talk: own, dictation: nil, keymap: keymap)
        #expect(found.count == 1 && found[0].contains("Talk to Zeus"), "\(found)")
    }

    @Test func aKeyedShortcutIsNotAModifierOnlyHolderAndTheOtherWayAround() {
        let keyed = notes(.controlOption, talk: chord(space, [.control, .option]), dictation: nil)
        #expect(keyed.isEmpty, "a keyed shortcut on the same modifiers does not start on the modifiers alone")
        let found = notes(.optionCommand, talk: .rightOption, dictation: .optionCommand)
        #expect(found.count == 1 && found[0].contains("Dictation") && found[0].contains("also your"), "\(found)")
    }

    // MARK: Defaults

    @Test func theShippedDefaultPairClashesWithNoShippedDefaultKey() {
        // Talk Control-Option, Dictation Right Command, Pointing Control-Option, Chat Control-Option-Space.
        for voiceOver in [false, true] {
            let base = TileConfig.defaults.base
            let found = TileBaseConflicts.notes(base: base, keymap: TileKeymap.defaults(base: base),
                                                talk: ShortcutStore.talkDefault, dictation: .rightCommand, pointing: .controlOption,
                                                chat: .standard, voiceOverOn: voiceOver)
            #expect(found.isEmpty, "voiceOver \(voiceOver): \(found)")
        }
    }

    @Test func theCopyIsPlainAndHasNoDashes() throws {
        var keymap = TileKeymap.defaults(base: .controlOption)
        try keymap.bind(Shortcut(keyCode: 8, modifiers: [.control, .option]), to: .retile)
        var found = notes(.controlOption, pointing: .controlOption, chat: .controlOptionC, keymap: keymap)
        #expect(found.count == 2)
        found += notes(.controlOption, talk: .rightOption, dictation: nil, voiceOverOn: true)
        found += notes(.optionCommand, talk: .controlOption, voiceOverOn: true)
        found += notes(.controlOption, talk: chord(leftArrow, [.control, .option]), dictation: nil)
        #expect(found.count == 5)
        for text in found {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)")
        }
    }
}
