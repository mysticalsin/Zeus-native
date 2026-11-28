import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the heard trim inside `PolyglotPipeline.process`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
/// The answer trim in `translate` still uses `CharacterSet.whitespacesAndNewlines`.
/// `PolyglotTextFilter.isPhantom` still trims a union with punctuation.
@Suite("Polyglot heard box")
struct PolyglotHeardBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PolyglotHeardBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PolyglotHeardBox.blankScalars.count == 5)
        #expect(PolyglotHeardBox.blankScalars.contains(" "))
        #expect(PolyglotHeardBox.blankScalars.contains("\t"))
        #expect(PolyglotHeardBox.blankScalars.contains("\n"))
        #expect(PolyglotHeardBox.blankScalars.contains("\r"))
        #expect(PolyglotHeardBox.blankScalars.contains("\u{00A0}"))
        #expect(!PolyglotHeardBox.blankScalars.contains("\u{200B}"))
        #expect(!PolyglotHeardBox.blankScalars.contains("\u{000B}"))
        #expect(!PolyglotHeardBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedHeardText() {
        #expect(PolyglotHeardBox.trimmedHeard("\u{200B}") == "\u{200B}")
        #expect(PolyglotHeardBox.trimmedHeard(" \u{200B} ") == "\u{200B}")
        #expect(PolyglotHeardBox.trimmedHeard("\t\u{200B}\n") == "\u{200B}")
        #expect(PolyglotHeardBox.trimmedHeard("\u{200B}hello") == "\u{200B}hello")
        #expect(PolyglotHeardBox.trimmedHeard("hello\u{200B}") == "hello\u{200B}")
        #expect(PolyglotHeardBox.trimmedHeard(" \t\n\r\u{00A0}") == "")
        #expect(PolyglotHeardBox.trimmedHeard("") == "")
        #expect(PolyglotHeardBox.trimmedHeard("\u{000B}hello") == "\u{000B}hello")
        #expect(PolyglotHeardBox.trimmedHeard("\u{3000}hello") == "\u{3000}hello")
        #expect(PolyglotHeardBox.trimmedHeard(" \thello\r\n") == "hello")
        #expect(PolyglotHeardBox.trimmedHeard("\u{00A0}hello\u{00A0}") == "hello")
        #expect(PolyglotHeardBox.trimmedHeard("hello") == "hello")
        #expect(PolyglotHeardBox.trimmedHeard("hel\u{200B}lo") == "hel\u{200B}lo")
        #expect(PolyglotHeardBox.trimmedHeard("\n") == "")
        #expect(PolyglotHeardBox.trimmedHeard("\r") == "")
        #expect(PolyglotHeardBox.trimmedHeard("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysWhenTheHeardLineIsTrimmed() async {
        #expect(PolyglotHeardBox.trimmedHeard("\u{200B}") == "\u{200B}")
        let kept = await captions(["\u{200B}hello", "hello\u{200B}", "hel\u{200B}lo", "\u{3000}hello", "\u{000B}hello"])
        #expect(kept.originals == ["\u{200B}hello", "hello\u{200B}", "hel\u{200B}lo", "\u{3000}hello", "\u{000B}hello"])
        #expect(kept.detected == ["\u{200B}hello", "hello\u{200B}", "hel\u{200B}lo", "\u{3000}hello", "\u{000B}hello"])
        #expect(kept.lines.allSatisfy { $0.isTarget && $0.language == "en" && $0.side == .system })
        let ordinary = await captions([" \thello\r\n", "\u{00A0}hello\u{00A0}", "\nhello\r", "hello"])
        #expect(ordinary.originals == ["hello", "hello", "hello", "hello"])
        let dropped = await captions(["\u{200B}", " \t\n\r\u{00A0}", "\n", "\r", "Thanks for watching!"])
        #expect(dropped.originals.isEmpty)
        #expect(dropped.discarded.count == 5)
        #expect(dropped.detected.isEmpty)
    }
}

private struct HeardRecognizer: PolyglotRecognizing {
    let text: String
    func transcribe(samples: [Float], language: String?) async throws -> String { text }
}

private final class HeardDetector: PolyglotLanguageDetecting, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    func detect(_ text: String) -> (code: String, confidence: Double)? {
        lock.withLock { seen.append(text) }
        return ("en", 0.99)
    }
    var texts: [String] { lock.withLock { seen } }
}

private actor HeardTranslator: PolyglotTranslating {
    func status(from source: String, to target: String) async -> PolyglotPackStatus { .installed }
    func translate(_ requests: [PolyglotTranslationRequest], from source: String, to target: String) async throws -> [String] {
        requests.map(\.text)
    }
}

private final class HeardEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [PolyglotEvent] = []
    func add(_ event: PolyglotEvent) { lock.withLock { store.append(event) } }
    var lines: [PolyglotLine] { lock.withLock { store.compactMap { if case .line(let line) = $0 { line } else { nil } } } }
    var discarded: [PolyglotEvent] {
        lock.withLock { store.filter { if case .discarded = $0 { true } else { false } } }
    }
}

private struct HeardCaptions {
    var lines: [PolyglotLine]
    var originals: [String]
    var detected: [String]
    var discarded: [PolyglotEvent]
}

private func speech(_ seconds: Double) -> [Float] {
    (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.31)) * 0.12 }
}

private func silence(_ seconds: Double) -> [Float] {
    Array(repeating: 0, count: Int(seconds * 16_000))
}

private func captions(_ texts: [String]) async -> HeardCaptions {
    var lines: [PolyglotLine] = []
    var detected: [String] = []
    var discarded: [PolyglotEvent] = []
    for text in texts {
        let events = HeardEvents()
        let detector = HeardDetector()
        let pipeline = PolyglotPipeline(
            recognizer: HeardRecognizer(text: text),
            detector: detector,
            translator: HeardTranslator(),
            target: "en"
        ) { events.add($0) }
        await pipeline.ingest(speech(1) + silence(1), from: .system)
        await pipeline.finish()
        lines.append(contentsOf: events.lines)
        detected.append(contentsOf: detector.texts)
        discarded.append(contentsOf: events.discarded)
    }
    return HeardCaptions(lines: lines, originals: lines.map(\.original), detected: detected, discarded: discarded)
}
