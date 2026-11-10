import Foundation

/// Speech to text for one utterance. `language` is a base code when the language is known, nil to detect.
public protocol PolyglotRecognizing: Sendable {
    func transcribe(samples: [Float], language: String?) async throws -> String
}

/// Names the language of a piece of text, with how sure it is (0...1).
public protocol PolyglotLanguageDetecting: Sendable {
    func detect(_ text: String) -> (code: String, confidence: Double)?
}

public enum PolyglotPackStatus: Equatable, Sendable {
    /// Both language packs are on this Mac.
    case installed
    /// Translation is possible once the person downloads the pack (macOS asks).
    case needsDownload
    case unsupported
}

public struct PolyglotTranslationRequest: Equatable, Sendable {
    public var id: Int
    public var text: String
    public init(id: Int, text: String) { self.id = id; self.text = text }
}

public protocol PolyglotTranslating: Sendable {
    func status(from source: String, to target: String) async -> PolyglotPackStatus
    /// One answer per request, in order.
    func translate(_ requests: [PolyglotTranslationRequest], from source: String, to target: String) async throws -> [String]
}

/// What the pipeline tells the card.
public enum PolyglotEvent: Equatable, Sendable {
    /// `id` is the id of the line this utterance becomes: the final `.line` carries the same one.
    case partial(side: PolyglotSide, id: Int, text: String)
    case line(PolyglotLine)
    /// The utterance ended without a caption (silence hallucination, recognizer error): retire its partial.
    case discarded(side: PolyglotSide, id: Int)
    case translated(id: Int, text: String, target: String)
    /// A language pack must be downloaded before this pair can be translated.
    case needsPack(source: String, target: String)
    case failed(String)
    /// Ordered barrier: all captions before this Clear were discarded, and new speech may resume.
    case cleared(Int)

    /// A result that stays true after its run ended (a caption, its translation, its retirement). A run
    /// that is still draining may deliver these; its partials and status messages are about a past moment.
    public var isSettled: Bool {
        switch self {
        case .line, .translated, .discarded: true
        case .partial, .needsPack, .failed, .cleared: false
        }
    }
}

/// Line ids that never repeat across runs: each run owns a block of ids, so a run that is still draining
/// after Stop can finish its captions while the next run is already numbering its own.
public enum PolyglotRunIDs {
    public static let blockSize = 1_000_000

    /// The first line id of run number `run` (1 for the first run of the session).
    public static func firstID(run: Int) -> Int { max(run, 1) * blockSize + 1 }
}

/// Drains captions before asking for recovery. Finishing the speech pipeline only closes
/// its producer; buffered events may still be waiting for the UI's consumer at that point.
public enum PolyglotEventDrain {
    public struct RecoveryState: Sendable {
        public let targetRevision: Int
        public let currentRun: Int
        public let clearedBelow: Int
        public let clearPending: Bool

        public init(targetRevision: Int, currentRun: Int, clearedBelow: Int, clearPending: Bool) {
            self.targetRevision = targetRevision
            self.currentRun = currentRun
            self.clearedBelow = clearedBelow
            self.clearPending = clearPending
        }
    }

    @MainActor
    public static func consume(_ events: AsyncStream<PolyglotEvent>, run: Int, targetRevisionAtStart: Int,
                               handle: @MainActor (PolyglotEvent) -> Void,
                               recoveryState: @MainActor () -> RecoveryState?,
                               recover: @MainActor (Range<Int>) async -> Void) async {
        for await event in events { handle(event) }
        guard !Task.isCancelled, let state = recoveryState(),
              state.targetRevision != targetRevisionAtStart,
              run >= state.clearedBelow, run <= state.currentRun, !state.clearPending else { return }
        // Exactly this drained run: a restarted capture owns a different block of line IDs.
        await recover(PolyglotRunIDs.firstID(run: run)..<PolyglotRunIDs.firstID(run: run + 1))
    }
}

/// Keeps the language steady between utterances: one noisy short phrase does not flip the
/// source, and only the languages the person expects (when set) are believed at a middling score.
public struct PolyglotLanguageTracker: Sendable {
    public private(set) var current: String?
    public var expected: Set<String>
    public var minimumConfidence = 0.55
    public var strongConfidence = 0.85

    public init(expected: Set<String> = [], current: String? = nil) {
        self.expected = Set(expected.map(PolyglotLanguage.base))
        self.current = current
    }

