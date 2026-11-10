import Darwin
import Foundation

/// One start-to-teardown run. Every engine callback carries its attempt, so a late callback from an earlier run is ignored.
public struct RecordlyRecordingAttempt: Hashable, Sendable {
    public let id: UInt64

    public init(id: UInt64) {
        self.id = id
    }
}

/// What the engine needs to begin one recording. Plain values only, so the session never sees a framework type.
public struct RecordlyStartRequest: Equatable, Sendable {
    public let intent: RecordlySourceSelection.SelectionIntent
    public let systemAudio: Bool
    public let excludeZeusWindows: Bool
    public let directory: URL

    public init(
        intent: RecordlySourceSelection.SelectionIntent,
        systemAudio: Bool,
        excludeZeusWindows: Bool,
        directory: URL
    ) {
        self.intent = intent
        self.systemAudio = systemAudio
        self.excludeZeusWindows = excludeZeusWindows
        self.directory = directory
    }
}

/// A finished recording, delivered to the caller exactly once.
public struct RecordlyRecordingOutput: Equatable, Sendable {
    public let url: URL
    public let cursorSamples: [RecordlyCursorSample]

    public init(url: URL, cursorSamples: [RecordlyCursorSample]) {
        self.url = url
        self.cursorSamples = cursorSamples
    }
}

/// Typed failures a port reports. The adapter maps its own errors onto these.
public enum RecordlyPortFailure: Error, Equatable, Sendable, LocalizedError {
    case permissionDenied(String)
    case noSource(String)
    case engine(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let message), .noSource(let message), .engine(let message): message
        case .cancelled: "The recording was cancelled."
        }
    }
}

/// The native side of a recording. A port that throws from `begin` or `end` has already released everything it
/// owned for that attempt; `cancel` returns only once teardown for that attempt is complete and is safe to repeat.
@MainActor
public protocol RecordlyRecordingPort: AnyObject {
    func begin(
        request: RecordlyStartRequest,
        attempt: RecordlyRecordingAttempt,
        onUnexpectedStop: @escaping @Sendable (RecordlyRecordingAttempt, String) -> Void
    ) async throws -> RecordlySourceSelection.ResolvedSource

    func cancel(attempt: RecordlyRecordingAttempt) async

    func end(attempt: RecordlyRecordingAttempt) async throws -> RecordlyRecordingOutput
}

/// The single authority for the capture lifecycle:
/// `idle -> starting -> recording -> stopping -> idle | failed`. A failure or a cancel sits in `stopping` until the
/// port acknowledges teardown, and only then does it become `failed` or `idle`, so a retry can never overlap a
/// teardown. Stop is accepted once, and a finished recording is handed back exactly once.
@MainActor
public final class RecordlyRecordingSession {
    public enum Phase: Equatable, Sendable {
        case idle
        case starting(RecordlyRecordingAttempt)
        case recording(RecordlyRecordingAttempt)
        case stopping(RecordlyRecordingAttempt)
        case failed(String)
    }

    public enum StartOutcome: Equatable, Sendable {
        case started(RecordlyRecordingAttempt, RecordlySourceSelection.ResolvedSource)
        case cancelled
        case failed(RecordlyPortFailure)
        case rejected(String)
    }

    public enum StopOutcome: Equatable, Sendable {
        case finished(RecordlyRecordingOutput)
        case failed(String)
        /// Nothing was recording, or another Stop already owns the teardown.
        case ignored
    }

