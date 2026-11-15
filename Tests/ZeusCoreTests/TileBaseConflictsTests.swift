import Foundation
import Testing
@testable import ZeusCore

/// The tiling key pair against Zeus's other global keys. A pair that another Zeus key already holds is refused,
/// because the tiling tap consumes the chord before the other key's monitor can see it spoil the hold.
@Suite struct TileBaseConflictsTests {
    /// `talk` is the key the owner chose; the rule works out the key the talk monitor really listens on.
    private func notes(_ base: TileModifierBase = .controlOption, talk: Shortcut = .controlOption,
                       dictation: Shortcut? = .rightCommand, pointing: Shortcut? = nil, polyglot: Shortcut? = nil,
                       chat: ChatHotkey = .off, voiceOverOn: Bool = false, keymap: TileKeymap? = nil,
                       dictationToggles: Bool = false, others: [TileBaseConflicts.NamedShortcut] = [],
                       talkChord: Shortcut? = nil) -> [String] {
        TileBaseConflicts.notes(base: base, keymap: keymap ?? TileKeymap.defaults(base: base), talk: talk,
                                dictation: dictation, pointing: pointing, polyglot: polyglot, chat: chat,
                                voiceOverOn: voiceOverOn, dictationToggles: dictationToggles, others: others, talkChord: talkChord)
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

    /// The rule leaves a larger pair free only because every hold-style monitor cancels a hold that a larger chord
    /// ends, and the tap tells the monitors about every key it consumes (`TilingConsumedKeyTests` proves both halves).
    @Test func aLargerPairThanTheTalkKeyIsFreeBecauseTheMonitorsAreToldAboutEveryConsumedKey() {
        #expect(notes(.controlOptionCommand).isEmpty)
    }

    // MARK: Keys that act on the first press

    /// A press-to-toggle dictation key acts the moment its own modifiers are down. A larger tiling pair that is
    /// pressed in the natural order (the smaller pair first) would toggle dictation on every chord, and a toggle
    /// cannot be taken back the way a hold can be cancelled, so the pair is refused.
    @Test func aToggleDictationKeyInsideALargerPairIsAClash() {
        let found = notes(.controlOptionCommand, talk: .rightOption, dictation: .controlOption, dictationToggles: true)
        #expect(found.count == 1 && found[0].contains("Dictation") && found[0].contains("Control-Option-Command"), "\(found)")
        #expect(notes(.controlOptionCommand, talk: .rightOption, dictation: .controlOption, dictationToggles: false).isEmpty,
                "a hold is cancelled when a larger chord ends it, so a hold-style key inside the pair is free")
    }

    @Test func aToggleDictationKeyOnTheSameModifiersIsStillTheEqualPairNote() {
        let found = notes(.controlOption, talk: .rightOption, dictation: .controlOption, dictationToggles: true)
        #expect(found.count == 1 && found[0].contains("also your Dictation key"), "one note, not two: \(found)")
    }

    @Test func aModifierOnlyPolyglotKeyInsideALargerPairIsAClashBecauseItToggles() {
        let found = notes(.controlOptionCommand, talk: .rightOption, dictation: nil, polyglot: .controlOption)
        #expect(found.count == 1 && found[0].contains("Polyglot"), "\(found)")
        #expect(notes(.controlOptionCommand, talk: .rightOption, dictation: nil, polyglot: Shortcut(keyCode: keyT, modifiers: [.shift])).isEmpty)
    }

