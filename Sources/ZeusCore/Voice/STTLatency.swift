import Foundation

/// Speech-to-text timing for the two input paths.
///
/// `talk-hold` is a hold that opens `VoiceTurnController` (Right Option, or Control+Option after
/// the key router). `murmur-tap` is a Right Command tap that opens Murmur.
/// Stage values are milliseconds from key-down. The trace never stores transcript text.
public enum STTPath: String, CaseIterable, Equatable, Sendable {
    case talkHold = "talk-hold"
    case murmurTap = "murmur-tap"
}

public enum STTFailure: String, Equatable, Sendable {
    case none
    case noText = "no_text"
    case emptyText = "empty_text"
    case hang
    case timeout
}

/// One turn's stage clock. Missing stages stay absent and print as `-`.
public struct STTLatencyTrace: Equatable, Sendable {
    public enum Stage: String, CaseIterable, Sendable {
        case keyDown = "key_down"
        case captureStart = "capture_start"
        case speechStart = "speech_start"
        case silenceDetected = "silence_detected"
        case endpointFired = "endpoint_fired"
        case modelReady = "model_ready"
        case firstPartial = "first_partial"
        case finalTranscript = "final_transcript"
        case deliveredToUI = "delivered_to_ui"
    }

    public enum Group: String, CaseIterable, Sendable {
        case capture
        case vad
        case asr
        case delivery
    }

    public static let groupStages: [Group: [Stage]] = [
        .capture: [.captureStart],
        .vad: [.speechStart, .silenceDetected, .endpointFired],
        .asr: [.modelReady, .firstPartial, .finalTranscript],
        .delivery: [.deliveredToUI],
    ]

    public var path: STTPath
    public private(set) var marks: [Stage: Int] = [:]

    public init(path: STTPath) { self.path = path }

    /// The first mark wins. Times are absolute milliseconds on the caller's clock.
    public mutating func mark(_ stage: Stage, atMs: Int) {
        guard marks[stage] == nil else { return }
        marks[stage] = max(0, atMs)
    }

    /// Drops the silence mark when speech resumes, so a pause in the middle is not the endpoint silence.
    public mutating func reviseSilence(speechResumed: Bool, endpointAlreadyFired: Bool) {
        guard speechResumed, !endpointAlreadyFired else { return }
        marks[.silenceDetected] = nil
    }

    /// Milliseconds after key-down. Nil when the stage has not happened.
    public func offset(_ stage: Stage) -> Int? {
        guard let mark = marks[stage] else { return nil }
        guard let zero = marks[.keyDown] else { return mark }
        return mark - zero
    }

    public func shows(_ stage: Stage) -> String {
        offset(stage).map(String.init) ?? "-"
    }

    /// Grouped lines the Mac repro prints. Digits, stage names and the path only.
    public func grouped(failure: STTFailure) -> String {
        var lines = ["path=\(path.rawValue) key_down=\(shows(.keyDown))"]
        for group in Group.allCases {
            let parts = (Self.groupStages[group] ?? []).map { "\($0.rawValue)=\(shows($0))" }
            lines.append("\(group.rawValue): \(parts.joined(separator: " "))")
        }
        lines.append("failure=\(failure.rawValue)")
        return lines.joined(separator: "\n")
    }
}

/// What the running app does. Tests inject this; they do not read `Date`.
public struct STTSessionPolicy: Equatable, Sendable {
    /// Quiet this long after the last voiced frame before a silence endpoint may fire.
    public var silenceToEndpointMs: Int
    /// Longest a turn may wait for the recognizer after the endpoint.
    public var endpointToFinalMs: Int
    public var talkDeliveredMs: Int
    public var murmurDeliveredMs: Int
    /// A recognition task that never calls back is cancelled at this bound.
    /// The 8 s, 20 s and 45 s budgets belong to other subsystems and are not this value.
    public var hangGiveUpMs: Int
    public var keyDownToCaptureMs: Int
    public var speechStartMs: Int
    /// An unchanged partial used to push the silence clock forward.
    public var duplicatePartialResetsEndpoint: Bool
    public var cancelsTaskWhenAudioEnds: Bool
    /// Legacy loads again on every utterance. The fixed policy loads once at prewarm.
    public var reloadsModelPerUtterance: Bool
    public var allowsServerRoundTrip: Bool

