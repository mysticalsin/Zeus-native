import Foundation

/// Isolated caption check for the real Polyglot pipeline. Synthetic samples only: no microphone,
/// no language-pack download, no network. Translation is reported unsupported; the heard line must remain.

private func speech(seconds: Double) -> [Float] {
    (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.31)) * 0.12 }
}

private func silence(seconds: Double) -> [Float] { Array(repeating: 0, count: Int(seconds * 16_000)) }

private actor Script {
    let text: String
    init(_ text: String) { self.text = text }
    func next() -> String { text }
}

private struct FixedRecognizer: PolyglotRecognizing {
    let script: Script
    func transcribe(samples: [Float], language: String?) async throws -> String { await script.next() }
}

private struct FixedDetector: PolyglotLanguageDetecting {
    func detect(_ text: String) -> (code: String, confidence: Double)? {
        text == "Vamos começar a reunião agora." ? ("pt", 0.97) : nil
    }
}

private actor UnsupportedTranslator: PolyglotTranslating {
    private(set) var calls = 0
    func status(from source: String, to target: String) async -> PolyglotPackStatus { .unsupported }
    func translate(_ requests: [PolyglotTranslationRequest], from source: String, to target: String) async throws -> [String] {
        calls += 1
        return requests.map { _ in "should-not-run" }
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [PolyglotEvent] = []
    func add(_ event: PolyglotEvent) { lock.withLock { store.append(event) } }
    var all: [PolyglotEvent] { lock.withLock { store } }
}

@main
enum PolyglotCaptionHarness {
    static func main() async {
        let heard = "Vamos começar a reunião agora."
        let translator = UnsupportedTranslator()
        let box = EventBox()
        let pipeline = PolyglotPipeline(
            recognizer: FixedRecognizer(script: Script(heard)),
            detector: FixedDetector(),
            translator: translator,
            target: "en",
            expected: ["pt", "es", "en"]
        ) { box.add($0) }
        await pipeline.ingest(speech(seconds: 1) + silence(seconds: 1), from: .system)
        await pipeline.finish()

        let events = box.all
        var transcript = PolyglotTranscript()
        for event in events { transcript.applySettled(event) }
        let lines = events.compactMap { event -> PolyglotLine? in
            if case .line(let line) = event { line } else { nil }
        }
        let translations = events.compactMap { event -> String? in
            if case .translated(_, let text, _) = event { text } else { nil }
        }
        let failed = events.contains { event in
            if case .failed(let text) = event { text.contains("Portuguese") } else { false }
        }
        var problems: [String] = []
        if lines.count != 1 { problems.append("line count \(lines.count)") }
        if lines.first?.original != heard { problems.append("original missing") }
        if lines.first?.language != "pt" { problems.append("language \(lines.first?.language ?? "nil")") }
        if !translations.isEmpty { problems.append("translation emitted") }
        if !failed { problems.append("unsupported pair was not reported") }
        if await translator.calls != 0 { problems.append("translator ran") }
        if transcript.lines.count != 1 || transcript.lines.first?.original != heard || transcript.lines.first?.translation != nil {
            problems.append("transcript did not keep the heard line")
        }
        if CommandLine.arguments.count > 1 {
            let source = (try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)) ?? ""
            if source.isEmpty { problems.append("controller source unreadable") }
            if source.contains("Live translation needs macOS 26") { problems.append("start still refuses captions before macOS 26") }
            if !source.contains("transcript.applySettled(event)") { problems.append("controller does not apply settled captions") }
        }
        if problems.isEmpty {
            print("PASS polyglot unsupported pair keeps the heard line")
            print("OK 1")
        } else {
            fputs("FAIL \(problems.joined(separator: "; "))\n", stderr)
            Foundation.exit(1)
        }
    }
}
