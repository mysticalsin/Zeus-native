import Foundation
import ZeusCore

/// Warm connections for the cloud voices. The talk key calls these (never launch): a free metadata GET opens
/// the TLS and HTTP/2 connection on the same session the first sentence's request uses. No audio is
/// generated, no credits are spent, and nothing is logged but the host and the outcome.
enum TTSHTTP {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastWarm: [String: Date] = [:]
    static let window: TimeInterval = 45

    private static func due(_ name: String) -> Bool {
        lock.withLock {
            let now = Date()
            if let last = lastWarm[name], now.timeIntervalSince(last) < window { return false }
            lastWarm[name] = now
            return true
        }
    }

    static func warmElevenLabs() async {
        guard due("elevenlabs"), let route = ElevenLabsVoice.loadRoutes().first else { return }
        var request: URLRequest
        switch route.route {
        case .direct(let apiKey):
            request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/models")!, timeoutInterval: 6)
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        case .worker(let url, _):
            request = URLRequest(url: url, timeoutInterval: 6)
        }
        request.httpMethod = "GET"
        // The response does not matter: the connection stays open for the sentence request.
        let reached = (try? await Speaker.elevenLabsSession.data(for: request)) != nil
        VoiceLog.log("voice", "tts prewarm engine=elevenlabs ok=\(reached)")
    }

    static func warmOpenAI() async {
        guard due("openai"), let config = OpenAITTSVoice.config(streaming: true) else { return }
        var request = URLRequest(url: config.baseURL.appendingPathComponent("models"), timeoutInterval: 6)
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let reached = (try? await Speaker.openAISession.data(for: request)) != nil
        VoiceLog.log("voice", "tts prewarm engine=openai ok=\(reached)")
    }
}