    public init(silenceToEndpointMs: Int, endpointToFinalMs: Int, talkDeliveredMs: Int, murmurDeliveredMs: Int,
                hangGiveUpMs: Int, keyDownToCaptureMs: Int, speechStartMs: Int,
                duplicatePartialResetsEndpoint: Bool, cancelsTaskWhenAudioEnds: Bool,
                reloadsModelPerUtterance: Bool, allowsServerRoundTrip: Bool) {
        self.silenceToEndpointMs = silenceToEndpointMs
        self.endpointToFinalMs = endpointToFinalMs
        self.talkDeliveredMs = talkDeliveredMs
        self.murmurDeliveredMs = murmurDeliveredMs
        self.hangGiveUpMs = hangGiveUpMs
        self.keyDownToCaptureMs = keyDownToCaptureMs
        self.speechStartMs = speechStartMs
        self.duplicatePartialResetsEndpoint = duplicatePartialResetsEndpoint
        self.cancelsTaskWhenAudioEnds = cancelsTaskWhenAudioEnds
        self.reloadsModelPerUtterance = reloadsModelPerUtterance
        self.allowsServerRoundTrip = allowsServerRoundTrip
    }

    public func deliveredHopMs(for path: STTPath) -> Int {
        path == .murmurTap ? murmurDeliveredMs : talkDeliveredMs
    }

    /// Apple's batch recognizer today waits `max(30 s, 3 × audio)`. A fixed policy caps that
    /// well under the unrelated 8 s, 20 s and 45 s budgets.
    public func batchGiveUpMs(audioMs: Int) -> Int {
        let audio = max(0, audioMs)
        if hangGiveUpMs >= 30_000 { return max(hangGiveUpMs, audio * 3) }
        return min(2_000, max(hangGiveUpMs, audio / 2))
    }

    /// Source of the slow path, read off the current app:
    /// `SpeechInput.stop` waits 2.5 s and does not cancel the task,
    /// `AppleSpeechEngine` gives up at `max(30 s, 3 × audio)`,
    /// hands-free treats every partial callback as new speech.
    public static let legacy = STTSessionPolicy(
        silenceToEndpointMs: 1_000,
        endpointToFinalMs: 2_500,
        talkDeliveredMs: 0,
        murmurDeliveredMs: 0,
        hangGiveUpMs: 30_000,
        keyDownToCaptureMs: 80,
        speechStartMs: 40,
        duplicatePartialResetsEndpoint: true,
        cancelsTaskWhenAudioEnds: false,
        reloadsModelPerUtterance: true,
        allowsServerRoundTrip: false
    )

    /// On-device stays the default. Same recognition budget on both paths.
    /// Murmur's handoff into the dictation controller is one extra main-queue hop.
    public static let fixed = STTSessionPolicy(
        silenceToEndpointMs: 400,
        endpointToFinalMs: 450,
        talkDeliveredMs: 50,
        murmurDeliveredMs: 80,
        hangGiveUpMs: 800,
        keyDownToCaptureMs: 80,
        speechStartMs: 40,
        duplicatePartialResetsEndpoint: false,
        cancelsTaskWhenAudioEnds: true,
        reloadsModelPerUtterance: false,
        allowsServerRoundTrip: false
    )

    /// The policy the app and the regression read.
    public static let production = STTSessionPolicy.fixed
}

/// Injected clock. Callers pass milliseconds; nothing here reads the wall clock.
public struct STTClock: Equatable, Sendable {
    public var nowMs: Int
    public init(nowMs: Int = 0) { self.nowMs = nowMs }
    public mutating func advance(to ms: Int) { nowMs = ms }
}

