import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the answer trim inside `PolyglotPipeline.translate`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
/// The heard trim in `process` is not this box.
/// `PolyglotTextFilter.isPhantom` still trims a union with punctuation.
@Suite("Polyglot answer box")
struct PolyglotAnswerBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PolyglotAnswerBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PolyglotAnswerBox.blankScalars.count == 5)
        #expect(PolyglotAnswerBox.blankScalars.contains(" "))
        #expect(PolyglotAnswerBox.blankScalars.contains("\t"))
        #expect(PolyglotAnswerBox.blankScalars.contains("\n"))
        #expect(PolyglotAnswerBox.blankScalars.contains("\r"))
        #expect(PolyglotAnswerBox.blankScalars.contains("\u{00A0}"))
        #expect(!PolyglotAnswerBox.blankScalars.contains("\u{200B}"))
        #expect(!PolyglotAnswerBox.blankScalars.contains("\u{000B}"))
        #expect(!PolyglotAnswerBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedAnswer() {
        #expect(PolyglotAnswerBox.trimmedAnswer("\u{200B}") == "\u{200B}")
        #expect(PolyglotAnswerBox.trimmedAnswer(" \u{200B} ") == "\u{200B}")
        #expect(PolyglotAnswerBox.trimmedAnswer("\t\u{200B}\n") == "\u{200B}")
        #expect(PolyglotAnswerBox.trimmedAnswer("\u{200B}hello") == "\u{200B}hello")
        #expect(PolyglotAnswerBox.trimmedAnswer("hello\u{200B}") == "hello\u{200B}")
        #expect(PolyglotAnswerBox.trimmedAnswer(" \t\n\r\u{00A0}") == "")
        #expect(PolyglotAnswerBox.trimmedAnswer("") == "")
        #expect(PolyglotAnswerBox.trimmedAnswer("\u{000B}hello") == "\u{000B}hello")
        #expect(PolyglotAnswerBox.trimmedAnswer("\u{3000}hello") == "\u{3000}hello")
        #expect(PolyglotAnswerBox.trimmedAnswer(" \thello\r\n") == "hello")
        #expect(PolyglotAnswerBox.trimmedAnswer("\u{00A0}hello\u{00A0}") == "hello")
        #expect(PolyglotAnswerBox.trimmedAnswer("hello") == "hello")
        #expect(PolyglotAnswerBox.trimmedAnswer("hel\u{200B}lo") == "hel\u{200B}lo")
        #expect(PolyglotAnswerBox.trimmedAnswer("\n") == "")
        #expect(PolyglotAnswerBox.trimmedAnswer("\r") == "")
        #expect(PolyglotAnswerBox.trimmedAnswer("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysWhenTheAnswerIsPublished() async {
        #expect(PolyglotAnswerBox.trimmedAnswer("\u{200B}") == "\u{200B}")
        let kept = await translations([
            "\u{200B}", " \u{200B} ", "\u{200B}hello", "hello\u{200B}", "hel\u{200B}lo",
            "\u{3000}", "\u{000B}", "\u{3000}hello", "\u{000B}hello", "\n\u{200B}\r",
        ])
        #expect(kept.texts == [
            "\u{200B}", " \u{200B} ", "\u{200B}hello", "hello\u{200B}", "hel\u{200B}lo",
            "\u{3000}", "\u{000B}", "\u{3000}hello", "\u{000B}hello", "\n\u{200B}\r",
        ])
        #expect(kept.targets.allSatisfy { $0 == "en" })
        #expect(kept.originals.allSatisfy { $0 == "one two three" })
        #expect(kept.lines.allSatisfy { !$0.isTarget && $0.language == "pt" && $0.side == .system })
        let ordinary = await translations(["  hello  ", "\u{00A0}hello\u{00A0}", "\nhello\r", "hello"])
        #expect(ordinary.texts == ["  hello  ", "\u{00A0}hello\u{00A0}", "\nhello\r", "hello"])
        let dropped = await translations([" \t\n\r\u{00A0}", "\n", "\r", "", "   "])
        #expect(dropped.texts.isEmpty)
        #expect(dropped.lines.count == 5)
        #expect(dropped.lines.allSatisfy { $0.original == "one two three" && $0.translation == nil })
    }
}

private struct AnswerRecognizer: PolyglotRecognizing {
    func transcribe(samples: [Float], language: String?) async throws -> String { "one two three" }
}

private struct AnswerDetector: PolyglotLanguageDetecting {
    func detect(_ text: String) -> (code: String, confidence: Double)? { ("pt", 0.99) }
}

private actor AnswerTranslator: PolyglotTranslating {
    let answer: String
    init(answer: String) { self.answer = answer }
    func status(from source: String, to target: String) async -> PolyglotPackStatus { .installed }
    func translate(_ requests: [PolyglotTranslationRequest], from source: String, to target: String) async throws -> [String] {
        Array(repeating: answer, count: requests.count)
    }
}

private final class AnswerEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [PolyglotEvent] = []
    func add(_ event: PolyglotEvent) { lock.withLock { store.append(event) } }
    var lines: [PolyglotLine] { lock.withLock { store.compactMap { if case .line(let line) = $0 { line } else { nil } } } }
    var translations: [(text: String, target: String)] {
        lock.withLock {
            store.compactMap { if case .translated(_, let text, let target) = $0 { (text, target) } else { nil } }
        }
    }
}

private struct AnswerCaptions {
    var lines: [PolyglotLine]
    var originals: [String]
    var texts: [String]
    var targets: [String]
}

private func speech(_ seconds: Double) -> [Float] {
    (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.31)) * 0.12 }
}

private func silence(_ seconds: Double) -> [Float] {
    Array(repeating: 0, count: Int(seconds * 16_000))
}

private func translations(_ answers: [String]) async -> AnswerCaptions {
    var lines: [PolyglotLine] = []
    var texts: [String] = []
    var targets: [String] = []
    for answer in answers {
        let events = AnswerEvents()
        let pipeline = PolyglotPipeline(
            recognizer: AnswerRecognizer(),
            detector: AnswerDetector(),
            translator: AnswerTranslator(answer: answer),
            target: "en"
        ) { events.add($0) }
        await pipeline.ingest(speech(1) + silence(1), from: .system)
        await pipeline.finish()
        lines.append(contentsOf: events.lines)
        texts.append(contentsOf: events.translations.map(\.text))
        targets.append(contentsOf: events.translations.map(\.target))
    }
    return AnswerCaptions(lines: lines, originals: lines.map(\.original), texts: texts, targets: targets)
}
