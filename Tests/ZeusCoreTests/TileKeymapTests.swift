import Foundation
import Testing
@testable import ZeusCore

private let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
private let keyJ: UInt16 = 38, keyT: UInt16 = 17, keyP: UInt16 = 35, keyR: UInt16 = 15, keyK: UInt16 = 40
private let openBracket: UInt16 = 33, closeBracket: UInt16 = 30

private func chord(_ code: UInt16, _ modifiers: ShortcutModifiers) -> Shortcut {
    Shortcut(keyCode: code, modifiers: modifiers)
}

@Suite struct TileKeymapTests {
    private let allBases: [TileModifierBase] = [.controlOption, .optionCommand, .controlOptionCommand]

    // MARK: Modifier bases

    @Test func eachBaseMapsToItsModifierSet() {
        #expect(TileModifierBase.controlOption.modifiers == [.control, .option])
        #expect(TileModifierBase.optionCommand.modifiers == [.option, .command])
        #expect(TileModifierBase.controlOptionCommand.modifiers == [.control, .option, .command])
    }

    @Test func storedStringsMapToABaseAndUnknownOnesFallBackToTheShippedPair() {
        #expect(TileModifierBase(label: "controlOption") == .controlOption)
        #expect(TileModifierBase(label: "optionCommand") == .optionCommand)
        #expect(TileModifierBase(label: "controlOptionCommand") == .controlOptionCommand)
        // The wording a settings row shows reads the same.
        #expect(TileModifierBase(label: "Control-Option") == .controlOption)
        #expect(TileModifierBase(label: "Option-Command") == .optionCommand)
        #expect(TileModifierBase(label: "Control-Option-Command") == .controlOptionCommand)
        #expect(TileModifierBase(label: " control + option + command ") == .controlOptionCommand)
        #expect(TileModifierBase(label: "") == .standard)
        #expect(TileModifierBase(label: "hyper") == .standard)
        #expect(TileModifierBase(label: "optionShift") == .standard)
        #expect(TileModifierBase.standard == .controlOptionCommand)
        for base in allBases { #expect(TileModifierBase(label: base.rawValue) == base) }
    }

    // MARK: Actions

    @Test func everyActionHasAStableIdThatParsesBack() {
        #expect(TileAction.all.count == 18)
        #expect(Set(TileAction.all).count == 18)
        for action in TileAction.all {
            #expect(TileAction(id: action.id) == action)
        }
        #expect(Set(TileAction.all.map(\.id)).count == 18)
        #expect(TileAction(id: "teleport") == nil)
        #expect(TileAction(id: "") == nil)
        #expect(TileAction(id: "focus.sideways") == nil)
        #expect(TileAction.focus(.left).id == "focus.left")
        #expect(TileAction.flipSplit.id == "flipSplit")
        #expect(TileAction.maximizeToggle.id == "maximizeToggle")
    }

    // MARK: 11. Defaults

    @Test func theDefaultTableIsTheDocumentedOne() {
        let base: ShortcutModifiers = [.control, .option]
        let map = TileKeymap.defaults(base: .controlOption)
        let expected: [(Shortcut, TileAction)] = [
            (chord(left, base), .focus(.left)), (chord(right, base), .focus(.right)),
            (chord(up, base), .focus(.up)), (chord(down, base), .focus(.down)),
            (chord(left, base.union(.shift)), .swap(.left)), (chord(right, base.union(.shift)), .swap(.right)),
            (chord(up, base.union(.shift)), .swap(.up)), (chord(down, base.union(.shift)), .swap(.down)),
            (chord(keyJ, base), .flipSplit), (chord(keyT, base), .toggleFloat), (chord(keyP, base), .togglePause),
            (chord(keyR, base), .retile), (chord(keyK, base), .showKeys),
            (chord(openBracket, base.union(.shift)), .nudge(.left)), (chord(closeBracket, base.union(.shift)), .nudge(.right)),
        ]
        #expect(map.bindings.count == expected.count)
        for (shortcut, action) in expected { #expect(map.action(for: shortcut) == action) }
    }

    @Test func everyDefaultChordIsUniqueValidAndUsesTheBase() {
        for base in allBases {
            let map = TileKeymap.defaults(base: base)
            let chords = map.bindings.map(\.shortcut)
            #expect(Set(chords).count == chords.count)
            for shortcut in chords {
                #expect(shortcut.isValid)
                #expect(!shortcut.isModifierOnly)
                #expect(shortcut.modifiers.isSuperset(of: base.modifiers))
                #expect(shortcut.modifiers.subtracting(base.modifiers).subtracting(.shift).isEmpty)
            }
        }
    }

    @Test func everyActionHasExactlyOneDefaultExceptTheDocumentedUnboundOnes() {
        for base in allBases {
            let map = TileKeymap.defaults(base: base)
            let unbound = Set(TileKeymap.unboundByDefault)
            #expect(unbound == [.nudge(.up), .nudge(.down), .maximizeToggle])
            for action in TileAction.all {
                let count = map.bindings.filter { $0.action == action }.count
                #expect(count == (unbound.contains(action) ? 0 : 1))
            }
        }
    }

    @Test func theBasesGiveDifferentChordsForTheSameActions() {
        let a = TileKeymap.defaults(base: .controlOption)
        let b = TileKeymap.defaults(base: .optionCommand)
        #expect(a != b)
        #expect(a.shortcut(for: .flipSplit) == chord(keyJ, [.control, .option]))
        #expect(b.shortcut(for: .flipSplit) == chord(keyJ, [.option, .command]))
        #expect(a.action(for: chord(keyJ, [.option, .command])) == nil)
        #expect(a.shortcut(for: .maximizeToggle) == nil)
    }

    @Test func numberKeysAndPlainKeysAreLeftUnbound() {
        let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for base in allBases {
            let map = TileKeymap.defaults(base: base)
            for code in digits {
                #expect(map.action(for: chord(code, base.modifiers)) == nil)
                #expect(map.action(for: chord(code, base.modifiers.union(.shift))) == nil)
            }
            // The base alone, a bare arrow and a shifted bare arrow are not binds.
            #expect(map.action(for: Shortcut(modifiers: base.modifiers)) == nil)
            #expect(map.action(for: Shortcut(keyCode: left, modifiers: [])) == nil)
            #expect(map.action(for: chord(left, .shift)) == nil)
        }
    }

    @Test func aChordWithAnExtraModifierDoesNotMatch() {
        let map = TileKeymap.defaults(base: .controlOption)
        #expect(map.action(for: chord(left, [.control, .option])) == .focus(.left))
        #expect(map.action(for: chord(left, [.control, .option, .command])) == nil)
        #expect(map.action(for: chord(left, [.control])) == nil)
        #expect(map.action(for: chord(left, [.control, .option, .shift])) == .swap(.left))
    }

    @Test func theFnFlagThatArrowKeysCarryDoesNotStopAMatch() {
        // macOS sets the fn flag on arrow and function keys by itself, so a real Control-Option-Left press
        // arrives as control, option and fn. It matches the same chord without fn.
        for base in allBases {
            let map = TileKeymap.defaults(base: base)
            let mods = base.modifiers
            #expect(map.action(for: chord(left, mods.union(.function))) == .focus(.left))
            #expect(map.action(for: chord(down, mods.union(.function))) == .focus(.down))
            #expect(map.action(for: chord(right, mods.union([.shift, .function]))) == .swap(.right))
            #expect(map.action(for: chord(keyJ, mods.union(.function))) == .flipSplit)
        }
        let map = TileKeymap.defaults(base: .controlOption)
        // Fn does not hide an extra modifier, and Fn alone is not a base.
        #expect(map.action(for: chord(left, [.control, .option, .command, .function])) == nil)
        #expect(map.action(for: chord(left, [.control, .function])) == nil)
        #expect(map.action(for: chord(left, .function)) == nil)
        #expect(map.action(for: Shortcut(modifiers: [.control, .option, .function])) == nil)
    }

    @Test func aChordBoundWithFnStillMatchesExactlyAndBeatsTheStrippedOne() throws {
        var map = TileKeymap()
        try map.bind(chord(keyJ, [.control, .option, .function]), to: .retile)
        #expect(map.action(for: chord(keyJ, [.control, .option, .function])) == .retile)
        #expect(map.action(for: chord(keyJ, [.control, .option])) == nil)
        try map.bind(chord(keyJ, [.control, .option]), to: .flipSplit)
        #expect(map.action(for: chord(keyJ, [.control, .option, .function])) == .retile)
        #expect(map.action(for: chord(keyJ, [.control, .option])) == .flipSplit)
    }

    // MARK: Rejections

    @Test func aChordWithoutControlOptionOrCommandIsRejected() throws {
        var map = TileKeymap()
        // A bare letter, a Shift letter, an Fn letter and a bare function key would all take typing or a
        // system key from every app, so none of them can be bound.
        let rejected: [Shortcut] = [
            Shortcut(keyCode: keyJ, modifiers: []),
            chord(keyJ, .shift),
            chord(keyJ, .function),
            chord(keyJ, [.shift, .function]),
            Shortcut(keyCode: 122, modifiers: []),
            chord(122, .function),
            chord(left, .shift),
        ]
        for shortcut in rejected {
            #expect(throws: TileKeymapError.invalidChord) { try map.bind(shortcut, to: .flipSplit) }
        }
        #expect(map.bindings.isEmpty)
        // Any one of control, option or command is enough, with or without Shift.
        for modifier in [ShortcutModifiers.control, .option, .command] {
            try map.bind(chord(keyJ, modifier), to: .flipSplit)
            try map.bind(chord(keyJ, modifier.union(.shift)), to: .retile)
        }
        #expect(map.bindings.count == 6)
    }

    @Test func aModifierOnlyChordIsNotAKeyBind() {
        var map = TileKeymap()
        #expect(throws: TileKeymapError.invalidChord) { try map.bind(.controlOption, to: .retile) }
        #expect(throws: TileKeymapError.invalidChord) { try map.bind(Shortcut(modifiers: []), to: .retile) }
        #expect(map.bindings.isEmpty)
    }

    @Test func aDuplicateChordIsRejectedAndTheFirstBindStays() throws {
        var map = TileKeymap()
        let shortcut = chord(keyJ, [.control, .option])
        try map.bind(shortcut, to: .flipSplit)
        #expect(throws: TileKeymapError.duplicateChord) { try map.bind(shortcut, to: .retile) }
        #expect(throws: TileKeymapError.duplicateChord) { try map.bind(shortcut, to: .flipSplit) }
        #expect(map.bindings == [TileKeymap.Binding(shortcut: shortcut, action: .flipSplit)])
        #expect(map.action(for: shortcut) == .flipSplit)
    }

    @Test func theSameActionMayHaveASecondChord() throws {
        var map = TileKeymap.defaults(base: .controlOption)
        try map.bind(chord(keyJ, [.control, .option, .shift]), to: .flipSplit)
        #expect(map.bindings.filter { $0.action == .flipSplit }.count == 2)
        #expect(map.shortcut(for: .flipSplit) == chord(keyJ, [.control, .option]))
    }

    // MARK: Storage

    @Test func theKeymapRoundTripsThroughItsStoredForm() throws {
        for base in allBases {
            let map = TileKeymap.defaults(base: base)
            let data = try map.encoded()
            #expect(TileKeymap.decode(data) == map)
            // The stored form does not depend on dictionary order or on the run.
            #expect(try map.encoded() == data)
        }
        #expect(TileKeymap.decode(try TileKeymap().encoded()) == TileKeymap())
    }

    /// One stored entry, with the chord written by the same encoder Shortcut uses everywhere else.
    private func entry(_ shortcut: Shortcut, _ action: String) throws -> String {
        let chord = String(decoding: try JSONEncoder().encode(shortcut), as: UTF8.self)
        return "{\"shortcut\":\(chord),\"action\":\"\(action)\"}"
    }

    @Test func decodeSkipsActionsThisBuildDoesNotKnow() throws {
        let both: ShortcutModifiers = [.control, .option]
        let entries = [
            try entry(chord(keyJ, both), "flipSplit"),
            try entry(chord(39, both), "teleport"),
            try entry(chord(keyT, both), "focus.sideways"),
            try entry(chord(keyP, both), "togglePause"),
        ]
        let json = "{\"version\":1,\"bindings\":[" + entries.joined(separator: ",") + "]}"
        let map = try #require(TileKeymap.decode(Data(json.utf8)))
        #expect(map.bindings.count == 2)
        #expect(map.action(for: chord(keyJ, both)) == .flipSplit)
        #expect(map.action(for: chord(keyP, both)) == .togglePause)
        #expect(map.action(for: chord(39, both)) == nil)
    }

    @Test func decodeSkipsBadChordsAndDuplicatesAndEntriesItCannotRead() throws {
        let both: ShortcutModifiers = [.control, .option]
        let entries = [
            try entry(chord(keyJ, both), "flipSplit"),
            try entry(chord(keyJ, both), "retile"), // duplicate chord: the first one stays
            try entry(Shortcut(keyCode: keyR, modifiers: []), "retile"), // bare letter
            try entry(.controlOption, "retile"), // modifier only
            try entry(chord(0, .shift), "retile"), // Shift letter would take capital letters
            try entry(chord(0, .function), "retile"), // Fn letter
            try entry(Shortcut(keyCode: 122, modifiers: []), "retile"), // bare function key
            "{\"shortcut\":\"not a shortcut\",\"action\":\"retile\"}",
            "{\"nothing\":true}",
            "17",
            try entry(chord(keyK, both), "showKeys"),
        ]
        let json = "{\"version\":2,\"extra\":\"ignored\",\"bindings\":[" + entries.joined(separator: ",") + "]}"
        let map = try #require(TileKeymap.decode(Data(json.utf8)))
        #expect(map.bindings.map(\.action) == [.flipSplit, .showKeys])
    }

    @Test func decodeGivesNilForDataThatIsNotAKeymap() {
        #expect(TileKeymap.decode(Data()) == nil)
        #expect(TileKeymap.decode(Data("garbage".utf8)) == nil)
        #expect(TileKeymap.decode(Data("[]".utf8)) == nil)
        #expect(TileKeymap.decode(Data("{\"version\":1}".utf8)) == nil)
    }

    // MARK: Conflicts

    @Test func conflictsAreReportedAgainstAReservedSet() {
        let map = TileKeymap.defaults(base: .controlOption)
        let reserved: Set<Shortcut> = [
            chord(left, [.control, .option]), // collides with focus left
            chord(keyT, [.control, .option]), // collides with float
            chord(49, [.control, .option]), // Space: not bound here
            .controlOption, // modifier-only chord: not a key bind
            chord(keyJ, [.control, .command]), // other modifiers
        ]
        let hits = map.conflicts(with: reserved)
        #expect(Set(hits) == [chord(left, [.control, .option]), chord(keyT, [.control, .option])])
        // Reported in table order, so the answer is stable.
        #expect(hits == map.bindings.map(\.shortcut).filter { reserved.contains($0) })
        #expect(map.conflicts(with: Set<Shortcut>()).isEmpty)
        #expect(map.conflicts(with: [chord(49, .command)]).isEmpty)
        #expect(TileKeymap().conflicts(with: reserved).isEmpty)
        // Any collection of shortcuts works.
        #expect(map.conflicts(with: [chord(keyK, [.control, .option])]) == [chord(keyK, [.control, .option])])
    }
}
