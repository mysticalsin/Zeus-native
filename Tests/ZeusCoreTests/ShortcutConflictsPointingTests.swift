import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing shortcut conflicts")
struct ShortcutConflictsPointingTests {
    private func warnings(pointing: Shortcut = .controlOption, talk: Shortcut = .controlOption,
                          dictation: Shortcut? = .rightCommand, chat: ChatHotkey = .off,
                          doubleControl: Bool = false, voiceOver: Bool = false) -> [String] {
        ShortcutConflicts.pointingWarnings(pointing: pointing, talk: talk, dictation: dictation, chat: chat,
                                           doubleControlTextEntry: doubleControl, voiceOverOn: voiceOver)
    }

    @Test func shippedDefaultsDoNotWarn() {
        #expect(warnings().isEmpty)
    }

    @Test func voiceOverIsMentionedOnlyWhileItIsOn() {
        let result = warnings(voiceOver: true)
        #expect(result.count == 1)
        #expect(result.first?.contains("VoiceOver") == true)
    }

    @Test func theChatShortcutSharingTheModifiersIsExplained() {
        let result = warnings(chat: .controlOptionSpace)
        #expect(result.contains { $0.contains("Chat shortcut") })
        #expect(!warnings(chat: .commandShiftSpace).contains { $0.contains("Chat shortcut") })
    }

    @Test func theSameKeyAsTalkIsOneTurnNotAConflict() {
        #expect(!warnings(pointing: .controlOption, talk: .controlOption).contains { $0.contains("Talk to Zeus") })
        #expect(!warnings(pointing: .rightOption, talk: .rightOption).contains { $0.contains("Talk to Zeus") })
    }

    @Test func theSameKeyAsDictationIsStillFlagged() {
        #expect(warnings(pointing: .rightOption, dictation: .rightOption).contains { $0.contains("Same key as Dictation") })
    }

    @Test func anOverlappingShowMeKeyIsFlagged() {
        let result = warnings(pointing: Shortcut(modifiers: .command))
        #expect(result.contains { $0.contains("Overlaps Show me") })
    }

    @Test func aDictationChordThatExtendsThePointingKeyWarnsAboutTheFlash() {
        let result = warnings(pointing: .function, dictation: .functionControl)
        #expect(result.contains { $0.contains("flashes") })
    }

    @Test func doubleControlWarnsAboutMacOSDictation() {
        #expect(!warnings().contains { $0.contains("Press Control key twice") })
        #expect(warnings(doubleControl: true).contains { $0.contains("Press Control key twice") })
    }

    @Test func doubleControlOverlapsAControlOnlyTalkKey() {
        let result = warnings(talk: Shortcut(modifiers: .control), doubleControl: true)
        #expect(result.contains { $0.contains("talk or dictation key") })
    }

    @Test func theFnControlPresetIsAValidModifierChord() {
        #expect(Shortcut.functionControl.isValid)
        #expect(Shortcut.functionControl.modifiers == [.function, .control])
        #expect(Shortcut.parse(Shortcut.stored(.functionControl)) == .functionControl)
    }

    @Test func thePresetRemembersAndRestoresTheDictationKey() {
        let preset = Shortcut.stored(.functionControl), right = Shortcut.stored(.rightCommand)
        let on = DictationFnControlPreset.next(wanted: true, current: right, saved: nil)
        #expect(on?.key == preset && on?.saved == right)
        #expect(DictationFnControlPreset.next(wanted: true, current: preset, saved: right) == nil)
        let off = DictationFnControlPreset.next(wanted: false, current: preset, saved: right)
        #expect(off?.key == right && off?.saved == nil)
        let lost = DictationFnControlPreset.next(wanted: false, current: preset, saved: nil)
        #expect(lost?.key == right)
        #expect(DictationFnControlPreset.next(wanted: false, current: right, saved: nil) == nil)
    }
}
