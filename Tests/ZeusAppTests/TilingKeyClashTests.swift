import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The reader behind the Key clash state hands the pure rule the keys as the owner has them now, VoiceOver
/// included. The rule itself is proved in `TileBaseConflictsTests`.
@Suite("Tiling key clash reader", .serialized) @MainActor
struct TilingKeyClashTests {
    private func note(_ base: TileModifierBase, talk: Shortcut = .controlOption, voiceOverOn: Bool, dictation: Shortcut? = nil,
                      pointing: Shortcut? = nil, polyglot: Shortcut? = nil) -> String? {
        TilingKeyClash.note(base: base, keymap: nil,
                            keys: TilingKeyClash.Keys(talk: talk, dictation: dictation, pointing: pointing, polyglot: polyglot,
                                                      chat: .off, voiceOverOn: voiceOverOn, others: []))
    }

    @Test func theNoteFollowsTheKeyTheTalkMonitorListensOnWhileVoiceOverRuns() {
        #expect(note(.optionCommand, voiceOverOn: false) == nil)
        let moved = note(.optionCommand, voiceOverOn: true)
        #expect(moved?.contains("Talk to Zeus") == true && moved?.contains("Option-Command") == true, "\(String(describing: moved))")
    }

    @Test func voiceOverRefusesEveryPairThatHoldsControlAndOptionAndNothingElse() {
        #expect(note(.controlOption, talk: .rightOption, voiceOverOn: true)?.contains("VoiceOver") == true)
        #expect(note(.controlOption, talk: .rightOption, voiceOverOn: false) == nil)
        #expect(note(.controlOptionCommand, talk: .rightOption, voiceOverOn: true)?.contains("VoiceOver") == true,
                "VoiceOver also uses its pair with Command and a letter")
        #expect(note(.controlOptionCommand, talk: .rightOption, voiceOverOn: false) == nil)
        #expect(note(.optionCommand, talk: .rightOption, voiceOverOn: true) == nil)
    }

    @Test func anotherZeusShortcutTheTilingKeysBindIsRefused() {
        let todo = TileBaseConflicts.NamedShortcut(name: "Quick to-do", shortcut: Shortcut(keyCode: 17, modifiers: [.control, .option]))
        let keys = TilingKeyClash.Keys(talk: .rightOption, dictation: nil, pointing: nil, polyglot: nil, chat: .off,
                                       voiceOverOn: false, others: [todo])
        #expect(TilingKeyClash.note(base: .controlOption, keymap: nil, keys: keys)?.contains("Quick to-do") == true)
        #expect(TilingKeyClash.note(base: .controlOptionCommand, keymap: nil, keys: keys) == nil)
    }

    @Test func theShippedShortcutPresetsAreReadAsKeyedShortcuts() {
        #expect(ShortcutPreset.controlOptionT.tilingShortcut == Shortcut(keyCode: 17, modifiers: [.control, .option]))
        #expect(ShortcutPreset.optionCommandZ.tilingShortcut == Shortcut(keyCode: 6, modifiers: [.option, .command]))
        #expect(ShortcutPreset.controlCommandZ.tilingShortcut == Shortcut(keyCode: 6, modifiers: [.control, .command]))
        #expect(ShortcutPreset.controlOptionSpace.tilingShortcut == Shortcut(keyCode: 49, modifiers: [.control, .option]))
        #expect(ShortcutPreset.off.tilingShortcut == nil)
    }

    @Test func theLiveKeysIncludeTheSelectedPresetsAndThePrompterPause() {
        let live = TilingKeyClash.Keys.live()
        let names = live.others.map(\.name)
        #expect(names.contains("Prompter pause"))
        #expect(live.others.contains { $0.name == "Quick to-do" } == (ExtraPreferences.shared.quickTodo.tilingShortcut != nil))
        #expect(live.others.contains { $0.name == "Open the notch" } == (ExtraPreferences.shared.openNotch.tilingShortcut != nil))
    }

    @Test func aKeyedShortcutTheTilingKeysBindIsRefused() {
        let leftArrow = Shortcut(keyCode: 123, modifiers: [.control, .option])
        #expect(note(.controlOption, talk: leftArrow, voiceOverOn: false)?.contains("Talk to Zeus") == true)
        #expect(note(.controlOption, talk: .rightOption, voiceOverOn: false, dictation: leftArrow)?.contains("Dictation") == true)
        #expect(note(.controlOption, talk: .rightOption, voiceOverOn: false, pointing: leftArrow)?.contains("Pointing") == true)
    }

    @Test func theLiveKeysCarryTheSameFieldsAsTheMonitorsRead() {
        let live = TilingKeyClash.Keys.live()
        #expect(live.talk == Preferences.shared.pushToTalk, "the chosen key; the rule derives the key the monitor listens on")
        #expect(live.voiceOverOn == NSWorkspace.shared.isVoiceOverEnabled)
        #expect(live.dictation == (DictationSettings.shared.enabled ? DictationSettings.shared.key : nil))
        #expect(live.pointing == (PointingSettings.enabled ? PointingSettings.shortcut : nil))
    }

    // MARK: Polyglot, and every monitor key in one place

    @Test func theShippedPolyglotKeyIsRefusedOnTheControlOptionPair() {
        let found = note(.controlOption, talk: .rightOption, voiceOverOn: false, polyglot: PolyglotSettings.defaultHotkey)
        #expect(found?.contains("Polyglot") == true, "\(String(describing: found))")
        #expect(note(.controlOptionCommand, talk: .rightOption, voiceOverOn: false, polyglot: PolyglotSettings.defaultHotkey) == nil)
        #expect(note(.controlOption, talk: .rightOption, voiceOverOn: false, polyglot: nil) == nil)
    }

    @Test func theLiveKeysCarryThePolyglotKeyAsItsMonitorReadsIt() {
        let settings = PolyglotSettings.shared
        #expect(TilingKeyClash.Keys.live().polyglot == (settings.enabled ? settings.hotkey : nil))
    }

    /// Every `HotkeyMonitor` in the app listens for a key the tiling tap could consume, so each one has to be read by
    /// `Keys.live()`. A new monitor or a new key provider fails here until its key is added there and its file is
    /// named below.
    @Test func everyKeyMonitorInTheAppIsAccountedForByTheLiveKeys() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Zeus")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var monitors: Set<String> = []
        var providers: Set<String> = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("HotkeyMonitor()") { monitors.insert(url.lastPathComponent) }
            if text.contains(".keyProvider =") { providers.insert(url.lastPathComponent) }
        }
        // Talk (the app delegate), Dictation, Polyglot, Pointing and Chat.
        #expect(monitors == ["AppDelegate.swift", "DictationController.swift", "PolyglotController.swift",
                             "PointingController.swift", "ChatHotkeyMonitor.swift"], "\(monitors.sorted())")
        // The talk monitor's own provider is the default one in HotkeyMonitor.swift.
        #expect(providers == ["DictationController.swift", "PolyglotController.swift"], "\(providers.sorted())")
    }

    // MARK: Hot keys registered through HotKeyCenter

    private static let ansiLetterCodes: [String: UInt16] = ["Y": 16, "N": 45, "O": 31, "P": 35]

    /// Every key that is registered with `HotKeyCenter` is a key the tiling tap would swallow if the keymap bound it.
    /// The preset keys (Quick to-do, the notch) are read from their settings; the others are fixed letters with
    /// Control and Option, and `Keys.live()` must list each one. A new raw binding provider, or a new fixed letter in
    /// one, fails here until it is added to `Keys.others`.
    @Test func everyHotKeyCenterBindingIsRepresentedInTheLiveKeys() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Zeus")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var providers: Set<String> = []
        var letters: Set<String> = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for chunk in text.components(separatedBy: "-> [(UInt32, UInt32, () -> Void)]").dropFirst() {
                providers.insert(url.lastPathComponent)
                let body = chunk.components(separatedBy: "\n    }\n").first ?? chunk
                for part in body.components(separatedBy: "kVK_ANSI_").dropFirst() { letters.insert(String(part.prefix(1))) }
            }
        }
        #expect(providers == ["AppDelegate.swift", "PrompterWindow.swift"], "\(providers.sorted())")
        #expect(letters == ["Y", "N", "O", "P"], "a new fixed hot key letter: \(letters.sorted())")
        let live = TilingKeyClash.Keys.live(answerKeysOn: true).others.map(\.shortcut)
        for letter in letters {
            let code = try #require(Self.ansiLetterCodes[letter], "add the key code of \(letter) to this test")
            #expect(live.contains(Shortcut(keyCode: code, modifiers: [.control, .option])), "\(letter) is not in Keys.live()")
        }
    }

    @Test func theApprovalAnswerKeysAreListedWhileTheSettingIsOnAndOnlyThen() {
        let expected = [Shortcut(keyCode: 16, modifiers: [.control, .option]), Shortcut(keyCode: 45, modifiers: [.control, .option]),
                        Shortcut(keyCode: 31, modifiers: [.control, .option])]
        let on = TilingKeyClash.Keys.live(answerKeysOn: true).others.map(\.shortcut)
        for key in expected { #expect(on.contains(key)) }
        let off = TilingKeyClash.Keys.live(answerKeysOn: false).others.map(\.shortcut)
        for key in expected { #expect(!off.contains(key)) }
    }

    @Test func aTilingKeyOnAnApprovalAnswerKeyIsRefusedWithThatKeysName() throws {
        var keymap = TileKeymap()
        try keymap.bind(Shortcut(keyCode: 16, modifiers: [.control, .option]), to: .retile)
        let keys = TilingKeyClash.Keys(talk: .rightOption, dictation: nil, pointing: nil, polyglot: nil, chat: .off,
                                       voiceOverOn: false, others: TilingKeyClash.Keys.approvalAnswers)
        let found = TilingKeyClash.note(base: .controlOption, keymap: keymap, keys: keys)
        #expect(found?.contains("Approve") == true, "\(String(describing: found))")
        #expect(TilingKeyClash.note(base: .controlOption, keymap: keymap,
                                    keys: TilingKeyClash.Keys(talk: .rightOption, dictation: nil, pointing: nil, polyglot: nil,
                                                              chat: .off, voiceOverOn: false, others: [])) == nil)
    }
}
