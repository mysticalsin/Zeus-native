import Foundation
import Testing

/// `AVAudioPlayerDelegate.audioPlayerDidFinishPlaying` is nonisolated.
/// A `@MainActor` method cannot satisfy it (`#ConformanceIsolation`).
@Suite("Provider player delegate isolation")
struct ProviderPlayerDelegateIsolationTests {
    @Test func theFinishCallbackIsNonisolated() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/Zeus/Voice/PluginVoiceBridge.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("class ProviderPlayerDelegate: NSObject, AVAudioPlayerDelegate"))
        #expect(text.contains("nonisolated func audioPlayerDidFinishPlaying"))
    }
}
