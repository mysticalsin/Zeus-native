import Foundation
import Testing
@testable import ZeusCore

private struct TargetChangeRecognizer: PolyglotRecognizing {
    func transcribe(samples: [Float], language: String?) async throws -> String { "Vamos começar a reunião agora." }
}

private struct TargetChangeDetector: PolyglotLanguageDetecting {
    func detect(_ text: String) -> (code: String, confidence: Double)? { ("pt", 0.99) }
}

private actor PausedTranslator: PolyglotTranslating {
    enum Stage { case status, translation }
    let stage: Stage
    var pending: CheckedContinuation<Void, Never>?
    var observers: [CheckedContinuation<Void, Never>] = []
    private(set) var destinations: [String] = []

    init(stage: Stage) { self.stage = stage }

    private func pause() async {
        await withCheckedContinuation { continuation in
            pending = continuation
            let ready = observers
            observers.removeAll()
            ready.forEach { $0.resume() }
        }
    }

    func waitUntilPaused() async {
        guard pending == nil else { return }
        await withCheckedContinuation { observers.append($0) }
    }

    func resume() { pending?.resume(); pending = nil }

    func status(from source: String, to target: String) async -> PolyglotPackStatus {
        if stage == .status { await pause() }
        return .installed
    }

    func translate(_ requests: [PolyglotTranslationRequest], from source: String, to target: String) async throws -> [String] {
        destinations.append(target)
        if stage == .translation { await pause() }
        return requests.map { "\(target): \($0.text)" }
    }
}

private final class TargetChangeEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [PolyglotEvent] = []
    func add(_ event: PolyglotEvent) { lock.withLock { events.append(event) } }
    var all: [PolyglotEvent] { lock.withLock { events } }
}

