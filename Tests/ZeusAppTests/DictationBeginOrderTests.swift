import AppKit
import Foundation
import Testing
@testable import Zeus

/// Key down opens the microphone before any read of the focused field.
@MainActor
@Suite("Dictation begin order")
struct DictationBeginOrderTests {
    init() { ZeusSound.isMutedForTesting = true }

    @Test func keyDownOpensTheMicBeforeReadingTheFocusedField() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mic-first-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let controller = DictationController(topBar: TopBarModel(), store: DictationStore(root: root))
        var log: [String] = []
        var seams = DictationController.Seams()
        seams.access = { _, _ in .init(speech: true, microphone: true, language: true, onDevice: true) }
        seams.readyEngine = { nil }
        seams.pauseMedia = { _ in nil }
        seams.speechStart = { _, generation in
            log.append("mic \(generation)")
            return 41
        }
        seams.contextRead = { controller in
            log.append("context")
            return controller.readFocusedContext()
        }
        controller.seams = seams
        controller.begin()
        #expect(log.count == 2)
        #expect(log[0].hasPrefix("mic "))
        #expect(log[1] == "context")
        #expect(controller.flow.isListening)
        let generation = UInt64(log[0].dropFirst(4))
        #expect(controller.turnContext?.generation == generation)
    }

    @Test func pasteBackStaysTheKeyDownAppWhenTheLaterReadNamesAnother() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mic-first-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let controller = DictationController(topBar: TopBarModel(), store: DictationStore(root: root))
        let keyDown = try #require(NSWorkspace.shared.frontmostApplication)
        let other = try #require(NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != keyDown.processIdentifier
        })
        var seams = DictationController.Seams()
        seams.access = { _, _ in .init(speech: true, microphone: true, language: true, onDevice: true) }
        seams.readyEngine = { nil }
        seams.pauseMedia = { _ in nil }
        seams.speechStart = { _, _ in 41 }
        seams.contextRead = { _ in
            DictationController.FocusedContext(targetApp: other, insertionField: nil,
                                               mode: DictationMode.builtIns[0], selection: nil)
        }
        controller.seams = seams
        controller.begin()
        let turn = try #require(controller.turnContext)
        #expect(turn.keyDownApp.processID == keyDown.processIdentifier)
        #expect(turn.pasteBackApp?.processIdentifier == keyDown.processIdentifier)
        #expect(turn.targetApp?.processIdentifier == other.processIdentifier)
        #expect(turn.pasteBackApp?.processIdentifier != other.processIdentifier)
    }
}