public enum STTEvent: Equatable, Sendable {
    case keyDown(Int)
    case capture(Int)
    case modelReady(Int)
    case audio(at: Int, rms: Float, partialToken: Int?)
    case keyUp(Int)
}

/// Counts loads. Prewarm is the one load when the policy says so.
public struct STTModelGate: Equatable, Sendable {
    public private(set) var loadCount = 0
    public private(set) var ready = false

    public init() {}

    /// True when this call performed the load.
    public mutating func prewarm(policy: STTSessionPolicy) -> Bool {
        if ready { return false }
        guard !policy.reloadsModelPerUtterance else { return false }
        loadCount += 1
        ready = true
        return true
    }

    /// True when this utterance had to load because nothing was warm.
    public mutating func beginUtterance(policy: STTSessionPolicy) -> Bool {
        if ready, !policy.reloadsModelPerUtterance { return false }
        loadCount += 1
        ready = true
        return true
    }
}

public struct STTFailureLedger: Equatable, Sendable {
    public private(set) var attempts: [STTPath: Int] = [:]
    public private(set) var failed: [STTPath: Int] = [:]

    public init() {}

    public mutating func record(path: STTPath, failure: STTFailure) {
        attempts[path, default: 0] += 1
        if failure != .none { failed[path, default: 0] += 1 }
    }

    public func rate(_ path: STTPath) -> Double {
        let count = attempts[path] ?? 0
        guard count > 0 else { return 0 }
        return Double(failed[path] ?? 0) / Double(count)
    }

    public func line(_ path: STTPath) -> String {
        let count = attempts[path] ?? 0
        let bad = failed[path] ?? 0
        return "failure_rate path=\(path.rawValue) attempts=\(count) failures=\(bad) rate=\(String(format: "%.3f", rate(path)))"
    }
}

/// One path, driven only by `STTClock` timestamps and RMS. No audio and no text.
public struct STTLiveTurn: Equatable, Sendable {
    public let policy: STTSessionPolicy
    public var endOnSilence: Bool
    public private(set) var trace: STTLatencyTrace
    public private(set) var failure: STTFailure = .none
    public private(set) var taskCancelled = false
    public private(set) var hasText = false
    public private(set) var heardSpeech = false
    private var lastVoicedMs: Int?
    private var silenceAt: Int?
    private var endpointAt: Int?
    private var lastToken: Int?
    private var concluded = false
    public var silenceLevel: Float = 0.008

    public init(path: STTPath, policy: STTSessionPolicy = .production, endOnSilence: Bool = true) {
        self.policy = policy
        self.endOnSilence = endOnSilence
        self.trace = STTLatencyTrace(path: path)
    }

    public mutating func keyDown(clock: STTClock) {
        trace.mark(.keyDown, atMs: clock.nowMs)
    }

    public mutating func captureStarted(clock: STTClock) {
        trace.mark(.captureStart, atMs: clock.nowMs)
    }

    public mutating func modelReady(clock: STTClock) {
        trace.mark(.modelReady, atMs: clock.nowMs)
    }

    /// True when this partial counts as speech. An unchanged token counts only on the legacy
    /// policy, which treated every callback as a new utterance and so never heard the silence.
    @discardableResult
    public mutating func notePartial(clock: STTClock, token: Int) -> Bool {
        hasText = true
        trace.mark(.firstPartial, atMs: clock.nowMs)
        let changed = Self.partialChanged(last: lastToken, token: token)
        lastToken = token
        let countsAsSpeech = changed || policy.duplicatePartialResetsEndpoint
        if countsAsSpeech { lastVoicedMs = clock.nowMs }
        return countsAsSpeech
    }

