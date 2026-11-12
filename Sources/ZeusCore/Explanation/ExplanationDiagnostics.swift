import Foundation

/// Numeric diagnostics only. This value is owned by one serialized caller; it
/// neither samples the OS nor starts a timer. The injected clock must be monotonic
/// seconds (for example system uptime), not wall-clock dates. No token, identity,
/// absolute timestamp, error description, content, or path enters the report.
public struct ExplanationDiagnostics {
    public static let sampleLimit: UInt64 = 4_096
    public static let maximumIntervalSeconds: Double = 86_400

    /// Tokens are intentionally not Codable. Even reuse of an app turn identity
    /// creates a fresh attempt, so callbacks from a previous attempt stay stale.
    public struct TurnToken: Equatable, Sendable {
        fileprivate let identity: UUID
        fileprivate let nonce: UUID
    }
    public enum Failure: CaseIterable, Sendable {
        case input, provider, invalidEvent, rendering, audio, persistence, other
    }
    public struct Metric: Codable, Equatable, Sendable {
        public fileprivate(set) var count: UInt64 = 0
        public fileprivate(set) var totalSeconds: Double = 0
        public fileprivate(set) var maximumSeconds: Double = 0
        public var meanSeconds: Double? { count == 0 ? nil : totalSeconds / Double(count) }
        fileprivate mutating func append(_ seconds: Double) -> Bool {
            guard count < ExplanationDiagnostics.sampleLimit, seconds.isFinite,
                  (0...ExplanationDiagnostics.maximumIntervalSeconds).contains(seconds) else { return false }
            count += 1; totalSeconds += seconds; maximumSeconds = max(maximumSeconds, seconds)
            return true
        }
    }
    public struct FailureCounts: Codable, Equatable, Sendable {
        public fileprivate(set) var input: UInt64 = 0
        public fileprivate(set) var provider: UInt64 = 0
        public fileprivate(set) var invalidEvent: UInt64 = 0
        public fileprivate(set) var rendering: UInt64 = 0
        public fileprivate(set) var audio: UInt64 = 0
        public fileprivate(set) var persistence: UInt64 = 0
        public fileprivate(set) var other: UInt64 = 0
        public func count(for failure: Failure) -> UInt64 {
            switch failure {
            case .input: input
            case .provider: provider
            case .invalidEvent: invalidEvent
            case .rendering: rendering
            case .audio: audio
            case .persistence: persistence
            case .other: other
            }
        }
        fileprivate mutating func append(_ failure: Failure) -> Bool {
            guard count(for: failure) < ExplanationDiagnostics.sampleLimit else { return false }
            switch failure {
            case .input: input += 1
            case .provider: provider += 1
            case .invalidEvent: invalidEvent += 1
            case .rendering: rendering += 1
            case .audio: audio += 1
            case .persistence: persistence += 1
            case .other: other += 1
            }
            return true
        }
    }
    /// Fixed-size aggregates. A count at sampleLimit is saturated: further samples
    /// are rejected, not presented as complete coverage. Codable is for exporting
    /// this snapshot; a decoded report never authorizes or changes the collector.
    public struct Report: Codable, Equatable, Sendable {
        public fileprivate(set) var schemaVersion: UInt64 = 1
        public fileprivate(set) var sampleLimit: UInt64 = ExplanationDiagnostics.sampleLimit
        public fileprivate(set) var turnsStarted: UInt64 = 0
        public fileprivate(set) var firstAudioStartLatency = Metric()
        /// Submission to the UI state, not render completion or on-screen photons.
        public fileprivate(set) var firstVisualStateSubmissionLatency = Metric()
        /// Media seconds, independent of selected playback speed. Not wall latency.
        public fileprivate(set) var cueSchedulerLatenessMediaSeconds = Metric()
        /// Only the synchronous cleanup block bracketed by the caller; this says
        /// nothing about asynchronous resource teardown or OS capture cessation.
        public fileprivate(set) var cancellationSynchronousCleanupSeconds = Metric()
        public fileprivate(set) var failures = FailureCounts()
        public fileprivate(set) var processSamples: UInt64 = 0
        /// Difference between first and latest accepted cumulative process CPU
        /// readings, including gaps. Process-wide, not attributable to this feature.
        public fileprivate(set) var processCPUSecondsDelta: Double?
        public fileprivate(set) var peakPhysicalFootprintBytes: UInt64?
    }

    private struct ActiveTurn {
        let token: TurnToken
        let began: Double
        var audioRecorded = false
        var visualRecorded = false
        var lastActualMediaTime: Double?
        var lastDueMediaTime: Double?
        var cancellationBegan: Double?
        var cancellationRecorded = false
    }
    private let clock: () -> Double
    private var lastClock: Double?
    private var active: ActiveTurn?
    private var lastCPUSeconds: Double?
    private var report = Report()

    public init(clock: @escaping () -> Double) { self.clock = clock }
    public func snapshot() -> Report { report }