    public private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            if case .stopping = phase {} else {
                watchdog?.cancel()
                watchdog = nil
            }
            onPhaseChange?(phase)
        }
    }

    /// Called after every phase change, on the main actor.
    public var onPhaseChange: (@MainActor (Phase) -> Void)?

    /// Called when the engine lost the stream mid-recording but the recording made so far was finalized and kept.
    /// The phase is `idle` by then; the message says why it ended early. A late finish is also reported here, with its
    /// attempt, even while a newer attempt is busy, so the receiver can keep it until it is safe to open.
    public var onRecovered: (@MainActor (RecordlyRecordingAttempt, RecordlyRecordingOutput, String) -> Void)?

    /// How the watchdog waits. Tests inject a gate so no real timer is involved.
    public typealias Sleeper = @MainActor @Sendable (Duration) async -> Void

    public static let defaultStuckTimeout: Duration = .seconds(10)
    public static let stuckMessage = "Zeus stopped waiting for the recording to finish because it took too long. If it finishes later it opens on its own. Dismiss this and try again; if Zeus says another recording is still running, relaunch Zeus."
    public static let lateFinishMessage = "The recording finished after Zeus had stopped waiting for it."

    private struct Teardown {
        var beginReturned: Bool
        var cancelReturned = false
        var failure: String?
    }

    private let port: any RecordlyRecordingPort
    private var lastAttemptID: UInt64 = 0
    private var teardown: Teardown?
    private let stuckTimeout: Duration
    private var watchdog: Task<Void, Never>?
    private let sleeper: Sleeper
    /// Attempts whose finish the watchdog gave up on; a late good result for one is still handed over once.
    private var abandonedFinishes: Set<RecordlyRecordingAttempt> = []

    public init(
        port: any RecordlyRecordingPort,
        stuckTimeout: Duration = RecordlyRecordingSession.defaultStuckTimeout,
        sleeper: @escaping Sleeper = { _ = try? await Task.sleep(for: $0) }
    ) {
        self.port = port
        self.stuckTimeout = stuckTimeout
        self.sleeper = sleeper
    }

    public var isBusy: Bool {
        switch phase {
        case .starting, .recording, .stopping: true
        case .idle, .failed: false
        }
    }

    public var failureMessage: String? {
        if case .failed(let message) = phase { message } else { nil }
    }

    /// Takes the user's explicit intent once. The phase is `starting` before the first suspension.
    public func start(_ request: RecordlyStartRequest) async -> StartOutcome {
        guard phase == .idle else { return .rejected(Self.busyMessage(phase)) }
        lastAttemptID &+= 1
        let attempt = RecordlyRecordingAttempt(id: lastAttemptID)
        teardown = nil
        phase = .starting(attempt)

        let begun: Result<RecordlySourceSelection.ResolvedSource, RecordlyPortFailure>
        do {
            let resolved = try await port.begin(
                request: request,
                attempt: attempt,
                onUnexpectedStop: { [weak self] stoppedAttempt, message in
                    Task { @MainActor in
                        await self?.engineFailed(attempt: stoppedAttempt, message: message)
                    }
                }
            )
            begun = .success(resolved)
        } catch let failure as RecordlyPortFailure {
            begun = .failure(failure)
        } catch {
            begun = .failure(.engine(error.localizedDescription))
        }
        return await settleStart(attempt, begun)
    }

    /// Cancels a start that has not been acknowledged. Anything else is a no-op. With `failing`, the teardown ends
    /// in `failed(reason)` instead of `idle`, which is how a startup timeout is reported.
    public func cancel(failing reason: String? = nil) async {
        guard case .starting(let attempt) = phase else { return }
        await beginTeardown(attempt, beginReturned: false, failure: reason)
    }

    /// Stop during startup cancels; Stop while recording finishes once; any other Stop is a no-op.
    public func stop() async -> StopOutcome {
        switch phase {
        case .starting:
            await cancel()
            return .ignored
        case .recording(let attempt):
            teardown = nil
            phase = .stopping(attempt)
            armWatchdog(attempt)
            do {
                let output = try await port.end(attempt: attempt)
                guard isStopping(attempt) else {
                    deliverLate(attempt, output)
                    return .ignored
                }
                phase = .idle
                return .finished(output)
            } catch {
                guard isStopping(attempt) else {
                    abandonedFinishes.remove(attempt)
                    return .ignored
                }
                let message = error.localizedDescription
                phase = .failed(message)
                return .failed(message)
            }
        case .idle, .stopping, .failed:
            return .ignored
        }
    }

    /// The engine lost the stream on its own. Only the live attempt's report counts; the rest are stale.
    public func engineFailed(attempt: RecordlyRecordingAttempt, message: String) async {
        switch phase {
        case .starting(let current) where current == attempt:
            await beginTeardown(attempt, beginReturned: false, failure: message)
        case .recording(let current) where current == attempt:
            await finishAfterUnexpectedStop(attempt, message: message)
        default:
            return
        }
    }

    /// An established recording is finalized and kept, never deleted. Only if finalizing fails does it become `failed`.
    private func finishAfterUnexpectedStop(_ attempt: RecordlyRecordingAttempt, message: String) async {
        teardown = nil
        phase = .stopping(attempt)
        armWatchdog(attempt)
        do {
            let output = try await port.end(attempt: attempt)
            guard isStopping(attempt) else {
                deliverLate(attempt, output)
                return
            }
            phase = .idle
            onRecovered?(attempt, output, message)
        } catch {
            guard isStopping(attempt) else {
                abandonedFinishes.remove(attempt)
                return
            }
            phase = .failed("\(message) The recording could not be saved: \(error.localizedDescription)")
        }
    }

    /// If the port never returns, the session leaves `stopping` for a recoverable `failed` rather than hanging.
    /// A late return is then ignored because the phase no longer matches the attempt.
    private func armWatchdog(_ attempt: RecordlyRecordingAttempt) {
        watchdog?.cancel()
        let timeout = stuckTimeout
        let sleeper = sleeper
        watchdog = Task { @MainActor [weak self] in
            await sleeper(timeout)
            guard !Task.isCancelled, let self else { return }
            self.forceFail(attempt)
        }
    }

    private func forceFail(_ attempt: RecordlyRecordingAttempt) {
        guard isStopping(attempt) else { return }
        // No teardown state means the stuck call is a finish, whose output may still arrive.
        if teardown == nil { abandonedFinishes.insert(attempt) }
        let message = teardown?.failure ?? Self.stuckMessage
        teardown = nil
        phase = .failed(message)
    }

    /// A finish that returned after the watchdog gave up is a complete recording: hand it over once, never drop it.
    /// A failure left by a retry that this finish superseded is cleared so the recovery can open. A busy newer attempt
    /// is left untouched; the receiver keeps the output with its attempt until it is safe to open.
    private func deliverLate(_ attempt: RecordlyRecordingAttempt, _ output: RecordlyRecordingOutput) {
        guard abandonedFinishes.remove(attempt) != nil else { return }
        if case .failed = phase { phase = .idle }
        onRecovered?(attempt, output, Self.lateFinishMessage)
    }

    /// Leaves a `failed` phase. Only reachable after teardown was acknowledged. False when there is nothing to clear.
    @discardableResult
    public func clearFailure() -> Bool {
        guard case .failed = phase else { return false }
        phase = .idle
        return true
    }

    /// Back to idle from idle or failed. False while an attempt is still starting, recording or stopping.
    @discardableResult
    public func reset() -> Bool {
        switch phase {
        case .idle: return true
        case .failed:
            phase = .idle
            return true
        case .starting, .recording, .stopping: return false
        }
    }

    // MARK: Internals

    private func isStopping(_ attempt: RecordlyRecordingAttempt) -> Bool {
        if case .stopping(let current) = phase { return current == attempt }
        return false
    }

    private func settleStart(
        _ attempt: RecordlyRecordingAttempt,
        _ begun: Result<RecordlySourceSelection.ResolvedSource, RecordlyPortFailure>
    ) async -> StartOutcome {
        if case .starting(let current) = phase, current == attempt {
            switch begun {
            case .success(let resolved):
                phase = .recording(attempt)
                return .started(attempt, resolved)
            case .failure(let failure):
                switch failure {
                case .cancelled:
                    phase = .idle
                    return .cancelled
                case .permissionDenied, .noSource:
                    phase = .idle
                    return .failed(failure)
                case .engine(let message):
                    phase = .failed(message)
                    return .failed(failure)
                }
            }
        }

        // A cancel or a failure report got here first: the phase is `stopping` and the start only now returned.
        guard isStopping(attempt), teardown != nil else {
            // The watchdog already gave up on this attempt; a start that finally succeeded must still be unwound.
            if case .success = begun { await port.cancel(attempt: attempt) }
            return .cancelled
        }
        teardown?.beginReturned = true
        if case .success = begun {
            // A late success must not survive: ask the port to unwind what it just built.
            await port.cancel(attempt: attempt)
        }
        let failure = teardown?.failure
        settleTeardown(attempt)
        if let failure { return .failed(.engine(failure)) }
        return .cancelled
    }

    private func beginTeardown(_ attempt: RecordlyRecordingAttempt, beginReturned: Bool, failure: String?) async {
        teardown = Teardown(beginReturned: beginReturned, failure: failure)
        phase = .stopping(attempt)
        armWatchdog(attempt)
        await port.cancel(attempt: attempt)
        guard isStopping(attempt), teardown != nil else { return }
        teardown?.cancelReturned = true
        settleTeardown(attempt)
    }

    /// Publishes the outcome once both the port's cancel and the pending start have returned.
    private func settleTeardown(_ attempt: RecordlyRecordingAttempt) {
        guard isStopping(attempt), let state = teardown, state.beginReturned, state.cancelReturned else { return }
        teardown = nil
        if let failure = state.failure {
            phase = .failed(failure)
        } else {
            phase = .idle
        }
    }

    private static func busyMessage(_ phase: Phase) -> String {
        switch phase {
        case .idle: "Ready."
        case .starting: "A recording is already starting."
        case .recording: "A recording is already running."
        case .stopping: "The previous recording is still stopping."
        case .failed: "The previous recording failed. Dismiss that message before starting again."
        }
    }
}

