import Foundation
import Testing
@testable import ZeusCore

@Suite("Dictation extras")
struct DictationExtrasTests {
    @Test func wavRoundTrips() throws {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1, 0.25]
        let data = WAVFile.encode(samples)
        #expect(data.count == 44 + samples.count * 2)
        let decoded = try #require(WAVFile.decode(data))
        #expect(decoded.sampleRate == 16_000)
        #expect(zip(decoded.samples, samples).allSatisfy { abs($0 - $1) < 0.001 })
        #expect(WAVFile.decode(Data("nope".utf8)) == nil)
    }

    @Test func storeKeepsAudioBesideTheRecord() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-audio-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DictationStore(root: dir)
        let record = DictationRecord(duration: 1, processingTime: 1, modeKey: "voice", modeName: "Voice", rawResult: "hi", result: "Hi")
        try store.save(record)
        #expect(!store.hasAudio(for: record.id))
        try store.saveAudio([0.1, 0.2], for: record.id)
        #expect(store.hasAudio(for: record.id))
        #expect(store.audio(for: record.id)?.count == 2)
        #expect(store.history().count == 1)
        store.delete(record.id)
        #expect(!store.hasAudio(for: record.id))
    }

    @Test func reprocessKeepsIdentity() {
        let record = DictationRecord(id: "x", duration: 900, processingTime: 100, modeKey: "voice", modeName: "Voice",
                                     rawResult: "hello there", result: "hello there", appName: "Mail", engine: "apple")
        let email = DictationMode.builtIns.first { $0.key == "email" }!
        let again = record.reprocessed(mode: email, rawResult: nil, result: "Hello there,", engine: nil, processingTime: 40)
        #expect(again.id == "x" && again.datetime == record.datetime && again.appName == "Mail")
        #expect(again.modeKey == "email" && again.result == "Hello there," && again.rawResult == "hello there")
        #expect(again.engine == "apple")
        let heard = record.reprocessed(mode: DictationMode.builtIns[0], rawResult: "hello their", result: "hello their", engine: "parakeet", processingTime: 50)
        #expect(heard.rawResult == "hello their" && heard.engine == "parakeet")
    }

    @Test func captureTurnsCorrectionsIntoReplacements() {
        let suggestion = VocabularyCapture.suggest(original: "Murmure and mount roil all live in the menu bar.",
                                                   corrected: "Murmure and Mount Royal all live in the menu bar.")
        #expect(suggestion.replacements == [Replacement(id: suggestion.replacements[0].id, original: "mount roil", with: "Mount Royal")])
        #expect(suggestion.words == ["Mount Royal"])
    }

    @Test func captureLearnsCasingAndInsertedNames() {
        let casing = VocabularyCapture.suggest(original: "ask zeus now", corrected: "ask ZEUS now")
        #expect(casing.replacements.isEmpty)
        #expect(casing.words == ["ZEUS"])
        let inserted = VocabularyCapture.suggest(original: "call me", corrected: "call me Devon")
        #expect(inserted.words == ["Devon"])
        #expect(VocabularyCapture.suggest(original: "same text.", corrected: "same text").isEmpty)
        #expect(VocabularyCapture.suggest(original: "drop this word", corrected: "drop word").isEmpty)
    }

    @Test func mergeSkipsKnownEntries() {
        let vocabulary = Vocabulary(words: ["ZEUS"], replacements: [Replacement(original: "mount roil", with: "Mount Royal")])
        let suggestion = VocabularyCapture.Suggestion(replacements: [Replacement(original: "Mount Roil", with: "x"), Replacement(original: "murmer", with: "Murmure")],
                                                      words: ["zeus", "Murmure"])
        let merged = VocabularyCapture.merge(suggestion, into: vocabulary)
        #expect(merged.words == ["ZEUS", "Murmure"])
        #expect(merged.replacements.map(\.original) == ["mount roil", "murmer"])
    }

    @Test func deepLinksParse() {
        func link(_ string: String) -> ZeusDeepLink? { ZeusDeepLink.parse(URL(string: string)!) }
        #expect(link("zeus://dictation/start") == .dictationStart)
        #expect(link("ZEUS://Dictation/Stop") == .dictationStop)
        #expect(link("zeus://dictation/toggle") == .dictationToggle)
        #expect(link("zeus://dictation/cancel") == .dictationCancel)
        #expect(link("zeus://dictation/mode?key=email") == .dictationMode("email"))
        #expect(link("zeus://dictation/mode/note") == .dictationMode("note"))
        #expect(link("zeus://dictation/mode") == nil)
        #expect(link("zeus://chat/open?text=Plan%20my%20day") == .chatOpen(prefill: "Plan my day"))
        #expect(link("zeus://chat") == .chatOpen(prefill: nil))
        #expect(link("zeus://chat/new") == .chatNew)
        #expect(link("zeus://prompter") == .prompter)
        #expect(link("zeus://sticky/new?text=Buy%20milk") == .stickyNew(text: "Buy milk"))
        #expect(link("zeus://sticky") == .stickyNew(text: nil))
        #expect(link("zeus://teleprompter/open") == .prompter)
        #expect(link("zeus:dictation/start") == .dictationStart)
        #expect(link("https://dictation/start") == nil)
        #expect(link("zeus://weather") == nil)
    }

    @Test func typingSplitsIntoSafeChunks() {
        #expect(KeystrokeTyping.pieces("hello\nworld") == [.text("hello"), .newline, .text("world")])
        let long = String(repeating: "a", count: 45)
        #expect(KeystrokeTyping.pieces(long) == [.text(String(repeating: "a", count: 20)), .text(String(repeating: "a", count: 20)), .text("aaaaa")])
        // An emoji is two UTF-16 units and is never cut in half.
        let pieces = KeystrokeTyping.pieces(String(repeating: "a", count: 19) + "👍b")
        #expect(pieces == [.text(String(repeating: "a", count: 19)), .text("👍b")])
        #expect(KeystrokeTyping.pieces("") == [])
    }

    @Test func typingDecision() {
        #expect(KeystrokeTyping.shouldType(bundleID: "a", alwaysType: true, typedApps: []))
        #expect(KeystrokeTyping.shouldType(bundleID: "com.vmware.fusion", alwaysType: false, typedApps: KeystrokeTyping.defaultBundleIDs))
        #expect(!KeystrokeTyping.shouldType(bundleID: "com.apple.mail", alwaysType: false, typedApps: KeystrokeTyping.defaultBundleIDs))
        #expect(!KeystrokeTyping.shouldType(bundleID: nil, alwaysType: false, typedApps: ["x"]))
    }

    @Test func microphoneChoiceFallsBackToDefault() {
        let devices = [MicrophoneDevice(uid: "built-in", name: "MacBook Pro Microphone", isDefault: true),
                       MicrophoneDevice(uid: "usb", name: "Shure MV7")]
        #expect(MicrophoneDevice.resolve(savedUID: "usb", devices: devices)?.uid == "usb")
        #expect(MicrophoneDevice.resolve(savedUID: "gone", devices: devices)?.uid == "built-in")
        #expect(MicrophoneDevice.resolve(savedUID: nil, devices: devices)?.uid == "built-in")
        #expect(MicrophoneDevice.resolve(savedUID: nil, devices: []) == nil)
    }

    @Test func micLevelAndVerdict() {
        #expect(MicLevel.level([]) == 0)
        #expect(MicLevel.level([Float](repeating: 0.001, count: 100)) == 0)
        #expect(MicLevel.level([Float](repeating: 0.5, count: 100)) == 1)
        let mid = MicLevel.level([Float](repeating: 0.05, count: 100))
        #expect(mid > 0.4 && mid < 0.5)
        #expect(MicLevel.verdict(peak: 0.02).hasPrefix("Too quiet"))
        #expect(MicLevel.verdict(peak: 0.5) == "Sounds good.")
        #expect(MicLevel.verdict(peak: 1).hasPrefix("Very loud"))
    }
}
