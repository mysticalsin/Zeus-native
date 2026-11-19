import Foundation
import Testing
import ZeusCore
@testable import Zeus

private func tempStore() -> WhisperKitModelStore {
    WhisperKitModelStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("zeus-wke-\(UUID().uuidString)"))
}

@Suite struct WhisperKitEngineTests {
    @Test func availabilityFollowsTheModelOnDisk() async throws {
        let store = tempStore()
        let engine = WhisperKitEngine(store: store)
        #expect(await engine.availability() == .notDownloaded)
        #expect(!engine.isDownloaded)
        for name in WhisperKitModelStore.requiredFolders {
            try FileManager.default.createDirectory(at: store.modelFolder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        #expect(await engine.availability() == .notDownloaded)
        try store.markComplete()
        #expect(await engine.availability() == .ready)
        #expect(engine.modelFolder == store.modelFolder)
    }

    @Test func transcribingWithoutAModelIsNotReady() async {
        let engine = WhisperKitEngine(store: tempStore())
        await #expect(throws: TranscriptionError.self) {
            _ = try await engine.transcribe(samples: [0.1, 0.2], hints: ["Zeus"], language: nil)
        }
    }

    @Test func vocabularyPromptPassesThroughToTheTokenizer() {
        let prompt = WhisperKitEngine.prompt(for: ["Zeus", "Jev"])
        #expect(prompt == "Names: Zeus, Jev.")
        var encoded = ""
        let tokens = WhisperKitEngine.promptTokens(prompt, encode: { text in
            encoded = text
            return [220, 50, 51_000, 7]
        }, specialTokenBegin: 50_257)
        #expect(encoded == " Names: Zeus, Jev.")
        #expect(tokens == [220, 50, 51_000, 7].filter { $0 < 50_257 })
        #expect(WhisperKitEngine.prompt(for: []) == "")
        #expect(WhisperKitEngine.promptTokens("", encode: { _ in [1] }, specialTokenBegin: 10) == nil)
    }
}
