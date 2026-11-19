import Foundation

/// Last-resort local fallback when Jev gave no answer: Ollama (qwen2.5:7b) asked for JSON, one call per
/// request, mapped back into System One answers. Choices get the model's pick at a flat 0.6
/// confidence because Ollama gives no calibrated probabilities.
public struct OllamaDecision: DecisionProvider {
    public let source = Decision.Source.ollama
    let endpoint: URL
    let model: String
    let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(model: String = "qwen2.5:7b", endpoint: URL = URL(string: "http://127.0.0.1:11434/api/generate")!,
                transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
        self.model = model; self.endpoint = endpoint; self.transport = transport
    }

    public func prompt(for request: SystemOneRequest) -> String {
        var lines = ["State: \(request.state.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))",
                     "Answer every question. Reply with one JSON object keyed by question id."]
        for (id, q) in request.questions.sorted(by: { $0.key < $1.key }) {
            switch q.type {
            case .choice: lines.append("\(id): \(q.instructions) Pick exactly one of: \((q.choices ?? [:]).keys.sorted().joined(separator: ", ")).")
            case .noul: lines.append("\(id): \(q.instructions) Reply with a probability from 0 to 1.")
            case .score: lines.append("\(id): \(q.instructions) Reply with a level number from 0 to \(max(0, (q.levels?.count ?? 1) - 1)).")
            }
        }
        return lines.joined(separator: "\n")
    }

    public func decide(_ body: SystemOneRequest) async throws -> Decision {
        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt(for: body), "format": "json", "stream": false])
        let data: Data
        do { (data, _) = try await transport(request) } catch { throw DecisionError.unavailable("ollama") }
        guard let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = outer["response"] as? String,
              let inner = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw DecisionError.badResponse }
        var answers: [String: SystemOneAnswer] = [:]
        for (id, q) in body.questions {
            switch q.type {
            case .choice:
                if let pick = inner[id] as? String, q.choices?[pick] != nil { answers[id] = SystemOneAnswer(type: "choice", choice: pick, confidence: 0.6) }
            case .noul:
                if let n = (inner[id] as? NSNumber)?.doubleValue { answers[id] = SystemOneAnswer(type: "noul", noul: min(1, max(0, n))) }
            case .score:
                if let s = (inner[id] as? NSNumber)?.doubleValue { answers[id] = SystemOneAnswer(type: "score", confidence: 0.6, score: s) }
            }
        }
        guard !answers.isEmpty else { throw DecisionError.badResponse }
        return Decision(source: .ollama, answers: answers)
    }
}