    @discardableResult
    public mutating func feed(clock: STTClock, rms: Float, partialToken: Int?) -> [STTLatencyTrace.Stage] {
        let partialSpoke = partialToken.map { notePartial(clock: clock, token: $0) } ?? false
        var fired: [STTLatencyTrace.Stage] = []
        let voiced = rms >= silenceLevel || partialSpoke
        if voiced {
            heardSpeech = true
            if trace.marks[.speechStart] == nil {
                trace.mark(.speechStart, atMs: clock.nowMs)
                fired.append(.speechStart)
            }
            lastVoicedMs = clock.nowMs
            if endpointAt == nil {
                silenceAt = nil
                trace.reviseSilence(speechResumed: true, endpointAlreadyFired: false)
            }
        } else if heardSpeech {
            if silenceAt == nil {
                silenceAt = clock.nowMs
                trace.mark(.silenceDetected, atMs: clock.nowMs)
                fired.append(.silenceDetected)
            }
            if endOnSilence, endpointAt == nil, let silenceAt,
               STTQuiet.reached(quietForMs: clock.nowMs - silenceAt, thresholdMs: policy.silenceToEndpointMs) {
                let at = STTQuiet.endpointStampMs(silenceAt: silenceAt, thresholdMs: policy.silenceToEndpointMs,
                                                   observedAtMs: clock.nowMs)
                endpointAt = at
                trace.mark(.endpointFired, atMs: at)
                fired.append(.endpointFired)
                conclude(atMs: at, recognizerFinalMs: nil)
            }
        }
        return fired
    }

    /// Key release, or the second Murmur tap. That is the endpoint when silence has not already ended the turn.
    public mutating func keyUp(clock: STTClock, recognizerFinalMs: Int? = nil) {
        armEndpoint(clock: clock)
        conclude(atMs: endpointAt ?? clock.nowMs, recognizerFinalMs: recognizerFinalMs)
    }

    /// Records the endpoint at this clock without inventing the final time.
    public mutating func armEndpoint(clock: STTClock) {
        if endpointAt == nil {
            endpointAt = clock.nowMs
            trace.mark(.endpointFired, atMs: clock.nowMs)
        }
    }

    public mutating func conclude(atMs: Int, recognizerFinalMs: Int?) {
        guard !concluded else { return }
        concluded = true
        let cap = atMs + policy.endpointToFinalMs
        let finalAt = min(recognizerFinalMs ?? cap, cap)
        trace.mark(.finalTranscript, atMs: finalAt)
        let delivered = finalAt + policy.deliveredHopMs(for: trace.path)
        trace.mark(.deliveredToUI, atMs: delivered)
        taskCancelled = policy.cancelsTaskWhenAudioEnds || recognizerFinalMs != nil
        if !heardSpeech, !hasText {
            failure = .noText
        } else if !hasText {
            failure = .emptyText
        } else if recognizerFinalMs == nil, !policy.cancelsTaskWhenAudioEnds {
            failure = .hang
        } else if recognizerFinalMs == nil, policy.endpointToFinalMs > STTSessionPolicy.fixed.endpointToFinalMs {
            failure = .timeout
        } else {
            failure = .none
        }
    }

    /// A first token is a change. A later token is a change only when it differs.
    /// The nil arm is load-bearing: removing it and force-unwrapping `last` traps the first partial.
    public static func partialChanged(last: Int?, token: Int) -> Bool {
        guard let last else { return true }
        return token != last
    }

    public static func replay(path: STTPath, policy: STTSessionPolicy = .production, events: [STTEvent],
                              endOnSilence: Bool = true) -> STTLiveTurn {
        var turn = STTLiveTurn(path: path, policy: policy, endOnSilence: endOnSilence)
        for event in events {
            switch event {
            case .keyDown(let ms): turn.keyDown(clock: STTClock(nowMs: ms))
            case .capture(let ms): turn.captureStarted(clock: STTClock(nowMs: ms))
            case .modelReady(let ms): turn.modelReady(clock: STTClock(nowMs: ms))
            case .audio(let ms, let rms, let token): turn.feed(clock: STTClock(nowMs: ms), rms: rms, partialToken: token)
            case .keyUp(let ms): turn.keyUp(clock: STTClock(nowMs: ms))
            }
        }
        return turn
    }
}

