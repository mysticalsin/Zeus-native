import AVFoundation
import Foundation
import ZeusCore

/// Plays provider audio. Playback on a Mac is MAC-PENDING until it is run there.
@MainActor
enum PluginAudioPlay {
    private static let synthesizer = AVSpeechSynthesizer()
    private static let delegate = ProviderPlayerDelegate()
    private static var player: AVAudioPlayer?
    private static var clips = PlaybackClipBook()
    private static var sleepObservers: [NSObjectProtocol] = []
    private static var routeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    @discardableResult
    static func play(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        armSleep()
        // PlaybackClipBook.replace: the previous clip ends before this one starts.
        retireCurrent()
        if data.starts(with: Data("RIFF".utf8)), playWithEngine(data) { return true }
        guard let next = try? AVAudioPlayer(data: data) else { return false }
        next.delegate = delegate
        player = next
        _ = clips.begin()
        ProviderPlaybackGate.shared.begin(player: ObjectIdentifier(next))
        let started = next.play()
        if !started {
            ProviderPlaybackGate.shared.endPlayer(ObjectIdentifier(next))
            clips.interrupt()
            player = nil
        }
        return started
    }

    static func stop() {
        retireCurrent()
    }

    /// Sleep or a route change. The file callback may never run, so the gate is reset here.
    static func noteInterrupted() {
        retireCurrent()
    }

    private static func retireCurrent() {
        player?.stop()
        player = nil
        for engine in engines { engine.stop() }
        for token in routeObservers.values { NotificationCenter.default.removeObserver(token) }
        routeObservers.removeAll()
        engines.removeAll()
        for file in ProviderEngineTracker.shared.stopAll() {
            try? FileManager.default.removeItem(at: file)
        }
        clips.interrupt()
        ProviderPlaybackGate.shared.reset()
    }

    private static func armSleep() {
        guard sleepObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { noteInterrupted() }
            }
            sleepObservers.append(token)
        }
    }

    /// Schedules a WAV on `AVAudioEngine`. MP3 from a cloud provider uses `AVAudioPlayer`.
    private static func playWithEngine(_ wav: Data) -> Bool {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-voice-\(UUID().uuidString).wav")
        do {
            try wav.write(to: url)
            let file = try AVAudioFile(forReading: url)
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            try engine.start()
            ProviderEngineTracker.shared.started(url)
            let token = ProviderPlaybackGate.shared.begin()
            _ = clips.begin()
            let watched = engine
            let route = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: watched, queue: .main
            ) { _ in
                MainActor.assumeIsolated { noteInterrupted() }
            }
            routeObservers[ObjectIdentifier(watched)] = route
            let finish = WavFinish(engine: engine, url: url, token: token)
            node.scheduleFile(file, at: nil) { finish.complete() }
            node.play()
            engines.append(engine)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    static func speakLocally(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    fileprivate static func drop(_ engine: AVAudioEngine) {
        engines.removeAll { $0 === engine }
    }

    private static var engines: [AVAudioEngine] = []
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
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
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
        let created = VoiceProviderSession(
            store: KeychainCredentialStore(),
            transport: URLSessionProviderTransport(protocolClasses: fake ? [VoiceProviderFakeProtocol.self] : [], log: log),
            local: MarkerLocalVoice(),
            preferences: VoiceProviderPreferences(defaults: .standard),
            log: log,
            serviceName: fake ? { VoiceProviderE2E.service(for: $0) } : { _ in VoiceProviderAccounts.service },
            keyAccount: fake ? { _ in ProviderCredentialLocation.account } : { VoiceProviderAccounts.keyAccount(for: $0) },
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
        let outcome = await session.speak(text, gate: session.utterances, utterance: utterance)
        guard !session.utterances.isCancelled(utterance), !Task.isCancelled else {
            return .localFallback(reason: "Speaking cancelled.")
        }
        switch outcome.route {
        case .cloud(let providerID, let voiceID):
            guard !session.utterances.isCancelled(utterance), !Task.isCancelled else {
                return .localFallback(reason: "Speaking cancelled.")
            }
            guard PluginAudioPlay.play(outcome.audio) else { return .localFallback(reason: outcome.statusLine) }
            let engine: UltronEngine = providerID == ElevenLabsTTSAdapter.id ? .elevenLabs : .system
            return .spoken(engine: engine, voice: voiceID, reason: "voice provider \(providerID)", firstAudioMs: outcome.firstAudioMs)
        case .local, .cancelled:
            return .localFallback(reason: outcome.statusLine)
        }
    }
}
