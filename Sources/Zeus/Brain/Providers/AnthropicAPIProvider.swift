import Foundation
import ZeusCore

/// Direct Anthropic Messages API (Haiku/Sonnet fast tier). Uses `assistant.key.anthropic` from the
/// Keychain — Tony's personal key, separate from the Claude CLI subscription and QA ledger.
final class AnthropicAPIProvider: BrainProvider, @unchecked Sendable {
    enum ProviderError: LocalizedError {
        case noKey
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noKey: "No Anthropic API key in the Keychain."
            case .failed(let detail): detail
            }
        }
    }

    let id: ProviderID = .anthropicAPI
    let capabilities: ProviderCapabilities = [.streaming]

    private static let version = "2023-06-01"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    nonisolated static var hasKey: Bool {
        Keychain.get("assistant.key.anthropic")?.isEmpty == false
    }

    /// Opens (or keeps) the HTTPS connection with a free metadata call, so the first real question
    /// skips TLS and HTTP/2 setup. No tokens are generated, so it costs nothing.
    func prewarm() async {
        guard let key = Keychain.get("assistant.key.anthropic"), !key.isEmpty else { return }
        var urlRequest = URLRequest(url: Self.warmEndpoint, timeoutInterval: 8)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        if let (_, response) = try? await BrainHTTP.session.data(for: urlRequest),
           let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            VoiceLog.log("brain", "engine=anthropic-api prewarm=ok")
        }
    }

    private static let warmEndpoint = URL(string: "https://api.anthropic.com/v1/models?limit=1")!

    static func prewarmIfNeeded() {
        Task.detached { await AnthropicAPIProvider().prewarm() }
    }

    func healthCheck() async -> ProviderHealth {
        Self.hasKey ? .ready(version: "claude-haiku-4-5") : .notLoggedIn(hint: "Add an Anthropic key in Settings")
    }

    private let inFlightLock = NSLock()
    private var inFlight: [UUID: Task<Void, Never>] = [:]

    /// Cancels the request for this turn; the stream then finishes with a CancellationError.
    func cancel(turn: UUID) async {
        let task = inFlightLock.withLock { inFlight.removeValue(forKey: turn) }
        task?.cancel()
    }

    func send(_ request: BrainRequest) -> AsyncThrowingStream<BrainEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let key = Keychain.get("assistant.key.anthropic"), !key.isEmpty else {
                continuation.finish(throwing: ProviderError.noKey)
                return
            }
            var messages: [[String: String]] = []
            for exchange in request.history.suffix(6) {
                messages.append(["role": "user", "content": exchange.user])
                messages.append(["role": "assistant", "content": exchange.assistant])
            }
            messages.append(["role": "user", "content": CLIEngineProvider.prompt(for: request)])
            let fastModel = ModelCap.httpModel(.anthropic, tier: .fast) ?? "claude-haiku-4-5"
            let deepModel = ModelCap.httpModel(.anthropic, tier: .deep) ?? "claude-sonnet-4-5"
            // Deep answers keep one plain try on Sonnet; spoken answers try the lean Haiku first.
            let attempts: [(model: String, lean: Bool)] = request.deep
                ? [(deepModel, false)]
                : AnthropicVoiceBody.fastAttempts(current: fastModel)
            let timeout: TimeInterval = request.deep ? 45 : (request.firstTextBudget ?? 45)
            let maxTokens = request.deep ? 1024 : 512
            let finalMessages = messages
            let system = request.systemPrompt
            func makeRequest(model: String, lean: Bool) -> URLRequest? {
                let body = AnthropicVoiceBody.make(model: model, system: system, messages: finalMessages, maxTokens: maxTokens, lean: lean)
                guard JSONSerialization.isValidJSONObject(body), let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
                var urlRequest = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
                urlRequest.httpMethod = "POST"
                urlRequest.httpBody = payload
                urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
                urlRequest.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
                urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
                return urlRequest
            }

            let started = Date()
            let task = Task {
                var firstTokenLogged = false
                var sawText = false
                var sawStop = false
                var stopReason: String?
                var model = attempts[0].model
                do {
                    var opened: URLSession.AsyncBytes?
                    for (index, attempt) in attempts.enumerated() {
                        guard let urlRequest = makeRequest(model: attempt.model, lean: attempt.lean) else {
                            continuation.finish(throwing: ProviderError.failed("Could not build the request."))
                            return
                        }
                        model = attempt.model
                        let (bytes, response) = try await BrainHTTP.session.bytes(for: urlRequest)
                        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                            var data = Data()
                            for try await byte in bytes { data.append(byte); if data.count > 4096 { break } }
                            if AnthropicVoiceBody.shouldRetry(status: http.statusCode), index + 1 < attempts.count {
                                VoiceLog.log("brain", "engine=anthropic-api model=\(attempt.model) lean=\(attempt.lean) HTTP \(http.statusCode); trying the next form")
                                continue
                            }
                            let message = String(decoding: data, as: UTF8.self).prefix(200)
                            continuation.finish(throwing: ProviderError.failed("Anthropic HTTP \(http.statusCode): \(message)"))
                            return
                        }
                        opened = bytes
                        break
                    }
                    guard let bytes = opened else {
                        continuation.finish(throwing: ProviderError.failed("Anthropic gave no answer."))
                        return
                    }
                    for try await line in bytes.lines {
                        // Cancelled turn: stop reading so the connection closes and no more tokens are paid for.
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonText = String(line.dropFirst(6))
                        if jsonText == "[DONE]" { break }
                        guard let data = jsonText.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else { continue }
                        if type == "error" {
                            let detail = ((json["error"] as? [String: Any])?["message"] as? String) ?? "stream error"
                            throw ProviderError.failed("Anthropic stream error: \(detail.prefix(200))")
                        }
                        if type == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String, !text.isEmpty {
                            if !firstTokenLogged {
                                firstTokenLogged = true
                                let ms = Int(Date().timeIntervalSince(started) * 1000)
                                VoiceLog.log("brain", "engine=anthropic-api model=\(model) first_token_ms=\(ms)")
                                NSLog("[ZEUS] brain: engine=anthropic-api model=%@ first_token_ms=%d", model, ms)
                            }
                            sawText = true
                            continuation.yield(.textDelta(text))
                        }
                        if type == "message_delta", let delta = json["delta"] as? [String: Any],
                           let reason = delta["stop_reason"] as? String {
                            stopReason = reason
                        }
                        if type == "message_stop" { sawStop = true; break }
                    }
                    try Task.checkCancellation()
                    // Only message_stop completes an answer; EOF before it (even after some text) is a failure.
                    guard sawStop else {
                        throw ProviderError.failed(sawText
                            ? "Anthropic answer was cut off: the stream ended early."
                            : "Anthropic stream ended without an answer.")
                    }
                    if stopReason == "max_tokens" {
                        throw ProviderError.failed("Anthropic answer was cut off: it hit the length limit.")
                    }
                    let totalMs = Int(Date().timeIntervalSince(started) * 1000)
                    VoiceLog.log("brain", "engine=anthropic-api model=\(model) done_ms=\(totalMs)")
                    continuation.yield(.done(nil))
                    continuation.finish()
                } catch let error as ProviderError {
                    continuation.finish(throwing: error)
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        continuation.finish(throwing: ProviderError.failed(error.localizedDescription))
                    }
                }
            }
            let turn = request.turn
            inFlightLock.withLock { inFlight[turn] = task }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.inFlightLock.withLock { _ = self?.inFlight.removeValue(forKey: turn) }
            }
        }
    }
}
