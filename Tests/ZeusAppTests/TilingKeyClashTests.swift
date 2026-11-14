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
                      pointing: Shortcut? = nil) -> String? {
        TilingKeyClash.note(base: base, keymap: nil,
                            keys: TilingKeyClash.Keys(talk: talk, dictation: dictation, pointing: pointing, chat: .off,
                                                      voiceOverOn: voiceOverOn))
    }

    @Test func theNoteFollowsTheKeyTheTalkMonitorListensOnWhileVoiceOverRuns() {
        #expect(note(.optionCommand, voiceOverOn: false) == nil)
        let moved = note(.optionCommand, voiceOverOn: true)
        #expect(moved?.contains("Talk to Zeus") == true && moved?.contains("Option-Command") == true, "\(String(describing: moved))")
    }

    @Test func voiceOverRefusesItsOwnPairAndNothingElse() {
        #expect(note(.controlOption, talk: .rightOption, voiceOverOn: true)?.contains("VoiceOver") == true)
        #expect(note(.controlOption, talk: .rightOption, voiceOverOn: false) == nil)
        #expect(note(.controlOptionCommand, voiceOverOn: true) == nil)
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
}
