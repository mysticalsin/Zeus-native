import AVFoundation
import Foundation
import ZeusCore

/// Plays provider audio. Playback on a Mac is MAC-PENDING until it is run there.
@MainActor
enum PluginAudioPlay {
    private static let synthesizer = AVSpeechSynthesizer()
    private static var player: AVAudioPlayer?

    @discardableResult
    static func play(_ data: Data) -> Bool {
        guard !data.isEmpty, let next = try? AVAudioPlayer(data: data) else { return false }
        player = next
        return next.play()
    }

    static func speakLocally(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}

/// A local stand-in that does not play. The talk path plays the local voice itself when this bridge
/// asks it to fall back, so a turn is not spoken twice.
struct MarkerLocalVoice: LocalVoiceSpeaking {
    func speak(_ text: String) async -> Data { Data([0x01]) }
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
        let created = VoiceProviderSession(
            store: KeychainCredentialStore(),
            transport: URLSessionProviderTransport(),
            local: MarkerLocalVoice(),
            preferences: VoiceProviderPreferences(defaults: .standard)
        )
        session = created
        return created
    }

    static func speak(_ text: String) async -> Result {
        let choice = VoiceProviderPreferences(defaults: .standard).choice
        guard case .provider = choice else { return .passthrough }
        let outcome = await sharedSession().speak(text)
        switch outcome.route {
        case .cloud(let providerID, let voiceID):
            guard PluginAudioPlay.play(outcome.audio) else { return .localFallback(reason: outcome.statusLine) }
            let engine: UltronEngine = providerID == ElevenLabsTTSAdapter.id ? .elevenLabs : .system
            return .spoken(engine: engine, voice: voiceID, reason: "voice provider \(providerID)", firstAudioMs: outcome.firstAudioMs)
        case .local, .cancelled:
            return .localFallback(reason: outcome.statusLine)
        }
    }
}