    /// The language to translate this utterance from, or nil while nothing is known.
    public mutating func resolve(_ detection: (code: String, confidence: Double)?, wordCount: Int) -> String? {
        guard let detection else { return current }
        let code = PolyglotLanguage.base(detection.code)
        let believed: Bool
        if code == current {
            believed = true
        } else if wordCount < 3 {
            believed = current == nil && detection.confidence >= strongConfidence
        } else if expected.isEmpty || expected.contains(code) {
            believed = detection.confidence >= minimumConfidence
        } else {
            believed = detection.confidence >= strongConfidence
        }
        if believed { current = code }
        return current
    }
}

/// Groups finished utterances for Apple's translator: one request per source language (a session
/// is one language pair), at most `limit` lines each, in the order they were said.
public enum PolyglotBatching {
    public struct Batch: Equatable, Sendable {
        public var language: String
        public var requests: [PolyglotTranslationRequest]
    }

    public static func group(_ items: [(language: String, request: PolyglotTranslationRequest)], limit: Int = 8) -> [Batch] {
        var batches: [Batch] = []
        var order: [String] = []
        var byLanguage: [String: [PolyglotTranslationRequest]] = [:]
        for item in items {
            if byLanguage[item.language] == nil { order.append(item.language) }
            byLanguage[item.language, default: []].append(item.request)
        }
        for language in order {
            let all = byLanguage[language] ?? []
            var start = 0
            while start < all.count {
                batches.append(Batch(language: language, requests: Array(all[start..<min(start + limit, all.count)])))
                start += limit
            }
        }
        return batches
    }
}

