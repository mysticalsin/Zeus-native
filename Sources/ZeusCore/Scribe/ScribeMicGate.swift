import Foundation

public enum ScribeMicDropReason: Hashable, Sendable {
    case muted
    case muteUnknown
}

public enum ScribeRouteDecision: Equatable, Sendable {
    case deliver
    case dropMicrophone(ScribeMicDropReason)
}

/// Pure mute policy. System audio is independent of mute; microphone audio flows only when unmuted.
public struct ScribeMicGate: Sendable, Equatable {
    public init() {}

    public func route(_ frame: ScribeAudioFrame, mute: ScribeMuteState) -> ScribeRouteDecision {
        switch frame.source {
        case .system:
            return .deliver
        case .microphone:
            switch mute {
            case .unmuted: return .deliver
            case .muted: return .dropMicrophone(.muted)
            case .unknown: return .dropMicrophone(.muteUnknown)
            }
        }
    }
}

public enum ScribeRouteOutcome: Equatable, Sendable {
    case delivered
    case droppedMicrophone(ScribeMicDropReason)
    case droppedStale
}

public struct ScribeRouterCounters: Equatable, Sendable {
    public var deliveredMicrophone = 0
    public var deliveredSystem = 0
    public var droppedMicrophoneMuted = 0
    public var droppedMicrophoneUnknown = 0
    public var droppedStale = 0
    public var storeFailures = 0

    public init() {}

    public var droppedMicrophone: Int { droppedMicrophoneMuted + droppedMicrophoneUnknown }
}

/// Applies the session check and the mic gate BEFORE any sink is called, so a dropped frame
/// never reaches storage or speech recognition.
public final class ScribeFrameRouter: @unchecked Sendable {
    private let muteSource: any ScribeMicMuteSource
    private let store: any ScribeFrameStore
    private let transcriber: any ScribeTranscriber
    private let gate: ScribeMicGate
    private let lock = NSLock()
    private var activeSession: ScribeSessionID?
    private var admissionClosed = false
    private var storedCounters = ScribeRouterCounters()

    public init(
        session: ScribeSessionID?,
        muteSource: any ScribeMicMuteSource,
        store: any ScribeFrameStore,
        transcriber: any ScribeTranscriber,
        gate: ScribeMicGate = ScribeMicGate()
    ) {
        self.activeSession = session
        self.muteSource = muteSource
        self.store = store
        self.transcriber = transcriber
        self.gate = gate
    }

    public var counters: ScribeRouterCounters {
        lock.withLock { storedCounters }
    }

    /// With no active session every frame is stale (fail closed). Waits for any in-flight delivery;
    /// once it returns, no frame of the previous session can reach a sink. Switching to a different
    /// session reopens admission after `finish()`. Must not be called from a sink.
    public func setActiveSession(_ session: ScribeSessionID?) {
        lock.lock()
        defer { lock.unlock() }
        if session != activeSession { admissionClosed = false }
        activeSession = session
    }

    /// Validation, mute read, delivery to both sinks and counter updates all happen under one lock,
    /// so `setActiveSession` and `finish` can never interleave with a frame already admitted.
    /// Sinks and the mute source are called while the lock is held: they must not call back into
    /// this router (that would deadlock).
    @discardableResult
    public func route(_ frame: ScribeAudioFrame) -> ScribeRouteOutcome {
        lock.lock()
        defer { lock.unlock() }

        guard !admissionClosed, let active = activeSession, active == frame.session else {
            storedCounters.droppedStale += 1
            return .droppedStale
        }

        // Mute is read per frame, and only for microphone frames.
        let mute: ScribeMuteState = frame.source == .microphone ? muteSource.currentMuteState() : .unmuted
        let decision = gate.route(frame, mute: mute)
        if case .dropMicrophone(let reason) = decision {
            switch reason {
            case .muted: storedCounters.droppedMicrophoneMuted += 1
            case .muteUnknown: storedCounters.droppedMicrophoneUnknown += 1
            }
            return .droppedMicrophone(reason)
        }

        do {
            try store.store(frame)
        } catch {
            storedCounters.storeFailures += 1
        }
        transcriber.ingest(frame)
        switch frame.source {
        case .microphone: storedCounters.deliveredMicrophone += 1
        case .system: storedCounters.deliveredSystem += 1
        }
        return .delivered
    }

    /// Closes admission for the active session, waits for any in-flight delivery (the lock), then
    /// tells the transcriber no more frames are coming. Frames after this are dropped as stale.
    /// Idempotent: the transcriber is told once. Must not be called from a sink.
    public func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !admissionClosed, let active = activeSession else { return }
        admissionClosed = true
        transcriber.finish(session: active)
    }
}