    @discardableResult
    public mutating func beginTurn(identity: UUID) -> TurnToken? {
        guard report.turnsStarted < Self.sampleLimit, let now = checkedClock() else { return nil }
        let token = TurnToken(identity: identity, nonce: UUID())
        active = ActiveTurn(token: token, began: now)
        report.turnsStarted += 1; lastClock = now
        return token
    }
    /// Retire callbacks even if the diagnostic clock has failed. Retirement needs
    /// no timing measurement and does not alter any exported metric.
    @discardableResult
    public mutating func endTurn(_ token: TurnToken) -> Bool {
        guard active?.token == token else { return false }
        active = nil
        return true
    }
    @discardableResult
    public mutating func recordFirstAudioStart(for token: TurnToken) -> Bool {
        guard let turn = running(token), !turn.audioRecorded, let now = checkedClock(),
              report.firstAudioStartLatency.append(now - turn.began) else { return false }
        active?.audioRecorded = true; lastClock = now
        return true
    }
    @discardableResult
    public mutating func recordFirstVisualStateSubmitted(for token: TurnToken) -> Bool {
        guard let turn = running(token), !turn.visualRecorded, let now = checkedClock(),
              report.firstVisualStateSubmissionLatency.append(now - turn.began) else { return false }
        active?.visualRecorded = true; lastClock = now
        return true
    }
    @discardableResult
    public mutating func recordCueSchedulerLateness(for token: TurnToken, actualMediaTime: Double, dueMediaTime: Double) -> Bool {
        guard let turn = running(token), actualMediaTime.isFinite, dueMediaTime.isFinite,
              (0...Self.maximumIntervalSeconds).contains(actualMediaTime), (0...actualMediaTime).contains(dueMediaTime),
              actualMediaTime >= (turn.lastActualMediaTime ?? 0), dueMediaTime >= (turn.lastDueMediaTime ?? 0),
              let now = checkedClock(), report.cueSchedulerLatenessMediaSeconds.append(actualMediaTime - dueMediaTime) else { return false }
        active?.lastActualMediaTime = actualMediaTime; active?.lastDueMediaTime = dueMediaTime; lastClock = now
        return true
    }
    @discardableResult
    public mutating func beginCancellation(for token: TurnToken) -> Bool {
        guard let turn = running(token), !turn.cancellationRecorded, let now = checkedClock() else { return false }
        active?.cancellationBegan = now; lastClock = now
        return true
    }
    @discardableResult
    public mutating func finishCancellation(for token: TurnToken) -> Bool {
        guard let turn = active, turn.token == token, let began = turn.cancellationBegan,
              !turn.cancellationRecorded, let now = checkedClock(),
              report.cancellationSynchronousCleanupSeconds.append(now - began) else { return false }
        active?.cancellationRecorded = true; active?.cancellationBegan = nil; lastClock = now
        // This attempt remains closed to new audio/visual events until endTurn.
        return true
    }
    @discardableResult
    public mutating func recordFailure(_ failure: Failure, for token: TurnToken) -> Bool {
        guard active?.token == token, let now = checkedClock(), report.failures.append(failure) else { return false }
        lastClock = now
        return true
    }
    /// Optional caller-supplied process observations. CPU must be cumulative and
    /// nondecreasing; memory may decrease. No sampling or hardware calls occur here.
    @discardableResult
    public mutating func recordProcessSample(for token: TurnToken, cumulativeCPUSeconds: Double? = nil,
                                             physicalFootprintBytes: UInt64? = nil) -> Bool {
        guard active?.token == token, report.processSamples < Self.sampleLimit,
              cumulativeCPUSeconds != nil || physicalFootprintBytes != nil else { return false }
        if let cpu = cumulativeCPUSeconds {
            guard cpu.isFinite, (0...1_000_000_000_000).contains(cpu), cpu >= (lastCPUSeconds ?? 0) else { return false }
        }
        if let bytes = physicalFootprintBytes { guard bytes <= 1 << 50 else { return false } }
        guard let now = checkedClock() else { return false }
        if let cpu = cumulativeCPUSeconds {
            report.processCPUSecondsDelta = (report.processCPUSecondsDelta ?? 0) + (lastCPUSeconds.map { cpu - $0 } ?? 0)
            lastCPUSeconds = cpu
        }
        if let bytes = physicalFootprintBytes { report.peakPhysicalFootprintBytes = max(report.peakPhysicalFootprintBytes ?? 0, bytes) }
        report.processSamples += 1; lastClock = now
        return true
    }
    private func running(_ token: TurnToken) -> ActiveTurn? {
        guard let active, active.token == token, active.cancellationBegan == nil, !active.cancellationRecorded else { return nil }
        return active
    }
    private func checkedClock() -> Double? {
        let now = clock()
        guard now.isFinite, now >= 0, now >= (lastClock ?? 0) else { return nil }
        return now
    }
}
