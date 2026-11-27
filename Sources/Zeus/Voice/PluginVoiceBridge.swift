import AVFoundation
import Foundation
import ZeusCore

private final class StreamedFlag: @unchecked Sendable {
    var value = false
}

enum ProviderClipFile {
    static func write(_ wav: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-voice-\(UUID().uuidString).wav")
        try wav.write(to: url)
        return url
    }
}

/// Plays provider audio. Playback on a Mac is MAC-PENDING until it is run there.
@MainActor
enum PluginAudioPlay {
    private static let synthesizer = AVSpeechSynthesizer()
    private static let delegate = ProviderPlayerDelegate()
    private static var player: AVAudioPlayer?

    /// Starts a clip. A WAV file is written off the main actor, then the engine starts here.
    @discardableResult
    static func play(_ data: Data) async -> Bool {
        guard !data.isEmpty else { return false }
        if data.starts(with: Data("RIFF".utf8)) {
            let captured = data
            guard let url = await Task.detached(priority: .userInitiated, operation: {
                try? ProviderClipFile.write(captured)
            }).value else { return false }
            return playFile(at: url)
        }
        guard let next = try? AVAudioPlayer(data: data) else { return false }
        next.delegate = delegate
        player = next
        ProviderPlaybackGate.shared.begin(player: ObjectIdentifier(next))
        let started = next.play()
        if !started { ProviderPlaybackGate.shared.endPlayer(ObjectIdentifier(next)) }
        return started
    }

    static func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        for engine in engines { engine.stop() }
        engines.removeAll()
        for observer in routeObservers { NotificationCenter.default.removeObserver(observer) }
        routeObservers.removeAll()
        for file in ProviderEngineTracker.shared.stopAll() {
            try? FileManager.default.removeItem(at: file)
        }
        ProviderPlaybackGate.shared.reset()
    }

    /// One more chunk of a clip that is already being spoken, or the first chunk.
    static func enqueue(_ data: Data) async {
        guard !data.isEmpty else { return }
        _ = await play(data)
    }

    /// Schedules a WAV on `AVAudioEngine`. The file already exists.
    private static func playFile(at url: URL) -> Bool {
        do {
            let file = try AVAudioFile(forReading: url)
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            try engine.start()
            ProviderEngineTracker.shared.started(url)
            let token = ProviderPlaybackGate.shared.begin()
            let finish = WavFinish(engine: engine, url: url, token: token)
            node.scheduleFile(file, at: nil) { finish.complete() }
            node.play()
            engines.append(engine)
            let observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
                MainActor.assumeIsolated {
                    engine.stop()
                    ProviderPlaybackGate.shared.reset()
                    try? FileManager.default.removeItem(at: url)
                }
            }
            routeObservers.append(observer)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    static func speakLocally(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Speaker.bestVoice(for: "en")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    fileprivate static func drop(_ engine: AVAudioEngine) {
        engines.removeAll { $0 === engine }
    }

    private static var engines: [AVAudioEngine] = []
    private static var routeObservers: [NSObjectProtocol] = []
}

private final class WavFinish: @unchecked Sendable {
    let engine: AVAudioEngine
    let url: URL
    let token: Int
    init(engine: AVAudioEngine, url: URL, token: Int) {
        self.engine = engine
        self.url = url
        self.token = token
    }

    func complete() {
        let remove = ProviderEngineTracker.shared.finished(url)
        let engine = self.engine
        let token = self.token
        Task { @MainActor in
            engine.stop()
            PluginAudioPlay.drop(engine)
            if let remove { try? FileManager.default.removeItem(at: remove) }
            ProviderPlaybackGate.shared.end(token)
        }
    }
}

@MainActor
private final class ProviderPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        ProviderPlaybackGate.shared.endPlayer(ObjectIdentifier(player))
    }
}

/// A local stand-in that does not play. The talk path plays the local voice itself when this bridge
/// asks it to fall back, so a turn is not spoken twice.
struct MarkerLocalVoice: LocalVoiceSpeaking {
    func speak(_ text: String) async -> Data { Data([0x01]) }
}

/// Marks that the Mac voice is the second offline step. `Speaker` plays it with `AVSpeechSynthesizer`
/// after the local voice. This value does not start audio by itself.
struct MacSystemSpeech: SystemSpeechSpeaking {
    func speak(_ text: String) async -> Data { Data("mac-voice".utf8) }
}

/// Uses a saved voice provider for a talk turn. The local voice, and every existing engine, is unchanged
/// until a provider is selected.
@MainActor
enum PluginVoiceBridge {
    enum Result: Sendable {
        case passthrough
        case spoken(engine: UltronEngine, voice: String, reason: String, firstAudioMs: Int?)
        case localFallback(reason: String)
    }

    private static var session: VoiceProviderSession?

    static func sharedSession() -> VoiceProviderSession {
        if let session { return session }
        let fake = VoiceProviderE2E.isEnabled()
        if fake { VoiceProviderFakeProtocol.failSynthesis = VoiceProviderE2E.failsSynthesis() }
        let log = ProviderLog { line in NSLog("[ZEUS] voice-provider %@", line) }
        let serviceName: @Sendable (String) -> String = fake
            ? { VoiceProviderE2E.service(for: $0) }
            : { _ in VoiceProviderAccounts.service }
        let keyAccount: @Sendable (String) -> String = fake
            ? { _ in ProviderCredentialLocation.account }
            : { VoiceProviderAccounts.keyAccount(for: $0) }
        let created = VoiceProviderSession(
            store: KeychainCredentialStore(),
            transport: URLSessionProviderTransport(protocolClasses: fake ? [VoiceProviderFakeProtocol.self] : [], log: log),
            local: MarkerLocalVoice(),
            preferences: VoiceProviderPreferences(defaults: .standard),
            log: log,
            serviceName: serviceName,
            keyAccount: keyAccount,
            system: MacSystemSpeech()
        )
        session = created
        return created
    }

    /// Synchronous. `stop` calls this before the sentence pump resumes, so a cancelled utterance cannot play.
    static func cancelSpeaking() {
        session?.utterances.cancelActive()
        let current = session
        Task { await current?.cancel() }
    }

    static func speak(_ text: String) async -> Result {
        let choice = VoiceProviderPreferences(defaults: .standard).choice
        guard case .provider = choice else { return .passthrough }
        let session = sharedSession()
        let utterance = session.utterances.begin()
        let streamed = StreamedFlag()
        let outcome = await session.speak(text, onPlaybackChunk: { chunk in
            streamed.value = true
            await PluginAudioPlay.enqueue(chunk)
        }, gate: session.utterances, utterance: utterance)
        guard !session.utterances.isCancelled(utterance), !Task.isCancelled else {
            return .localFallback(reason: "Speaking cancelled.")
        }
        switch outcome.route {
        case .cloud(let providerID, let voiceID):
            if !streamed.value {
                guard !session.utterances.isCancelled(utterance), !Task.isCancelled else {
                    return .localFallback(reason: "Speaking cancelled.")
                }
                guard await PluginAudioPlay.play(outcome.audio) else { return .localFallback(reason: outcome.statusLine) }
            }
            let engine: UltronEngine = providerID == ElevenLabsTTSAdapter.id ? .elevenLabs : .system
            return .spoken(engine: engine, voice: voiceID, reason: "voice provider \(providerID)", firstAudioMs: outcome.firstAudioMs)
        case .local, .cancelled:
            return .localFallback(reason: outcome.statusLine)
        }
    }
}
