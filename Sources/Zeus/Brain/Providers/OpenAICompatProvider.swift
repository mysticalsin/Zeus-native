import Foundation
import ZeusCore

/// OpenAI-compatible streaming chat. Ollama on this Mac is the default. Anthropic stays on its own provider.
/// A key, when one is set, is read from the Keychain and never logged.
final class OpenAICompatProvider: BrainProvider, @unchecked Sendable {
    let id: ProviderID
    let capabilities: ProviderCapabilities = [.streaming]
    let baseURL: URL
    let model: String
    let key: String?
    let keepAlive: String?

    private let lock = NSLock()
    private var running: [UUID: Task<Void, Never>] = [:]

    init(id: ProviderID, baseURL: URL, model: String, key: String?, keepAlive: String?) {
        self.id = id
        self.baseURL = baseURL
        self.model = model
        self.key = key
        self.keepAlive = keepAlive
    }

    static func ollama(model: String = ModelCap.httpModel(.ollama, tier: .fast) ?? "llama3.2") -> OpenAICompatProvider {
        OpenAICompatProvider(id: .ollama, baseURL: URL(string: "http://127.0.0.1:11434/v1")!, model: model, key: nil, keepAlive: "45m")
    }

    static func openAI(model: String, key: String) -> OpenAICompatProvider {
        OpenAICompatProvider(id: .openAIAPI, baseURL: URL(string: "https://api.openai.com/v1")!, model: model, key: key, keepAlive: nil)
    }

    func healthCheck() async -> ProviderHealth { .ready(version: model) }

    func cancel(turn: UUID) async {
        let task = lock.withLock { running.removeValue(forKey: turn) }
        task?.cancel()
    }

    /// One token, so the local model is already loaded the next time someone asks. Failures are ignored.
    func prewarm() async {
        var request = urlRequest(prompt: "ok", system: nil, maxTokens: 1)
        request.timeoutInterval = 2
        _ = try? await BrainHTTP.session.data(for: request)
    }

    /// Opens the TLS and HTTP/2 connection to a cloud API with a free metadata call (no tokens).
    func warmConnection() async {
        guard id == .openAIAPI, let key, !key.isEmpty else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"), timeoutInterval: 6)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let (_, response) = try? await BrainHTTP.session.data(for: request),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            VoiceLog.log("brain", "engine=openai prewarm=ok")
        }
    }

    func send(_ request: BrainRequest) -> AsyncThrowingStream<BrainEvent, Error> {
        AsyncThrowingStream { continuation in
            guard ModelCap.gatedHTTPModel(model) != nil else {
                continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed("That model is over the cap."))
                return
            }
            let task = Task { [weak self] in
                guard let self else { return }
                let started = Date()
                var firstTokenLogged = false
                do {
                    let (bytes, response) = try await BrainHTTP.session.bytes(for: self.urlRequest(prompt: request.transcript, system: request.systemPrompt, maxTokens: request.deep ? 1024 : 512))
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte); if data.count > 2048 { break } }
                        continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed("HTTP \(http.statusCode)"))
                        return
                    }
                    var pending = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        pending += line + "\n"
                        for piece in OpenAICompat.parse(chunk: pending) {
                            switch piece {
                            case .delta(let text):
                                if !firstTokenLogged {
                                    firstTokenLogged = true
                                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                                    VoiceLog.log("brain", "engine=\(self.id.rawValue) model=\(self.model) first_token_ms=\(ms)")
                                }
                                continuation.yield(.textDelta(text))
                            case .done: break
                            case .failure(let message):
                                continuation.finish(throwing: ClaudeCLIProvider.ProviderError.failed(message))
                                return
                            }
                        }
                        pending = ""
                    }
                    continuation.yield(.done(nil))
                    let done = Int(Date().timeIntervalSince(started) * 1000)
                    VoiceLog.log("brain", "engine=\(self.id.rawValue) model=\(self.model) done_ms=\(done)")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                self.lock.withLock { _ = self.running.removeValue(forKey: request.turn) }
            }
            lock.withLock { running[request.turn] = task }
            continuation.onTermination = { [weak self] _ in
                let stored = self?.lock.withLock { self?.running.removeValue(forKey: request.turn) }
                stored?.cancel()
            }
        }
    }

    private func urlRequest(prompt: String, system: String?, maxTokens: Int) -> URLRequest {
        let url = baseURL.appendingPathComponent("chat/completions")
        let timeout: TimeInterval = id == .ollama ? 8 : 20
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let body = OpenAICompat.body(model: model, prompt: prompt, system: system, keepAlive: keepAlive, maxTokens: maxTokens)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}