/// Audio in, captions out. Each input (microphone, Mac audio) has its own segmenter so two
/// voices never share an utterance. Finished utterances queue up; the worker transcribes them,
/// hands each text to the language detector, then translates whatever has piled up in batches.
public actor PolyglotPipeline {
    private struct Pending {
        var id: Int
        var side: PolyglotSide
        var samples: [Float]
    }

    private let recognizer: any PolyglotRecognizing
    private let detector: any PolyglotLanguageDetecting
    private let translator: any PolyglotTranslating
    private var target: String
    /// Changes even when a person switches away and back while a translator call is suspended.
    private var targetRevision = 0
    private var latestTargetRequest = 0
    private var contentRevision = 0
    private let expectedLanguages: Set<String>
    /// The microphone and remote speakers can speak different languages at the same time.
    private var trackers: [PolyglotSide: PolyglotLanguageTracker] = [:]
    private var segmenters: [PolyglotSide: PolyglotSegmenter] = [:]
    private let config: PolyglotSegmenter.Config
    private var queue: [Pending] = []
    private var working = false
    private var nextID: Int
    /// The utterance each input is saying right now (segmenter number) and the line id it was given.
    private var openUtterances: [PolyglotSide: (utterance: Int, id: Int)] = [:]
    /// Bumped by every `finish()`: a partial that started before it is dropped when it answers.
    private var session = 0
    private var partialBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let emit: @Sendable (PolyglotEvent) -> Void
    /// How many utterances one worker pass takes, so a backlog turns into a few translator calls.
    public let passLimit: Int

    /// `firstID` is the first line id: a later run starts above the lines already on the card.
    public init(recognizer: any PolyglotRecognizing, detector: any PolyglotLanguageDetecting, translator: any PolyglotTranslating,
                target: String, expected: Set<String> = [], config: PolyglotSegmenter.Config = .init(), passLimit: Int = 6,
                firstID: Int = 1, emit: @escaping @Sendable (PolyglotEvent) -> Void) {
        self.nextID = max(firstID, 1)
        self.recognizer = recognizer
        self.detector = detector
        self.translator = translator
        self.target = PolyglotLanguage.base(target)
        self.expectedLanguages = expected
        self.config = config
        self.passLimit = passLimit
        self.emit = emit
    }

    public func setTarget(_ code: String, request: Int? = nil) {
        if let request {
            guard request >= latestTargetRequest else { return }
            latestTargetRequest = request
        }
        let next = PolyglotLanguage.base(code)
        guard next != target else { return }
        target = next
        targetRevision += 1
    }

    /// Feeds 16 kHz mono samples from one input.
    public func ingest(_ samples: [Float], from side: PolyglotSide) {
        var segmenter = segmenters[side] ?? PolyglotSegmenter(config: config)
        let events = segmenter.feed(samples)
        segmenters[side] = segmenter
        handle(events, side: side)
    }

    /// Called in audio-input order. Discard in-flight recognition and buffered speech without
    /// stopping capture; only samples fed after the barrier can produce another caption.
    public func clear(token: Int) {
        contentRevision += 1
        session += 1
        queue.removeAll()
        segmenters.removeAll()
        openUtterances.removeAll()
        trackers.removeAll()
        emit(.cleared(token))
    }

    /// Ends the listening: every open utterance is closed, then everything queued is finished.
    public func finish() async {
        session += 1
        for side in Array(segmenters.keys) {
            var segmenter = segmenters[side] ?? PolyglotSegmenter(config: config)
            let events = segmenter.flush()
            segmenters[side] = segmenter
            handle(events, side: side)
        }
        if working || !queue.isEmpty {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func handle(_ events: [PolyglotSegmenter.Event], side: PolyglotSide) {
        for event in events {
            switch event {
            case .partial(let utterance, let samples):
                guard !partialBusy, queue.isEmpty else { continue }
                let id = lineID(side, utterance: utterance)
                partialBusy = true
                let language = trackers[side]?.current
                let started = session
                Task { await self.partial(samples, side: side, utterance: utterance, id: id, language: language, session: started) }
            case .final(let utterance, let samples):
                let id = lineID(side, utterance: utterance)
                openUtterances[side] = nil
                queue.append(Pending(id: id, side: side, samples: samples))
            }
        }
        if !queue.isEmpty, !working {
            working = true
            Task { await self.work() }
        }
    }

    /// The line id of an input's utterance: the same one for its partials and its final.
    private func lineID(_ side: PolyglotSide, utterance: Int) -> Int {
        if let known = openUtterances[side], known.utterance == utterance { return known.id }
        let id = nextID
        nextID += 1
        openUtterances[side] = (utterance: utterance, id: id)
        return id
    }

    private func partial(_ samples: [Float], side: PolyglotSide, utterance: Int, id: Int, language: String?, session started: Int) async {
        defer { partialBusy = false }
        guard let text = try? await recognizer.transcribe(samples: samples, language: language),
              !PolyglotTextFilter.isPhantom(text) else { return }
        // Late: the utterance was already finished (or the listening ended) while this was being recognized.
        guard started == session, openUtterances[side]?.utterance == utterance else { return }
        emit(.partial(side: side, id: id, text: text))
    }

    private func work() async {
        while !queue.isEmpty {
            let taken = Array(queue.prefix(passLimit))
            queue.removeFirst(taken.count)
            await process(taken, revision: contentRevision)
        }
        working = false
        let ready = waiters
        waiters.removeAll()
        ready.forEach { $0.resume() }
    }

    private func process(_ items: [Pending], revision: Int) async {
        var toTranslate: [(language: String, request: PolyglotTranslationRequest)] = []
        for item in items {
            let text: String
            do {
                text = try await recognizer.transcribe(samples: item.samples, language: trackers[item.side]?.current)
            } catch {
                guard revision == contentRevision else { return }
                emit(.failed("Speech recognition failed: \(error.localizedDescription)"))
                emit(.discarded(side: item.side, id: item.id))
                continue
            }
            guard revision == contentRevision else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !PolyglotTextFilter.isPhantom(trimmed) else {
                emit(.discarded(side: item.side, id: item.id))
                continue
            }
            let words = trimmed.split(whereSeparator: \.isWhitespace).count
            var tracker = trackers[item.side] ?? PolyglotLanguageTracker(expected: expectedLanguages)
            let language = tracker.resolve(detector.detect(trimmed), wordCount: words)
            trackers[item.side] = tracker
            let isTarget = language.map { PolyglotLanguage.base($0) == target } ?? false
            emit(.line(PolyglotLine(id: item.id, side: item.side, original: trimmed, language: language, isTarget: isTarget)))
            if let language, !isTarget { toTranslate.append((language, PolyglotTranslationRequest(id: item.id, text: trimmed))) }
        }
        for batch in PolyglotBatching.group(toTranslate) {
            guard revision == contentRevision else { return }
            await translate(batch, content: revision)
        }
    }

    private func translate(_ batch: PolyglotBatching.Batch, content: Int) async {
        let destination = target
        guard PolyglotLanguage.base(batch.language) != destination else { return }
        let revision = targetRevision
        let status = await translator.status(from: batch.language, to: destination)
        guard revision == targetRevision, content == contentRevision else { return }
        switch status {
        case .installed: break
        case .needsDownload:
            emit(.needsPack(source: batch.language, target: destination))
            return
        case .unsupported:
            emit(.failed("\(PolyglotLanguage.name(for: batch.language)) to \(PolyglotLanguage.name(for: destination)) is not available for translation."))
            return
        }
        do {
            let answers = try await translator.translate(batch.requests, from: batch.language, to: destination)
            guard revision == targetRevision, content == contentRevision else { return }
            // An empty answer means the translator had nothing for that line: leave it as heard, never blank.
            for (request, answer) in zip(batch.requests, answers) where !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emit(.translated(id: request.id, text: answer, target: destination))
            }
        } catch {
            guard revision == targetRevision, content == contentRevision else { return }
            emit(.failed("Translation failed: \(error.localizedDescription)"))
        }
    }
}