/// Removes a saved Recordly checkpoint record, and optionally its raw recording, without following symlinks.
/// Missing files count as already removed. Roots come from the store, never from the checkpoint JSON.
public enum RecordlyDiscard {
    public static func removeCheckpointRecord(_ store: RecordlyCheckpointStore) throws {
        guard let parts = RecordlyCheckpointStore.components(ofAbsolute: store.checkpointRoot) else {
            throw RecordlyCheckpointStore.StoreError.invalidRoot("checkpoint")
        }
        try unlinkLeaf(parts + [RecordlyCheckpointStore.recordName])
    }

    /// The recording must sit strictly under the store's media root and outside its checkpoint folder.
    public static func removeMedia(_ store: RecordlyCheckpointStore, rawPath: String) throws {
        guard let root = RecordlyCheckpointStore.components(ofAbsolute: store.mediaRoot) else {
            throw RecordlyCheckpointStore.StoreError.invalidRoot("recording")
        }
        guard let checkpoint = RecordlyCheckpointStore.components(ofAbsolute: store.checkpointRoot) else {
            throw RecordlyCheckpointStore.StoreError.invalidRoot("checkpoint")
        }
        guard let media = RecordlyCheckpointStore.components(ofAbsolute: rawPath),
              media.count > root.count,
              Array(media.prefix(root.count)) == root
        else { throw RecordlyCheckpointStore.StoreError.mediaOutsideTrustedRoot }
        if media.count >= checkpoint.count, Array(media.prefix(checkpoint.count)) == checkpoint {
            throw RecordlyCheckpointStore.StoreError.mediaOutsideTrustedRoot
        }
        try unlinkLeaf(media)
    }

    private static func unlinkLeaf(_ parts: [String]) throws {
        guard let leaf = parts.last else { throw RecordlyCheckpointStore.StoreError.pathEscape }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw failure("open filesystem root", errno) }
        for name in parts.dropLast() {
            let next = openat(current, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let code = errno
            Darwin.close(current)
            guard next >= 0 else {
                if code == ENOENT { return }
                throw failure("open folder", code)
            }
            current = next
        }
        defer { Darwin.close(current) }
        if unlinkat(current, leaf, 0) != 0 {
            let code = errno
            if code == ENOENT { return }
            throw failure("remove file", code)
        }
    }

    private static func failure(_ operation: String, _ code: Int32) -> RecordlyCheckpointStore.StoreError {
        switch code {
        case ELOOP, ENOTDIR: .pathEscape
        default: .system(operation: operation, code: code)
        }
    }
}