private actor PausedCaptionRecognizer: PolyglotRecognizing {
    private var pending: CheckedContinuation<String, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var first = true

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard first else { return "Fresh words after Clear" }
        first = false
        return await withCheckedContinuation { continuation in
            pending = continuation
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilPaused() async {
        guard pending == nil else { return }
        await withCheckedContinuation { observer = $0 }
    }

    func resume() { pending?.resume(returning: "Old words before Clear"); pending = nil }
}

private struct ClearTestTranslator: PolyglotTranslating {
    func status(from source: String, to target: String) async -> PolyglotPackStatus { .unsupported }
    func translate(_ requests: [PolyglotTranslationRequest], from source: String, to target: String) async throws -> [String] { [] }
}

@Suite struct PolyglotTargetChangeTests {
    private func make(_ stage: PausedTranslator.Stage) -> (PolyglotPipeline, PausedTranslator, TargetChangeEvents) {
        let translator = PausedTranslator(stage: stage)
        let events = TargetChangeEvents()
        let pipeline = PolyglotPipeline(recognizer: TargetChangeRecognizer(), detector: TargetChangeDetector(), translator: translator,
                                        target: "en") { events.add($0) }
        return (pipeline, translator, events)
    }

    private var samples: [Float] {
        (0..<16_000).map { Float(sin(Double($0) * 0.31)) * 0.12 } + Array(repeating: Float(0), count: 16_000)
    }

    @Test func targetChangedDuringPackCheckDoesNotLaunchTheStaleTranslation() async {
        let (pipeline, translator, events) = make(.status)
        await pipeline.ingest(samples, from: .system)
        await translator.waitUntilPaused()
        await pipeline.setTarget("es")
        await translator.resume()
        await pipeline.finish()
        #expect(await translator.destinations.isEmpty)
        #expect(!events.all.contains { if case .translated = $0 { true } else { false } })
        #expect(events.all.contains { if case .line = $0 { true } else { false } })
    }

    @Test func targetChangedDuringTranslationDropsTheOldAnswerEvenAfterSwitchingBack() async {
        let (pipeline, translator, events) = make(.translation)
        await pipeline.ingest(samples, from: .system)
        await translator.waitUntilPaused()
        await pipeline.setTarget("es")
        await pipeline.setTarget("en")
        await translator.resume()
        await pipeline.finish()
        #expect(await translator.destinations == ["en"])
        #expect(!events.all.contains { if case .translated = $0 { true } else { false } })
    }

    @Test func clearDuringTranslationDiscardsTheOldAnswerBehindAnOrderedBarrier() async {
        let (pipeline, translator, events) = make(.translation)
        await pipeline.ingest(samples, from: .system)
        await translator.waitUntilPaused()
        await pipeline.clear(token: 7)
        await translator.resume()
        await pipeline.finish()
        let all = events.all
        let barrier = all.firstIndex(of: .cleared(7))
        #expect(barrier != nil)
        #expect(!all.contains { if case .translated = $0 { true } else { false } })
        var transcript = PolyglotTranscript()
        for event in all {
            if case .cleared = event { transcript.clear() } else { transcript.applySettled(event) }
        }
        #expect(transcript.lines.isEmpty)
    }

    @Test func clearDiscardsPendingRecognitionAndContinuesWithNewSpeech() async {
        let recognizer = PausedCaptionRecognizer()
        let events = TargetChangeEvents()
        let pipeline = PolyglotPipeline(recognizer: recognizer, detector: TargetChangeDetector(), translator: ClearTestTranslator(),
                                        target: "en") { events.add($0) }
        await pipeline.ingest(samples, from: .system)
        await recognizer.waitUntilPaused()
        await pipeline.clear(token: 1)
        await recognizer.resume()
        await pipeline.finish()
        #expect(!events.all.contains { if case .line = $0 { true } else { false } })
        await pipeline.ingest(samples, from: .system)
        await pipeline.finish()
        let lines = events.all.compactMap { if case .line(let line) = $0 { line } else { nil } }
        #expect(lines.map(\.original) == ["Fresh words after Clear"])
    }

    @Test func retargetKeepsOriginalsAndRecomputesWhichLinesNeedTranslation() {
        var transcript = PolyglotTranscript(lines: [
            PolyglotLine(id: 1, side: .system, original: "Olá", language: "pt", translation: "Hello"),
            PolyglotLine(id: 2, side: .microphone, original: "Good morning", language: "en", isTarget: true),
        ])
        transcript.retarget(to: "pt-BR")
        #expect(transcript.lines.map(\.original) == ["Olá", "Good morning"])
        #expect(transcript.lines.map(\.isTarget) == [true, false])
        #expect(transcript.lines.allSatisfy { $0.translation == nil })
        transcript.applySettled(.translated(id: 2, text: "Bom dia", target: "pt"))
        #expect(transcript.lines[1].translation == "Bom dia")
    }
}

@MainActor @Suite struct PolyglotEventDrainTests {
    @Test func targetRecoverySeesEveryLateCaptionAfterTheProducerFinishes() async {
        let (events, continuation) = AsyncStream.makeStream(of: PolyglotEvent.self)
        let firstID = PolyglotRunIDs.firstID(run: 1)
        continuation.yield(.line(PolyglotLine(id: firstID, side: .system, original: "Primeira frase", language: "pt")))
        continuation.yield(.line(PolyglotLine(id: firstID + 1, side: .system, original: "Última frase", language: "pt")))
        // Stop has finished the producer, but neither buffered caption has reached the transcript.
        continuation.finish()
        let nextRunID = PolyglotRunIDs.firstID(run: 2)
        var transcript = PolyglotTranscript(lines: [
            PolyglotLine(id: nextRunID, side: .system, original: "New run", language: "en")
        ])
        var recoveryIDs: [Int] = []
        await PolyglotEventDrain.consume(events, run: 1, targetRevisionAtStart: 0,
            handle: { transcript.applySettled($0) },
            recoveryState: { .init(targetRevision: 1, currentRun: 2, clearedBelow: 0, clearPending: false) },
            recover: { scope in
                recoveryIDs = transcript.lines.filter { scope.contains($0.id) }.map(\.id)
                for id in recoveryIDs { transcript.setTranslation(id: id, "new destination") }
            })
        #expect(recoveryIDs == [firstID, firstID + 1])
        #expect(transcript.lines.filter { recoveryIDs.contains($0.id) }.allSatisfy { $0.translation == "new destination" })
        // Starting a second capture does not discard the old run or include the new one's IDs.
        #expect(!recoveryIDs.contains(PolyglotRunIDs.firstID(run: 2)))
        #expect(transcript.lines.first { $0.id == nextRunID }?.translation == nil)
    }

    @Test func clearAndUnchangedDestinationSuppressDrainRecovery() async {
        let states: [PolyglotEventDrain.RecoveryState] = [
            .init(targetRevision: 0, currentRun: 1, clearedBelow: 0, clearPending: false),
            .init(targetRevision: 1, currentRun: 1, clearedBelow: 2, clearPending: false),
            .init(targetRevision: 1, currentRun: 1, clearedBelow: 0, clearPending: true),
            .init(targetRevision: 1, currentRun: 0, clearedBelow: 0, clearPending: false),
        ]
        for state in states {
            let (events, continuation) = AsyncStream.makeStream(of: PolyglotEvent.self)
            continuation.finish()
            var called = false
            await PolyglotEventDrain.consume(events, run: 1, targetRevisionAtStart: 0,
                handle: { _ in }, recoveryState: { state }, recover: { _ in called = true })
            #expect(!called)
        }
    }

    @Test func recoveryUsesStateAfterHandlingTheLastEvent() async {
        let (events, continuation) = AsyncStream.makeStream(of: PolyglotEvent.self)
        continuation.yield(.cleared(4))
        continuation.finish()
        var clearPending = true
        var called = false
        await PolyglotEventDrain.consume(events, run: 1, targetRevisionAtStart: 0,
            handle: { _ in clearPending = false },
            recoveryState: { .init(targetRevision: 1, currentRun: 1, clearedBelow: 1, clearPending: clearPending) },
            recover: { _ in called = true })
        #expect(called)
    }
}