    @Test func aToggleKeyOutsideThePairOrOffIsFree() {
        #expect(notes(.controlOptionCommand, talk: .rightOption, dictation: .function, dictationToggles: true).isEmpty, "Fn is not in the pair")
        #expect(notes(.optionCommand, talk: .rightOption, dictation: .controlOption, dictationToggles: true).isEmpty,
                "Control is not in Option-Command, so Control-Option is not inside it")
        #expect(notes(.controlOptionCommand, talk: .rightOption, dictation: nil, dictationToggles: true).isEmpty, "dictation is off")
    }

    @Test func aSingleModifierToggleKeyInsideThePairIsAClashToo() {
        let found = notes(.optionCommand, talk: .rightOption, dictation: .rightCommand, dictationToggles: true)
        #expect(found.count == 1 && found[0].contains("Dictation"), "Right Command is held inside Option-Command: \(found)")
    }

    @Test func theShippedDefaultsClashWithNothing() {
        // Shipped: talk and pointing Control-Option, dictation Right Command in hold mode, Polyglot Control-Option-T, tiling Control-Option-Command.
        let polyglot = Shortcut(keyCode: keyT, modifiers: [.control, .option])
        #expect(notes(.standard, talk: .controlOption, dictation: .rightCommand, pointing: .controlOption, polyglot: polyglot).isEmpty)
        #expect(TileModifierBase.standard == .controlOptionCommand)
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

    @Test func aTilingBindingOnTheTalkChordIsNamed() throws {
        let chord = VoiceKey.talkChord
        #expect(notes(.controlOption, talk: .rightOption, talkChord: chord).isEmpty, "the default table never binds Space")
        var keymap = TileKeymap.defaults(base: .controlOption)
        try keymap.bind(chord, to: .retile)
        let found = notes(.controlOption, talk: .rightOption, keymap: keymap, talkChord: chord)
        #expect(found == ["Control-Option-Space is both your Talk to Zeus chord and a tiling key."], "\(found)")
        #expect(notes(.controlOption, talk: .rightOption, keymap: keymap, talkChord: nil).isEmpty, "no chord, no note")
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
        #expect(notes(.controlOptionCommand, talk: .controlOption, dictation: nil, voiceOverOn: true).count == 1,
                "only the VoiceOver note: the talk key moved to Option-Command, which is a smaller pair")
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

    @Test func voiceOverDoesNotRefuseAPairWithoutControlAndOption() {
        #expect(notes(.optionCommand, talk: .rightOption, dictation: nil, voiceOverOn: true).isEmpty)
    }

    /// VoiceOver also owns its modifiers plus Command plus a letter (VO-Command-J, -T, -L, -H). The default table binds
    /// J, T, P, R and K and the arrows on the pair, so a pair that holds Control and Option takes those from VoiceOver.
    @Test func whileVoiceOverRunsAPairThatHoldsControlAndOptionIsRefusedWhateverElseItHolds() {
        for base in [TileModifierBase.controlOptionCommand, .controlOption] {
            let found = notes(base, talk: .rightOption, dictation: nil, voiceOverOn: true)
            #expect(found.count == 1 && found[0].contains("VoiceOver") && found[0].contains(base.label), "\(base): \(found)")
            #expect(notes(base, talk: .rightOption, dictation: nil, voiceOverOn: false).isEmpty, "\(base) with VoiceOver off")
        }
    }

    @Test func aBoundChordWithControlAndOptionIsRefusedWhileVoiceOverRunsEvenOnAnotherBase() throws {
        var keymap = TileKeymap.defaults(base: .optionCommand)
        #expect(notes(.optionCommand, talk: .rightOption, dictation: nil, voiceOverOn: true, keymap: keymap).isEmpty)
        try keymap.bind(chord(8, [.control, .option, .shift]), to: .retile)
        let found = notes(.optionCommand, talk: .rightOption, dictation: nil, voiceOverOn: true, keymap: keymap)
        #expect(found.count == 1 && found[0].contains("VoiceOver"), "\(found)")
        #expect(notes(.optionCommand, talk: .rightOption, dictation: nil, voiceOverOn: false, keymap: keymap).isEmpty)
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

    @Test func aGlobeChordOnALetterIsNotAClashWithTheChordWithoutFn() {
        #expect(notes(.controlOption, talk: chord(keyJ, [.control, .option, .function]), dictation: nil).isEmpty,
                "the tap passes Globe plus the pair plus J through, so it never takes the key from another feature")
        #expect(notes(.controlOption, talk: chord(keyJ, [.control, .option]), dictation: nil).count == 1)
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

    // MARK: Polyglot

    /// Polyglot ships on, with Control-Option-T. Its monitor reads every key the tiling tap forwards as a consumed key
    /// and toggles audio capture on an exact match, so a chord both features bind would float a window and start
    /// capturing audio from one key press.
    private let polyglotDefault = Shortcut(keyCode: 17, modifiers: [.control, .option])

    @Test func theShippedPolyglotKeyAgainstTheControlOptionPairIsAClash() {
        let found = notes(.controlOption, talk: .rightOption, dictation: nil, polyglot: polyglotDefault)
        #expect(found.count == 1 && found[0].contains("Polyglot") && found[0].contains("tiling key"), "\(found)")
        #expect(found[0].contains(polyglotDefault.symbol), "\(found)")
    }

    @Test func aPolyglotKeyOnAnotherTilingChordIsAClash() {
        let found = notes(.controlOptionCommand, talk: .rightOption, dictation: nil,
                          polyglot: chord(keyT, [.control, .option, .command]))
        #expect(found.count == 1 && found[0].contains("Polyglot"), "\(found)")
        let shifted = notes(.controlOption, talk: .rightOption, dictation: nil, polyglot: chord(leftArrow, [.control, .option, .shift]))
        #expect(shifted.count == 1 && shifted[0].contains("Polyglot"), "swap left: \(shifted)")
    }

    @Test func aPolyglotKeyTheKeymapDoesNotBindIsClearAndAnOffKeyIsIgnored() {
        #expect(notes(.controlOptionCommand, talk: .rightOption, dictation: nil, polyglot: polyglotDefault).isEmpty,
                "the shipped pair binds Control-Option-Command chords, not Control-Option-T")
        #expect(notes(.controlOption, talk: .rightOption, dictation: nil, polyglot: chord(space, [.control, .option])).isEmpty)
        #expect(notes(.controlOption, talk: .rightOption, dictation: nil, polyglot: nil).isEmpty)
    }

    @Test func aModifierOnlyPolyglotKeyEqualToThePairHoldsIt() {
        let found = notes(.optionCommand, talk: .rightOption, dictation: nil, polyglot: .optionCommand)
        #expect(found.count == 1 && found[0].contains("Polyglot") && found[0].contains("also your"), "\(found)")
    }

    // MARK: The other global Zeus shortcuts

    private func named(_ name: String, _ code: UInt16, _ modifiers: ShortcutModifiers) -> TileBaseConflicts.NamedShortcut {
        TileBaseConflicts.NamedShortcut(name: name, shortcut: chord(code, modifiers))
    }

    @Test func aQuickTodoOrNotchShortcutTheKeymapBindsIsAClash() {
        let todo = notes(.controlOption, talk: .rightOption, dictation: nil, others: [named("Quick to-do", keyT, [.control, .option])])
        #expect(todo.count == 1 && todo[0].contains("Quick to-do") && todo[0].contains("tiling key"), "\(todo)")
        let preset = notes(.optionCommand, talk: .rightOption, dictation: nil, others: [named("Quick to-do", keyT, [.option, .command])])
        #expect(preset.count == 1 && preset[0].contains("Quick to-do"), "\(preset)")
        let notch = notes(.controlOption, talk: .rightOption, dictation: nil, others: [named("Prompter pause", 35, [.control, .option])])
        #expect(notch.count == 1 && notch[0].contains("Prompter pause"), "pause is bound on every pair: \(notch)")
    }

    @Test func anotherZeusShortcutTheKeymapDoesNotBindIsClear() {
        let others = [named("Quick to-do", keyT, [.control, .option]), named("Open the notch", 6, [.option, .command]),
                      named("Quick to-do", space, [.control, .option])]
        #expect(notes(.controlOptionCommand, talk: .rightOption, dictation: nil, others: others).isEmpty, "the default pair binds none of them")
        #expect(notes(.optionCommand, talk: .rightOption, dictation: nil, others: [named("Open the notch", 6, [.option, .command])]).isEmpty,
                "Z is not a tiling key")
    }

    // MARK: Every modifier set the keymap binds

    /// A keymap with one chord, on `modifiers`.
    private func keymap(_ modifiers: ShortcutModifiers...) throws -> TileKeymap {
        var map = TileKeymap()
        for set in modifiers { try map.bind(chord(keyJ, set), to: .flipSplit) }
        return map
    }

    private let pairShift: ShortcutModifiers = [.control, .option, .command, .shift]

    @Test func aHoldKeyOnThePairPlusShiftIsRefused() {
        let found = notes(.controlOptionCommand, talk: Shortcut(modifiers: pairShift), dictation: nil)
        #expect(found.count == 1 && found[0].contains("Control-Option-Command-Shift is also your Talk to Zeus key"), "\(found)")
        let pointing = notes(.controlOptionCommand, talk: .rightOption, dictation: nil, pointing: Shortcut(modifiers: pairShift))
        #expect(pointing.count == 1 && pointing[0].contains("Pointing"), "\(pointing)")
    }

    @Test func aKeyThatDiffersFromABoundSetOnlyByFnCountsAsEqual() {
        let withFn = Shortcut(modifiers: [.control, .option, .command, .function])
        let found = notes(.controlOptionCommand, talk: withFn, dictation: nil)
        #expect(found.count == 1 && found[0].contains("also your Talk to Zeus key"), "\(found)")
        let shifted = Shortcut(modifiers: [.control, .option, .command, .shift, .function])
        #expect(notes(.controlOptionCommand, talk: shifted, dictation: nil).count == 1, "the pair plus Shift plus Fn")
    }

    @Test func aToggleKeyOnThePairPlusShiftIsRefused() {
        let found = notes(.controlOptionCommand, talk: .rightOption, dictation: Shortcut(modifiers: pairShift), dictationToggles: true)
        #expect(found.count == 1 && found[0].contains("Control-Option-Command-Shift is also your Dictation key"), "\(found)")
        let polyglot = notes(.controlOptionCommand, talk: .rightOption, dictation: nil, polyglot: Shortcut(modifiers: pairShift))
        #expect(polyglot.count == 1 && polyglot[0].contains("Polyglot"), "\(polyglot)")
    }

    @Test func aToggleKeyInsideThePairPlusShiftOnlyIsRefused() {
        let controlShift = Shortcut(modifiers: [.control, .shift])
        let found = notes(.controlOptionCommand, talk: .rightOption, dictation: controlShift, dictationToggles: true)
        #expect(found.count == 1 && found[0].contains("Control-Option-Command-Shift also holds your Dictation key"), "\(found)")
        #expect(notes(.controlOptionCommand, talk: .rightOption, dictation: controlShift, dictationToggles: false).isEmpty,
                "a hold key there waits out the confirm instead")
    }

    @Test func aHoldKeyStrictlyInsideABoundSetIsFreeAndWaitsOutTheConfirm() throws {
        let map = TileKeymap.defaults(base: .controlOptionCommand)
        for key in [Shortcut.controlOption, .rightCommand, .optionCommand, Shortcut(modifiers: [.control, .shift])] {
            #expect(TileBaseConflicts.confirm(for: key, keymap: map) == 0.15, "\(key.symbol)")
        }
        #expect(notes(.controlOptionCommand, talk: .controlOption, dictation: .rightCommand, pointing: .controlOption).isEmpty)
        #expect(TileBaseConflicts.confirm(for: .controlOption, keymap: TileKeymap()) == 0, "no chord is bound")
    }

    @Test func aKeyEqualToABoundSetOrOutsideEveryOneHasNoConfirm() throws {
        let map = TileKeymap.defaults(base: .controlOptionCommand)
        #expect(TileBaseConflicts.confirm(for: Shortcut(modifiers: [.control, .option, .command]), keymap: map) == 0, "refused, not delayed")
        #expect(TileBaseConflicts.confirm(for: .controlOption, keymap: TileKeymap.defaults(base: .optionCommand)) == 0, "inside no bound set")
        #expect(TileBaseConflicts.confirm(for: .function, keymap: map) == 0, "Fn alone")
        #expect(TileBaseConflicts.confirm(for: chord(leftArrow, [.control]), keymap: map) == 0, "a keyed key is not a hold key")
    }

    @Test func fnAloneIsFreeAgainstEveryKeymap() throws {
        let map = try keymap([.command], [.control, .option])
        #expect(notes(.controlOption, talk: .function, dictation: nil, pointing: .function, keymap: map).isEmpty)
        #expect(notes(.controlOption, talk: .rightOption, dictation: .function, polyglot: .function, keymap: map).isEmpty)
        #expect(notes(.controlOption, talk: .rightOption, dictation: .function, keymap: map, dictationToggles: true).isEmpty)
    }

    @Test func aDictationHoldKeyOneShiftShortOfABoundSetIsRefusedAndATalkKeyThereIsFree() throws {
        let map = try keymap([.control, .option, .shift])
        let dictation = notes(.controlOption, talk: .rightOption, dictation: .controlOption, keymap: map)
        #expect(dictation.count == 1 && dictation[0].contains("Control-Option-Shift is also your Dictation key"), "\(dictation)")
        #expect(notes(.controlOption, talk: .controlOption, dictation: nil, keymap: map).isEmpty, "Shift joining talk cancels it")
        #expect(TileBaseConflicts.confirm(for: .controlOption, keymap: map) == 0.15)
        let pointing = notes(.controlOption, talk: .rightOption, dictation: nil, pointing: .controlOption, keymap: map)
        #expect(pointing.isEmpty)
    }

    @Test func aKeymapWithAChordOnOneModifierIsReadAsBound() throws {
        let map = try keymap([.command])
        let hold = notes(.controlOption, talk: .rightCommand, dictation: nil, keymap: map)
        #expect(hold.count == 1 && hold[0].contains("Command is also your Talk to Zeus key"), "\(hold)")
        let toggle = notes(.controlOption, talk: .rightOption, dictation: .rightCommand, keymap: map, dictationToggles: true)
        #expect(toggle.count == 1 && toggle[0].contains("Command is also your Dictation key"), "\(toggle)")
        #expect(notes(.controlOption, talk: .controlOption, dictation: nil, keymap: map).isEmpty, "Control-Option is not inside Command")
    }

    @Test func aKeyNamedByTheChordItMeetsNotByTheBase() throws {
        let map = try keymap([.option, .shift])
        let found = notes(.controlOptionCommand, talk: .rightOption, dictation: nil, polyglot: Shortcut(modifiers: [.option, .shift]), keymap: map)
        #expect(found.count == 1 && found[0].contains("Option-Shift") && !found[0].contains("Control-Option-Command"), "\(found)")
    }

    @Test func theChordNoteHasNoDashesOtherThanTheHyphensOfTheNames() {
        let found = notes(.controlOptionCommand, talk: Shortcut(modifiers: pairShift), dictation: nil)
        #expect(found.count == 1)
        for text in found { #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)") }
    }

    // MARK: Defaults

    @Test func theShippedDefaultPairClashesWithNoShippedDefaultKey() {
        // Talk Control-Option, Dictation Right Command, Pointing Control-Option, Chat Control-Option-Space.
        let base = TileConfig.defaults.base
        let shippedOthers = [named("Quick to-do", keyT, [.control, .option]), named("Open the notch", 6, [.option, .command])]
        func shipped(voiceOver: Bool) -> [String] {
            TileBaseConflicts.notes(base: base, keymap: TileKeymap.defaults(base: base),
                                    talk: ShortcutStore.talkDefault, dictation: .rightCommand, pointing: .controlOption,
                                    polyglot: polyglotDefault, chat: .standard, voiceOverOn: voiceOver, others: shippedOthers)
        }
        #expect(shipped(voiceOver: false).isEmpty, "\(shipped(voiceOver: false))")
        // With VoiceOver running the pair holds Control and Option, which VoiceOver owns: that note alone, nothing else.
        let withVoiceOver = shipped(voiceOver: true)
        #expect(withVoiceOver.count == 1 && withVoiceOver[0].contains("VoiceOver"), "\(withVoiceOver)")
    }

    @Test func theCopyIsPlainAndHasNoDashes() throws {
        var keymap = TileKeymap.defaults(base: .controlOption)
        try keymap.bind(Shortcut(keyCode: 8, modifiers: [.control, .option]), to: .retile)
        var found = notes(.controlOption, pointing: .controlOption, chat: .controlOptionC, keymap: keymap)
        #expect(found.count == 2)
        found += notes(.controlOption, talk: .rightOption, dictation: nil, voiceOverOn: true)
        found += notes(.optionCommand, talk: .controlOption, voiceOverOn: true)
        found += notes(.controlOption, talk: chord(leftArrow, [.control, .option]), dictation: nil)
        found += notes(.controlOption, talk: .rightOption, dictation: nil, others: [named("Quick to-do", keyT, [.control, .option])])
        #expect(found.count == 6)
        for text in found {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)")
        }
    }
}
