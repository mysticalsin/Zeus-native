import Foundation
import Testing
@testable import ZeusCore

@Suite("Command dictate path")
struct CommandDictatePathTests {
    @Test func aWritableFocusedFieldIsInsertedInsteadOfLeftOnTheClipboard() {
        let choice = FocusedFieldWrite.choose(turnCurrent: true, fieldWritable: true)
        #expect(choice == .writeField)
        #expect(FocusedFieldWrite.inserted(choice: choice, fieldWriteLanded: true))
    }

    @Test func aClipboardChoiceIsNotInserted() {
        #expect(FocusedFieldWrite.choose(turnCurrent: true, fieldWritable: false) == .clipboard)
        #expect(FocusedFieldWrite.choose(turnCurrent: false, fieldWritable: true) == .clipboard)
        let choice = FocusedFieldWrite.Choice.clipboard
        #expect(!FocusedFieldWrite.inserted(choice: choice, fieldWriteLanded: false))
        #expect(!FocusedFieldWrite.inserted(choice: .writeField, fieldWriteLanded: false))
    }

    @Test func aMissingKeyGrantAnnouncesAndALaterGrantArmsTheHotkey() {
        var recovery = KeyListenRecovery()
        #expect(recovery.send(.start(granted: false)) == [.announceMissing])
        #expect(recovery.send(.start(granted: false)).isEmpty)
        #expect(!recovery.armed)
        #expect(recovery.send(.granted) == [.armMonitors, .clearStuckPress])
        #expect(recovery.armed)
        #expect(recovery.send(.granted).isEmpty)
    }

    @Test func aPromptThatBecomesReadyWhileHeldStartsTheTurn() {
        #expect(CommandHotkeyAccess.press(voice: .needsPrompt) == .ask)
        #expect(CommandHotkeyAccess.recover(voice: .ready, keyStillDown: true) == .start)
        #expect(CommandHotkeyAccess.recover(voice: .ready, keyStillDown: false) == .wait)
        #expect(CommandHotkeyAccess.press(voice: .ready) == .start)
    }

    @Test func aDeniedVoiceGrantDoesNotStartTheTurn() {
        #expect(CommandHotkeyAccess.press(voice: .denied) == .degradeVoice)
        #expect(CommandHotkeyAccess.recover(voice: .denied, keyStillDown: true) == .degradeVoice)
        #expect(CommandHotkeyAccess.recover(voice: .needsPrompt, keyStillDown: true) == .wait)
    }

    @Test func anUnsetDictateFileGenerationDoesNotFlushTheTrace() {
        var book = STTUtteranceBook()
        let noted = book.begin(path: .murmurTap, atMs: 0)
        let unset = DictateFileTrace.keep(0)
        #expect(noted > 0)
        #expect(unset == 0)
        let wrote = book.deliver(generation: unset, atMs: 50)
        #expect(!wrote)
        #expect(book.trace.offset(.deliveredToUI) == nil)
    }

    @Test func aDictateFileGenerationFlushesTheMurmurTrace() {
        var book = STTUtteranceBook()
        let noted = book.begin(path: .murmurTap, atMs: 0)
        let kept = DictateFileTrace.keep(noted)
        let wrote = book.deliver(generation: kept, atMs: 50)
        #expect(wrote)
        #expect(book.trace.path == .murmurTap)
        #expect(book.trace.offset(.deliveredToUI) == 50)
        #expect(book.trace.grouped(failure: .none).contains("path=murmur-tap"))
        #expect(book.trace.grouped(failure: .none).contains("delivered_to_ui=50"))
    }
}