/// The one live utterance. A newer begin replaces the trace. A deliver or cancel for an older
/// generation does not write the replacement.
public struct STTUtteranceBook: Equatable, Sendable {
    public private(set) var generation = 0
    public private(set) var trace = STTLatencyTrace(path: .talkHold)
    public private(set) var cancelled = false
    private var keyDownAt = 0

    public init() {}

    public mutating func begin(path: STTPath, atMs: Int) -> Int {
        generation += 1
        cancelled = false
        keyDownAt = atMs
        trace = STTLatencyTrace(path: path)
        trace.mark(.keyDown, atMs: atMs)
        return generation
    }

    @discardableResult
    public mutating func mark(_ stage: STTLatencyTrace.Stage, atMs: Int, generation owner: Int) -> Bool {
        guard owner == generation, !cancelled else { return false }
        trace.mark(stage, atMs: atMs)
        return true
    }

    /// True when `owner` is still the open utterance and this call wrote `delivered_to_ui`.
    public static func accepts(owner: Int, current: Int, cancelled: Bool) -> Bool {
        owner > 0 && owner == current && !cancelled
    }

    /// True when this call wrote `delivered_to_ui`.
    public mutating func deliver(generation owner: Int, atMs: Int) -> Bool {
        guard Self.accepts(owner: owner, current: generation, cancelled: cancelled) else { return false }
        guard trace.marks[.deliveredToUI] == nil else { return false }
        trace.mark(.deliveredToUI, atMs: atMs)
        return true
    }

    public mutating func cancel(generation owner: Int) {
        guard owner == generation else { return }
        cancelled = true
    }

    /// Applies loudness only for the session that owns the buffer.
    public mutating func noteLoudness(rms: Float, atMs: Int, bufferSession: Int, currentSession: Int) -> Bool {
        guard STTBufferGate.loudnessApplies(bufferSession: bufferSession, currentSession: currentSession) else { return false }
        if rms >= 0.008 {
            trace.mark(.speechStart, atMs: atMs)
        } else if trace.marks[.speechStart] != nil {
            trace.mark(.silenceDetected, atMs: atMs)
        }
        return true
    }
}

/// Whether a microphone buffer may update the live utterance. A stale tap session must not.
public struct STTTapEffect: Equatable, Sendable {
    public var applyLoudness: Bool
    public var publishLevel: Bool
}

public enum STTBufferGate {
    public static func loudnessApplies(bufferSession: Int, currentSession: Int) -> Bool {
        bufferSession == currentSession
    }

    /// Loudness and the level meter share one owner check. The meter flag is wrong until the fix:
    /// a stale tap still publishes level.
    public static func effect(bufferSession: Int, currentSession: Int) -> STTTapEffect {
        let owns = loudnessApplies(bufferSession: bufferSession, currentSession: currentSession)
        return STTTapEffect(applyLoudness: owns, publishLevel: true)
    }
}

/// The flag `SpeechInput.noteDelivered` stores. `allowed` ignores it until the fix, so a
/// hardcoded cancelled bit fails the delivery test.
public struct STTLiveDelivery: Equatable, Sendable {
    public private(set) var current: Int
    public private(set) var traceCancelled: Bool

    public init(current: Int = 0, traceCancelled: Bool = false) {
        self.current = current
        self.traceCancelled = traceCancelled
    }

    public mutating func begin() -> Int {
        current += 1
        traceCancelled = false
        return current
    }

    public mutating func cancel() {
        traceCancelled = true
    }

    public func allowed(owner: Int) -> Bool {
        STTUtteranceBook.accepts(owner: owner, current: current, cancelled: false)
    }
}

/// Quiet-time endpoint. Hands-free polls every 100 ms. The predicate is `>=` so a sample
/// that lands on the threshold counts. Non-wake hands-free stays at 1000 ms.
public enum STTQuiet {
    public static let handsFreeSilenceMs = 1_000

    public static func reached(quietForMs: Int, thresholdMs: Int) -> Bool {
        quietForMs >= thresholdMs
    }

    /// Stamps the observed clock. The crossing sample is silence plus the budget.
    public static func endpointStampMs(silenceAt: Int, thresholdMs: Int, observedAtMs: Int) -> Int {
        _ = silenceAt
        _ = thresholdMs
        return observedAtMs
    }
}

/// Non-wake hands-free quiet. The red path still uses the legacy 1000 ms and a strict `>`.
public enum STTHandsFree {
    public static var silenceMs: Int { STTQuiet.handsFreeSilenceMs }

    public static func quietEnded(quietForMs: Int) -> Bool {
        quietForMs > silenceMs
    }
}

public enum STTOutcome {
    /// How a finished turn is counted. A partial that is handed over inside the budget is not a failure.
    public static func failure(hadSpeech: Bool, hasText: Bool, recognizerFinished: Bool,
                               policy: STTSessionPolicy = .production) -> STTFailure {
        if !hadSpeech, !hasText { return .noText }
        if !hasText { return .emptyText }
        if !recognizerFinished, !policy.cancelsTaskWhenAudioEnds { return .hang }
        if !recognizerFinished, policy.endpointToFinalMs > STTSessionPolicy.fixed.endpointToFinalMs { return .timeout }
        return .none
    }
}

/// Process-wide failure counts. The log line is counts only.
public final class STTFailureLog: @unchecked Sendable {
    public static let shared = STTFailureLog()
    private let lock = NSLock()
    private var ledger = STTFailureLedger()

    public func record(path: STTPath, failure: STTFailure) -> String {
        lock.lock()
        ledger.record(path: path, failure: failure)
        let line = ledger.line(path)
        lock.unlock()
        return line
    }
}

public enum STTLatencyHarness {
    /// Hold or tap, then release, with no recognizer final. The partial token stands in for text.
    public static let releaseEvents: [STTEvent] = [
        .keyDown(0),
        .capture(15),
        .modelReady(0),
        .audio(at: 40, rms: 0.05, partialToken: 1),
        .keyUp(600),
    ]

    /// Speech, then the same partial repeated across silence. A correct endpoint does not move.
    public static let silenceEvents: [STTEvent] = [
        .keyDown(0),
        .capture(15),
        .modelReady(0),
        .audio(at: 40, rms: 0.05, partialToken: 1),
        .audio(at: 480, rms: 0.001, partialToken: 1),
        .audio(at: 880, rms: 0.001, partialToken: 1),
    ]

    public static func measurementReport() -> String {
        var lines: [String] = []
        for path in STTPath.allCases {
            for (name, events, endOnSilence) in [("release", releaseEvents, false), ("silence", silenceEvents, true)] {
                let before = STTLiveTurn.replay(path: path, policy: .legacy, events: events, endOnSilence: endOnSilence)
                let after = STTLiveTurn.replay(path: path, policy: .production, events: events, endOnSilence: endOnSilence)
                lines.append("BEFORE \(path.rawValue) \(name)")
                lines.append(before.trace.grouped(failure: before.failure))
                lines.append("AFTER \(path.rawValue) \(name)")
                lines.append(after.trace.grouped(failure: after.failure))
            }
        }
        lines.append(failureReport(policy: .legacy, label: "BEFORE").joined(separator: "\n"))
        lines.append(failureReport(policy: .production, label: "AFTER").joined(separator: "\n"))
        return lines.joined(separator: "\n")
    }

    public static func failureReport(policy: STTSessionPolicy = .production, turns: Int = 4, label: String = "AFTER") -> [String] {
        var ledger = STTFailureLedger()
        for path in STTPath.allCases {
            for _ in 0..<turns {
                let turn = STTLiveTurn.replay(path: path, policy: policy, events: releaseEvents, endOnSilence: false)
                ledger.record(path: path, failure: turn.failure)
            }
        }
        return STTPath.allCases.map { "\(label) \(ledger.line($0))" }
    }
}
