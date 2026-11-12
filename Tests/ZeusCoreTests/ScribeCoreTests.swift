import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe capture acknowledgement boundary")
struct ScribeCaptureWindowTests {
    @Test func audioFromPermissionSetupIsNotReplayedIntoTheMeeting() {
        // The microphone started at t=1, but the other source's permission dialog completed at t=10.
        #expect(!ScribeCaptureWindow.admits(start: 1, duration: 0.1, acknowledgedAt: 10))
        // A block that straddles acknowledgement is withheld in full; no partial pre-recording audio leaks.
        #expect(!ScribeCaptureWindow.admits(start: 9.95, duration: 0.1, acknowledgedAt: 10))
        #expect(ScribeCaptureWindow.admits(start: 10, duration: 0.1, acknowledgedAt: 10))
        #expect(ScribeCaptureWindow.admits(start: 10.1, duration: 0.1, acknowledgedAt: 10))
    }

    @Test func unknownTimingAndUnacknowledgedCaptureFailClosed() {
        #expect(!ScribeCaptureWindow.admits(start: nil, duration: 0.1, acknowledgedAt: 10))
        #expect(!ScribeCaptureWindow.admits(start: 10, duration: 0.1, acknowledgedAt: nil))
        #expect(!ScribeCaptureWindow.admits(start: .nan, duration: 0.1, acknowledgedAt: 10))
        #expect(!ScribeCaptureWindow.admits(start: 10, duration: .infinity, acknowledgedAt: 10))
        #expect(!ScribeCaptureWindow.admits(start: 10, duration: 0, acknowledgedAt: 10))
        #expect(!ScribeCaptureWindow.admits(start: 10, duration: -1, acknowledgedAt: 10))
    }
}

// MARK: - Scribe sinks

private final class RecordingFrameStore: ScribeFrameStore, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [ScribeAudioFrame] = []

    var stored: [ScribeAudioFrame] { lock.withLock { frames } }

    func store(_ frame: ScribeAudioFrame) throws {
        lock.withLock { frames.append(frame) }
    }
}

private struct StoreFailure: Error {}

private final class FailingFrameStore: ScribeFrameStore, @unchecked Sendable {
    func store(_ frame: ScribeAudioFrame) throws {
        throw StoreFailure()
    }
}

private final class RecordingTranscriber: ScribeTranscriber, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [ScribeAudioFrame] = []
    private var finished: [ScribeSessionID] = []

    var ingested: [ScribeAudioFrame] { lock.withLock { frames } }
    var finishedSessions: [ScribeSessionID] { lock.withLock { finished } }

    func ingest(_ frame: ScribeAudioFrame) {
        lock.withLock { frames.append(frame) }
    }

    func finish(session: ScribeSessionID) {
        lock.withLock { finished.append(session) }
    }
}

private final class StubMuteSource: ScribeMicMuteSource, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ScribeMuteState

    init(_ state: ScribeMuteState) { self.state = state }

    func set(_ new: ScribeMuteState) { lock.withLock { state = new } }

    func currentMuteState() -> ScribeMuteState { lock.withLock { state } }
}

private struct RouterRig {
    let session = ScribeSessionID()
    let mute: StubMuteSource
    let store = RecordingFrameStore()
    let transcriber = RecordingTranscriber()
    let router: ScribeFrameRouter

    init(mute initial: ScribeMuteState) {
        let mute = StubMuteSource(initial)
        let store = self.store
        let transcriber = self.transcriber
        self.mute = mute
        self.router = ScribeFrameRouter(
            session: session,
            muteSource: mute,
            store: store,
            transcriber: transcriber
        )
    }

    func frame(_ source: ScribeAudioSource, _ sequence: UInt64, session override: ScribeSessionID? = nil) -> ScribeAudioFrame {
        ScribeAudioFrame(
            session: override ?? session,
            source: source,
            sequence: sequence,
            hostTime: TimeInterval(sequence) * 0.02,
            sampleCount: 320,
            payload: Data([UInt8(truncatingIfNeeded: sequence)])
        )
    }
}

private final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    var all: [String] { lock.withLock { entries } }

    func add(_ entry: String) { lock.withLock { entries.append(entry) } }
}

/// These deliberately blocking contention workers must not depend on the global dispatch pool,
/// which the complete parallel test module also uses. Each case starts at most two owned threads;
/// the existing bounded waits and deferred sink release still detect hangs and ordering failures.
private func startRouterContentionWorker(group: DispatchGroup, operation: @escaping @Sendable () -> Void) {
    group.enter()
    let thread = Thread {
        defer { group.leave() }
        operation()
    }
    thread.name = "zeus-router-contention-test"
    thread.start()
}

/// One-shot arm flag shared by the blocking sinks: only the first delivery blocks.
private final class BlockOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = true

    /// True exactly once, until `disarm()`.
    func take() -> Bool { lock.withLock { let was = armed; armed = false; return was } }
    func disarm() { lock.withLock { armed = false } }
}

/// Sink-side hold deadline. It must stay well above the orchestration waits (2 s) so delayed scheduling
/// cannot auto-release a sink before the contention assertion.
private let sinkHoldTimeout: TimeInterval = 6

/// Records whether a blocking sink gave up waiting for its release (auto-release instead of a real release).
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var didTimeOut: Bool { lock.withLock { value } }
    func mark() { lock.withLock { value = true } }
}

/// Blocks inside the first `store` until released (bounded), so a test can interleave other router
/// calls deterministically. Later calls never block.
private final class BlockingFrameStore: ScribeFrameStore, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let once = BlockOnce()
    let timeout = TimeoutFlag()
    private let log: OrderLog

    init(log: OrderLog) { self.log = log }

    /// Disarms blocking and unblocks a pending delivery. Safe to call repeatedly.
    func releaseAll() {
        once.disarm()
        release.signal()
    }

    func releaseBlocked() { release.signal() }

    func store(_ frame: ScribeAudioFrame) throws {
        guard once.take() else { return }
        log.add("store-start")
        entered.signal()
        if release.wait(timeout: .now() + sinkHoldTimeout) == .timedOut { timeout.mark() }
        log.add("store-done")
    }
}

/// Blocks inside the first `ingest` until released (bounded). `finish` is only logged.
private final class BlockingTranscriber: ScribeTranscriber, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let once = BlockOnce()
    let timeout = TimeoutFlag()
    private let log: OrderLog

    init(log: OrderLog) { self.log = log }

    /// Disarms blocking and unblocks a pending delivery. Safe to call repeatedly.
    func releaseAll() {
        once.disarm()
        release.signal()
    }

    func releaseBlocked() { release.signal() }

    func ingest(_ frame: ScribeAudioFrame) {
        guard once.take() else { return }
        log.add("ingest-start")
        entered.signal()
        if release.wait(timeout: .now() + sinkHoldTimeout) == .timedOut { timeout.mark() }
        log.add("ingest-done")
    }

    func finish(session: ScribeSessionID) {
        log.add("finish")
    }
}

// MARK: - 1-4 Router and mic gate

@Suite("Scribe mic gate and router")
struct ScribeMicGateRouterTests {
    @Test func anUnsupportedMicrophoneOwnerStillLetsTheMicrophoneThrough() {
        let scan = ScribeScanReducer.reduce(
            reads: [.input(pid: 50, bundleID: "com.example.unsupported-call")],
            running: [], ownPID: 1
        )
        #expect(scan == .incomplete)
        // Another app sharing the input never withholds the person's microphone; only the device's mute does.
        let rig = RouterRig(mute: ScribeMuteResolver.resolve(device: .noSwitch))
        #expect(rig.router.route(rig.frame(.microphone, 0)) == .delivered)
        #expect(rig.router.route(rig.frame(.system, 1)) == .delivered)
        let muted = RouterRig(mute: ScribeMuteResolver.resolve(device: .muted))
        #expect(muted.router.route(muted.frame(.microphone, 0)) != .delivered)
        #expect(muted.store.stored.isEmpty)
    }

    @Test func mutedAndUnknownMicFramesReachNeitherStoreNorTranscriber() {
        for state in [ScribeMuteState.muted, .unknown] {
            let rig = RouterRig(mute: state)
            for sequence in 0..<5 { rig.router.route(rig.frame(.microphone, UInt64(sequence))) }
            #expect(rig.store.stored.isEmpty)
            #expect(rig.transcriber.ingested.isEmpty)
            #expect(rig.router.counters.droppedMicrophone == 5)
            #expect(rig.router.counters.deliveredMicrophone == 0)
        }
    }

    @Test func dropReasonDistinguishesMutedFromUnknown() {
        let muted = RouterRig(mute: .muted)
        #expect(muted.router.route(muted.frame(.microphone, 0)) == .droppedMicrophone(.muted))
        #expect(muted.router.counters.droppedMicrophoneMuted == 1)
        let unknown = RouterRig(mute: .unknown)
        #expect(unknown.router.route(unknown.frame(.microphone, 0)) == .droppedMicrophone(.muteUnknown))
        #expect(unknown.router.counters.droppedMicrophoneUnknown == 1)
    }

    @Test func unmutedMicFramesReachBothSinks() {
        let rig = RouterRig(mute: .unmuted)
        let frames = (0..<3).map { rig.frame(.microphone, UInt64($0)) }
        for frame in frames { #expect(rig.router.route(frame) == .delivered) }
        #expect(rig.store.stored == frames)
        #expect(rig.transcriber.ingested == frames)
        #expect(rig.router.counters.deliveredMicrophone == 3)
    }

    @Test func systemAudioIsIndependentOfMute() {
        for state in [ScribeMuteState.muted, .unknown, .unmuted] {
            let rig = RouterRig(mute: state)
            let frame = rig.frame(.system, 7)
            #expect(rig.router.route(frame) == .delivered)
            #expect(rig.store.stored == [frame])
            #expect(rig.transcriber.ingested == [frame])
            #expect(rig.router.counters.deliveredSystem == 1)
        }
    }

    @Test func gateIsPureAndFailsClosedOnUnknown() {
        let gate = ScribeMicGate()
        let session = ScribeSessionID()
        let mic = ScribeAudioFrame(session: session, source: .microphone, sequence: 0, hostTime: 0, sampleCount: 1, payload: Data())
        let system = ScribeAudioFrame(session: session, source: .system, sequence: 0, hostTime: 0, sampleCount: 1, payload: Data())
        #expect(gate.route(mic, mute: .unmuted) == .deliver)
        #expect(gate.route(mic, mute: .muted) == .dropMicrophone(.muted))
        #expect(gate.route(mic, mute: .unknown) == .dropMicrophone(.muteUnknown))
        for state in [ScribeMuteState.unmuted, .muted, .unknown] {
            #expect(gate.route(system, mute: state) == .deliver)
        }
    }

    @Test func muteChangeTakesEffectOnVeryNextFrame() {
        let rig = RouterRig(mute: .unmuted)
        let first = rig.frame(.microphone, 0)
        let second = rig.frame(.microphone, 1)
        let third = rig.frame(.microphone, 2)

        #expect(rig.router.route(first) == .delivered)
        rig.mute.set(.muted)
        #expect(rig.router.route(second) == .droppedMicrophone(.muted))
        rig.mute.set(.unmuted)
        #expect(rig.router.route(third) == .delivered)

        #expect(rig.store.stored == [first, third])
        #expect(rig.transcriber.ingested == [first, third])
    }

    @Test func staleSessionFramesAreDroppedFromBothSinks() {
        let rig = RouterRig(mute: .unmuted)
        let other = ScribeSessionID()
        #expect(rig.router.route(rig.frame(.microphone, 0, session: other)) == .droppedStale)
        #expect(rig.router.route(rig.frame(.system, 1, session: other)) == .droppedStale)
        #expect(rig.store.stored.isEmpty)
        #expect(rig.transcriber.ingested.isEmpty)
        #expect(rig.router.counters.droppedStale == 2)
    }

    @Test func switchingActiveSessionMakesOldFramesStale() {
        let rig = RouterRig(mute: .unmuted)
        let next = ScribeSessionID()
        rig.router.setActiveSession(next)
        #expect(rig.router.route(rig.frame(.system, 0)) == .droppedStale)
        #expect(rig.router.route(rig.frame(.system, 1, session: next)) == .delivered)
        rig.router.setActiveSession(nil)
        #expect(rig.router.route(rig.frame(.system, 2, session: next)) == .droppedStale)
        #expect(rig.store.stored.count == 1)
    }

    @Test func storeFailureStillFeedsTranscriberAndIsCounted() {
        let session = ScribeSessionID()
        let transcriber = RecordingTranscriber()
        let router = ScribeFrameRouter(
            session: session,
            muteSource: StubMuteSource(.unmuted),
            store: FailingFrameStore(),
            transcriber: transcriber
        )
        let frame = ScribeAudioFrame(session: session, source: .system, sequence: 0, hostTime: 0, sampleCount: 1, payload: Data())
        #expect(router.route(frame) == .delivered)
        #expect(transcriber.ingested == [frame])
        #expect(router.counters.storeFailures == 1)
    }

    @Test func finishNotifiesTranscriberForActiveSession() {
        let rig = RouterRig(mute: .unmuted)
        rig.router.finish()
        #expect(rig.transcriber.finishedSessions == [rig.session])
    }

    @Test func framesAfterFinishAreRejectedAndFinishIsIdempotent() {
        let rig = RouterRig(mute: .unmuted)
        let before = rig.frame(.system, 0)
        #expect(rig.router.route(before) == .delivered)
        rig.router.finish()
        rig.router.finish()
        #expect(rig.transcriber.finishedSessions == [rig.session])
        #expect(rig.router.route(rig.frame(.system, 1)) == .droppedStale)
        #expect(rig.router.route(rig.frame(.microphone, 2)) == .droppedStale)
        #expect(rig.store.stored == [before])
        #expect(rig.transcriber.ingested == [before])
        #expect(rig.router.counters.droppedStale == 2)

        // A new session reopens admission.
        let next = ScribeSessionID()
        rig.router.setActiveSession(next)
        #expect(rig.router.route(rig.frame(.system, 3, session: next)) == .delivered)
    }

    @Test func setActiveSessionWaitsForInFlightDeliveryAndNoOldFrameReachesSinksAfterward() {
        let log = OrderLog()
        let store = BlockingFrameStore(log: log)
        let transcriber = RecordingTranscriber()
        let session = ScribeSessionID()
        let next = ScribeSessionID()
        let router = ScribeFrameRouter(
            session: session,
            muteSource: StubMuteSource(.unmuted),
            store: store,
            transcriber: transcriber
        )
        let frame = ScribeAudioFrame(session: session, source: .system, sequence: 0, hostTime: 0, sampleCount: 1, payload: Data())
        let group = DispatchGroup()
        let started = DispatchSemaphore(value: 0)
        let switched = DispatchSemaphore(value: 0)
        // Always unblock the sink, even if an expectation below fails, so a regression fails instead of hanging.
        defer { store.releaseAll() }

        // This test bounds hangs and checks ordering under contention; it does not prove the lock by itself.
        startRouterContentionWorker(group: group) { router.route(frame) }
        // Frame A passed validation and is blocked inside the store sink.
        guard store.entered.wait(timeout: .now() + 2) == .success else {
            Issue.record("frame never reached the store sink")
            return
        }
        startRouterContentionWorker(group: group) {
            log.add("switch-start")
            started.signal()
            router.setActiveSession(next)
            log.add("switched")
            switched.signal()
        }
        guard started.wait(timeout: .now() + 2) == .success else {
            Issue.record("switch worker never started")
            return
        }
        // The switch must not complete while A is mid-delivery (grace period after the worker started).
        #expect(switched.wait(timeout: .now() + 0.2) == .timedOut)
        store.releaseBlocked()
        // On timeout, return (deferred release runs) instead of calling router.route, which could block.
        guard group.wait(timeout: .now() + 2) == .success else {
            Issue.record("workers did not finish after the store sink was released")
            return
        }
        guard !store.timeout.didTimeOut else {
            Issue.record("store sink auto-released before the test released it")
            return
        }

        #expect(log.all == ["store-start", "switch-start", "store-done", "switched"])
        #expect(transcriber.ingested == [frame])   // A finished delivering to both sinks before the switch
        // After the switch returned, A is stale for both sinks. The sink no longer blocks, so this cannot hang.
        #expect(router.route(frame) == .droppedStale)
        #expect(transcriber.ingested == [frame])
        #expect(log.all == ["store-start", "switch-start", "store-done", "switched"])
    }

    @Test func finishDrainsInFlightDeliveryBeforeTranscriberFinishAndClosesAdmission() {
        let log = OrderLog()
        let transcriber = BlockingTranscriber(log: log)
        let session = ScribeSessionID()
        let router = ScribeFrameRouter(
            session: session,
            muteSource: StubMuteSource(.unmuted),
            store: RecordingFrameStore(),
            transcriber: transcriber
        )
        let frame = ScribeAudioFrame(session: session, source: .system, sequence: 0, hostTime: 0, sampleCount: 1, payload: Data())
        let group = DispatchGroup()
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        // Always unblock the sink, even if an expectation below fails, so a regression fails instead of hanging.
        defer { transcriber.releaseAll() }

        // This test bounds hangs and checks ordering under contention; it does not prove the lock by itself.
        startRouterContentionWorker(group: group) { router.route(frame) }
        // The frame is blocked inside ingest.
        guard transcriber.entered.wait(timeout: .now() + 2) == .success else {
            Issue.record("frame never reached the transcriber sink")
            return
        }
        startRouterContentionWorker(group: group) {
            log.add("finish-start")
            started.signal()
            router.finish()
            finished.signal()
        }
        guard started.wait(timeout: .now() + 2) == .success else {
            Issue.record("finish worker never started")
            return
        }
        // Grace period after the worker started: finish must still be waiting on the in-flight delivery.
        #expect(finished.wait(timeout: .now() + 0.2) == .timedOut)
        #expect(log.all == ["ingest-start", "finish-start"])   // finish has not reached the transcriber yet
        transcriber.releaseBlocked()
        // On timeout, return (deferred release runs) instead of calling router.route or counters, which could block.
        guard group.wait(timeout: .now() + 2) == .success else {
            Issue.record("workers did not finish after the transcriber sink was released")
            return
        }
        guard !transcriber.timeout.didTimeOut else {
            Issue.record("transcriber sink auto-released before the test released it")
            return
        }

        let expected = ["ingest-start", "finish-start", "ingest-done", "finish"]
        #expect(log.all == expected)
        // The sink no longer blocks, so this cannot hang even if admission was not closed.
        #expect(router.route(frame) == .droppedStale)
        #expect(log.all == expected)
        #expect(router.counters.droppedStale == 1)
        #expect(router.counters.deliveredSystem == 1)
    }
}

// MARK: - 5 Session machine

@Suite("Scribe session machine")
struct ScribeSessionMachineTests {
    private func recording(_ id: ScribeSessionID) -> ScribeSessionMachine {
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 0)
        _ = machine.acknowledgeCapture(id, now: 1)
        return machine
    }

    @Test func recordingBeginsOnlyAfterAcknowledgement() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        let started = machine.start(id, now: 10)
        #expect(started.isApplied)
        #expect(started.events.isEmpty)
        #expect(machine.phase == .starting(id))
        #expect(machine.requestEnd(id, now: 11, grace: 5).outcome == .invalid)
        #expect(machine.phase == .starting(id))

        let ack = machine.acknowledgeCapture(id, now: 12)
        #expect(ack.events == [.recordingStarted(id)])
        #expect(machine.phase == .recording(id, since: 12))
    }

    @Test func staleCommandsAreRejectedWithoutChange() {
        let id = ScribeSessionID()
        let other = ScribeSessionID()
        var machine = recording(id)
        let before = machine

        let results = [
            machine.acknowledgeCapture(other, now: 2),
            machine.requestEnd(other, now: 2, grace: 5),
            machine.keepRecording(other),
            machine.captureEnded(other),
            machine.transcriptUpdated(other),
            machine.transcriptFinalized(other),
            machine.notesReady(other),
            machine.cancel(other),
            machine.fail(other, reason: "x")
        ]
        for result in results {
            #expect(result.outcome == .stale)
            #expect(result.events.isEmpty)
        }
        #expect(machine == before)
    }

    @Test func commandsOnIdleMachineAreStale() {
        var machine = ScribeSessionMachine()
        let id = ScribeSessionID()
        #expect(machine.acknowledgeCapture(id, now: 0).outcome == .stale)
        #expect(machine.cancel(id).outcome == .stale)
        #expect(machine.phase == .idle)
    }

    @Test func startWhileActiveReplacesAndCancelsOldSession() {
        let old = ScribeSessionID()
        let new = ScribeSessionID()
        var machine = recording(old)
        let replaced = machine.start(new, now: 20)
        #expect(replaced.isApplied)
        #expect(replaced.events == [.cancelled(old)])
        #expect(machine.phase == .starting(new))
        #expect(machine.acknowledgeCapture(old, now: 21).outcome == .stale)
        #expect(machine.phase == .starting(new))
    }

    @Test func restartingSameActiveIDIsInvalid() {
        let id = ScribeSessionID()
        var machine = recording(id)
        #expect(machine.start(id, now: 5).outcome == .invalid)
        #expect(machine.phase == .recording(id, since: 1))
    }

    @Test func startAfterTerminalSessionEmitsNoCancel() {
        let first = ScribeSessionID()
        let second = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(first, now: 0)
        _ = machine.fail(first, reason: "boom")
        let result = machine.start(second, now: 1)
        #expect(result.events.isEmpty)
        #expect(machine.phase == .starting(second))
    }

    @Test func cancelFromEveryActivePhase() {
        let id = ScribeSessionID()

        var starting = ScribeSessionMachine()
        _ = starting.start(id, now: 0)

        var rec = recording(id)

        var ending = recording(id)
        _ = ending.requestEnd(id, now: 2, grace: 5)

        var processing = recording(id)
        _ = processing.captureEnded(id)

        for var machine in [starting, rec, ending, processing] {
            let result = machine.cancel(id)
            #expect(result.isApplied)
            #expect(result.events == [.cancelled(id)])
            #expect(machine.phase == .idle)
        }
        _ = rec.cancel(id)
        #expect(rec.cancel(id).outcome == .stale)
    }

    @Test func cancelOrFailOnTerminalSessionIsInvalid() {
        let id = ScribeSessionID()
        var machine = recording(id)
        _ = machine.captureEnded(id)
        _ = machine.transcriptFinalized(id)
        _ = machine.notesReady(id)
        #expect(machine.phase == .complete(id))
        #expect(machine.cancel(id).outcome == .invalid)
        #expect(machine.fail(id, reason: "late").outcome == .invalid)
        #expect(machine.phase == .complete(id))
    }

    @Test func failEmitsReasonAndStopsActivity() {
        let id = ScribeSessionID()
        var machine = recording(id)
        let result = machine.fail(id, reason: "capture lost")
        #expect(result.events == [.failed(id, reason: "capture lost")])
        #expect(machine.phase == .failed(id, reason: "capture lost"))
        #expect(!machine.phase.isActive)
    }

    @Test func keepRecordingIsOnlyValidInEnding() {
        let id = ScribeSessionID()

        var starting = ScribeSessionMachine()
        _ = starting.start(id, now: 0)
        #expect(starting.keepRecording(id).outcome == .invalid)

        var rec = recording(id)
        #expect(rec.keepRecording(id).outcome == .invalid)
        #expect(rec.phase == .recording(id, since: 1))

        var ending = recording(id)
        _ = ending.requestEnd(id, now: 5, grace: 10)
        let kept = ending.keepRecording(id)
        #expect(kept.events == [.endingCancelled(id)])
        #expect(ending.phase == .recording(id, since: 1))

        var processing = recording(id)
        _ = processing.captureEnded(id)
        #expect(processing.keepRecording(id).outcome == .invalid)
        #expect(processing.phase == .processing(id))
    }

    @Test func countdownExpiryAloneDoesNotEndCapture() {
        let id = ScribeSessionID()
        var machine = recording(id)
        let request = machine.requestEnd(id, now: 10, grace: 5)
        #expect(request.events == [.endingCountdown(id, remaining: 5)])
        #expect(machine.phase == .ending(id, deadline: 15))

        #expect(!machine.isCountdownExpired(now: 14.9))
        #expect(machine.isCountdownExpired(now: 15))
        let tick = machine.tick(now: 100)
        #expect(tick.events == [.endingCountdown(id, remaining: 0)])
        #expect(machine.phase == .ending(id, deadline: 15))
        #expect(!tick.events.contains(.recordingEnded(id)))
    }

    @Test func tickOutsideEndingIsInvalid() {
        let id = ScribeSessionID()
        var machine = recording(id)
        #expect(machine.tick(now: 5).outcome == .invalid)
    }

    @Test func negativeGraceIsClampedToZero() {
        let id = ScribeSessionID()
        var machine = recording(id)
        let result = machine.requestEnd(id, now: 10, grace: -3)
        #expect(result.events == [.endingCountdown(id, remaining: 0)])
        #expect(machine.phase == .ending(id, deadline: 10))
    }

    @Test func captureEndedMovesToProcessingFromRecordingAndEnding() {
        let id = ScribeSessionID()

        var direct = recording(id)
        #expect(direct.captureEnded(id).events == [.recordingEnded(id)])
        #expect(direct.phase == .processing(id))

        var viaEnding = recording(id)
        _ = viaEnding.requestEnd(id, now: 2, grace: 5)
        #expect(viaEnding.captureEnded(id).events == [.recordingEnded(id)])
        #expect(viaEnding.phase == .processing(id))

        var starting = ScribeSessionMachine()
        _ = starting.start(id, now: 0)
        #expect(starting.captureEnded(id).outcome == .invalid)
    }

    @Test func fullLifecycleEmitsEventsInOrder() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        var events: [ScribeLifecycleEvent] = []

        events += machine.start(id, now: 0).events
        events += machine.acknowledgeCapture(id, now: 1).events
        events += machine.transcriptUpdated(id).events
        events += machine.requestEnd(id, now: 60, grace: 5).events
        events += machine.captureEnded(id).events
        #expect(machine.notesReady(id).outcome == .invalid)
        events += machine.transcriptFinalized(id).events
        #expect(machine.phase == .processing(id))
        #expect(machine.transcriptFinalized(id).outcome == .invalid)
        events += machine.notesReady(id).events

        #expect(machine.phase == .complete(id))
        #expect(events == [
            .recordingStarted(id),
            .transcriptUpdated(id),
            .endingCountdown(id, remaining: 5),
            .recordingEnded(id),
            .transcriptFinalized(id),
            .notesReady(id)
        ])
    }

    @Test func transcriptUpdatesAreRejectedBeforeRecordingAndAfterComplete() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 0)
        #expect(machine.transcriptUpdated(id).outcome == .invalid)
        _ = machine.acknowledgeCapture(id, now: 1)
        _ = machine.captureEnded(id)
        _ = machine.transcriptFinalized(id)
        _ = machine.notesReady(id)
        #expect(machine.transcriptUpdated(id).outcome == .invalid)
    }
}

// MARK: - 6 Transcript

@Suite("Scribe transcript")
struct ScribeTranscriptTests {
    private let session = ScribeSessionID()

    private func segment(
        _ id: String,
        _ text: String,
        start: TimeInterval = 0,
        end: TimeInterval? = nil,
        speaker: ScribeSpeaker = .you,
        final: Bool = false,
        session override: ScribeSessionID? = nil
    ) -> ScribeTranscriptSegment {
        ScribeTranscriptSegment(
            id: id,
            session: override ?? session,
            speaker: speaker,
            start: start,
            end: end ?? start + 1,
            text: text,
            isFinal: final
        )
    }

    @Test func provisionalUpsertReplacesInPlace() {
        var transcript = ScribeTranscript(session: session)
        #expect(transcript.upsert(segment("a", "hel")) == .inserted)
        #expect(transcript.upsert(segment("a", "hello wor")) == .replaced)
        #expect(transcript.segments.count == 1)
        #expect(transcript.segments[0].text == "hello wor")
        #expect(!transcript.segments[0].isFinal)
    }

    @Test func finalReplacesProvisionalAndThenLocks() {
        var transcript = ScribeTranscript(session: session)
        transcript.upsert(segment("a", "hello wor"))
        #expect(transcript.upsert(segment("a", "hello world", final: true)) == .replaced)
        #expect(transcript.segments[0].isFinal)
        #expect(transcript.upsert(segment("a", "garbled")) == .ignoredLocked)
        #expect(transcript.upsert(segment("a", "other final", final: true)) == .ignoredLocked)
        #expect(transcript.segments[0].text == "hello world")
    }

    @Test func segmentsAreOrderedByStart() {
        var transcript = ScribeTranscript(session: session)
        transcript.upsert(segment("late", "second", start: 9))
        transcript.upsert(segment("early", "first", start: 2))
        transcript.upsert(segment("mid", "middle", start: 5))
        #expect(transcript.segments.map(\.id) == ["early", "mid", "late"])
        // A replacement that moves a segment re-sorts.
        transcript.upsert(segment("early", "first", start: 20))
        #expect(transcript.segments.map(\.id) == ["mid", "late", "early"])
    }

    @Test func finalizeRejectsLateSegmentsAndDoesNotPromoteProvisional() {
        var transcript = ScribeTranscript(session: session)
        transcript.upsert(segment("a", "done", final: true))
        transcript.upsert(segment("b", "tail", start: 1))
        transcript.finalize()
        #expect(transcript.isFinalized)
        #expect(transcript.segments.map(\.isFinal) == [true, false])
        #expect(transcript.finalSegments.map(\.id) == ["a"])
        #expect(transcript.unresolvedSegments.map(\.id) == ["b"])
        #expect(transcript.meetingTranscript().lines.map(\.text) == ["done"])
        #expect(transcript.upsert(segment("c", "late provisional", start: 3)) == .rejectedFinalized)
        #expect(transcript.upsert(segment("d", "late final", start: 4, final: true)) == .rejectedFinalized)
        #expect(transcript.segments.map(\.id) == ["a", "b"])
    }

    @Test func finalizedTranscriptNeverFeedsUnresolvedTextToNotes() throws {
        var transcript = ScribeTranscript(session: session)
        transcript.upsert(segment("a", "Hello team.", final: true))
        transcript.upsert(segment("b", "We decided to cancel everything", start: 1))
        transcript.finalize()
        let notes = try ScribeExtractiveNotesGenerator(clock: { Date(timeIntervalSince1970: 0) }).generate(from: transcript)
        #expect(notes.decisions.isEmpty)
        #expect(notes.summary == "Hello team.")
    }

    @Test func otherSessionSegmentsAreRejected() {
        var transcript = ScribeTranscript(session: session)
        let foreign = segment("x", "nope", session: ScribeSessionID())
        #expect(transcript.upsert(foreign) == .rejectedSession)
        #expect(transcript.segments.isEmpty)
    }

    @Test func invalidTimesAreRejected() {
        var transcript = ScribeTranscript(session: session)
        #expect(transcript.upsert(segment("a", "x", start: 5, end: 4)) == .rejectedInvalid)
        #expect(transcript.upsert(segment("b", "x", start: .nan, end: 1)) == .rejectedInvalid)
        #expect(transcript.upsert(segment("c", "x", start: 0, end: .infinity)) == .rejectedInvalid)
        #expect(transcript.segments.isEmpty)
    }

    @Test func speakerMappingFollowsSource() {
        #expect(ScribeSpeaker.forSource(.microphone) == .you)
        #expect(ScribeSpeaker.forSource(.microphone, label: "Sam") == .you)
        #expect(ScribeSpeaker.forSource(.system, label: "Sam") == .participant("Sam"))
        #expect(ScribeSpeaker.forSource(.system, label: "  ") == .unknown)
        #expect(ScribeSpeaker.forSource(.system) == .unknown)
        #expect(ScribeSpeaker.you.displayName == "You")
        #expect(ScribeSpeaker.participant("Sam").displayName == "Sam")
        #expect(ScribeSpeaker.unknown.displayName == "Unknown")
    }

    @Test func exportsToMeetingTranscriptWithFinalSegmentsOnlyByDefault() {
        var transcript = ScribeTranscript(session: session)
        transcript.upsert(segment("a", "hello", start: 5, speaker: .you, final: true))
        transcript.upsert(segment("b", "hi there", start: 1, speaker: .participant("Sam"), final: true))
        transcript.upsert(segment("c", "typing", start: 8, speaker: .unknown))

        let exported = transcript.meetingTranscript()
        #expect(exported == MeetingTranscript(lines: [
            MeetingTranscriptLine(start: 1, speaker: "Sam", text: "hi there"),
            MeetingTranscriptLine(start: 5, speaker: "You", text: "hello")
        ]))
        #expect(transcript.meetingTranscript(includeProvisional: true).lines.count == 3)
        #expect(exported.text().contains("Sam: hi there"))
    }
}

// MARK: - 7 Notes

@Suite("Scribe notes")
struct ScribeNotesTests {
    private let session = ScribeSessionID()
    private let fixedDate = Date(timeIntervalSince1970: 1_000)

    private func transcript(_ lines: [(String, Bool)]) -> ScribeTranscript {
        var transcript = ScribeTranscript(session: session)
        for (index, line) in lines.enumerated() {
            transcript.upsert(ScribeTranscriptSegment(
                id: "s\(index)",
                session: session,
                speaker: .unknown,
                start: TimeInterval(index),
                end: TimeInterval(index) + 1,
                text: line.0,
                isFinal: line.1
            ))
        }
        return transcript
    }

    private func generator(summaryLines: Int = 2) -> ScribeExtractiveNotesGenerator {
        let date = fixedDate
        return ScribeExtractiveNotesGenerator(summaryLineCount: summaryLines, clock: { date })
    }

    @Test func extractiveGenerationFindsDecisionsActionsAndSummary() throws {
        let source = transcript([
            ("Welcome everyone to the sync.", true),
            ("We decided to ship on Friday.", true),
            ("Alex will send the report.", true),
            ("Still talking about lunch", false),
            ("Thanks all.", true)
        ])
        let notes = try generator().generate(from: source)
        #expect(notes.method == .extractive)
        #expect(notes.generatedAt == fixedDate)
        #expect(notes.summary == "Welcome everyone to the sync. We decided to ship on Friday.")
        #expect(notes.decisions == ["We decided to ship on Friday."])
        #expect(notes.actionItems == [ScribeActionItem(text: "Alex will send the report.", done: false)])
        #expect(!notes.isEmpty)
    }

    @Test func lineWithDecisionAndActionKeywordsYieldsBoth() throws {
        let line = "We agreed Alex will send the report."
        let notes = try generator().generate(from: transcript([(line, true)]))
        #expect(notes.decisions == [line])
        #expect(notes.actionItems == [ScribeActionItem(text: line, done: false)])
    }

    @Test func provisionalLinesAreIgnored() throws {
        let source = transcript([("We agreed on the plan", false)])
        let notes = try generator().generate(from: source)
        #expect(notes.isEmpty)
    }

    @Test func emptyTranscriptGivesHonestEmptyNotes() throws {
        let notes = try generator().generate(from: ScribeTranscript(session: session))
        #expect(notes.summary.isEmpty)
        #expect(notes.decisions.isEmpty)
        #expect(notes.actionItems.isEmpty)
        #expect(notes.isEmpty)
    }

    @Test func keywordsMatchWholeWordsOnly() throws {
        let source = transcript([("He seemed unwilling and disagreeable.", true)])
        let notes = try generator(summaryLines: 0).generate(from: source)
        #expect(notes.decisions.isEmpty)
        #expect(notes.actionItems.isEmpty)
        #expect(notes.summary.isEmpty)
    }

    @Test func privateNotesSurviveRegenerationByteForByte() throws {
        let privateText = "  my secret\n\tnotes — keep exactly  "
        var notes = ScribeMeetingNotes(privateNotes: privateText)

        let first = try generator().generate(from: transcript([("Alex will send the report.", true)]))
        notes = ScribeNotes.merge(generated: first, into: notes)
        #expect(notes.privateNotes == privateText)
        #expect(Array(notes.privateNotes.utf8) == Array(privateText.utf8))

        let second = try generator().generate(from: transcript([("We decided to wait.", true)]))
        notes = ScribeNotes.merge(generated: second, into: notes)
        #expect(notes.privateNotes == privateText)
        #expect(notes.decisions == ["We decided to wait."])
        #expect(notes.generatedAt == fixedDate)
        #expect(notes.method == .extractive)
    }

    @Test func regenerationPreservesDoneFlagForUnchangedActionItem() throws {
        let generated = try generator().generate(from: transcript([("Alex will send the report.", true)]))
        var existing = ScribeMeetingNotes(actionItems: [
            ScribeActionItem(text: "Alex will send the report.", done: true),
            ScribeActionItem(text: "Removed item", done: true)
        ])
        existing = ScribeNotes.merge(generated: generated, into: existing)
        #expect(existing.actionItems == [ScribeActionItem(text: "Alex will send the report.", done: true)])
    }

    @Test func mergingEmptyGeneratedNotesStillKeepsPrivateNotes() throws {
        let generated = try generator().generate(from: ScribeTranscript(session: session))
        let merged = ScribeNotes.merge(generated: generated, into: ScribeMeetingNotes(summary: "old", privateNotes: "mine"))
        #expect(merged.privateNotes == "mine")
        #expect(merged.summary.isEmpty)
    }
}

// MARK: - 8 Call prompt

@Suite("Scribe call prompt")
struct ScribeCallPromptTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func slot(_ id: String, offset: TimeInterval, end: Date? = nil) -> ScribeCalendarSlot {
        ScribeCalendarSlot(id: id, title: "Meeting \(id)", start: now.addingTimeInterval(offset), end: end)
    }

    private func decide(
        _ slots: [ScribeCalendarSlot] = [],
        app: ScribeCallApp? = nil,
        recording: Bool = false,
        dismissed: Set<String> = [],
        dismissedApps: Set<ScribeCallApp> = []
    ) -> ScribePromptDecision {
        ScribeCallPrompt.decide(
            now: now,
            upcoming: slots,
            activeCallApp: app,
            isRecording: recording,
            dismissedIDs: dismissed,
            dismissedCallApps: dismissedApps
        )
    }

    @Test func upcomingWindowEdges() {
        let startsIn120 = slot("a", offset: 120)
        let startsIn121 = slot("b", offset: 121)
        let startedAgo300 = slot("c", offset: -300)
        let startedAgo301 = slot("d", offset: -301)
        let startsNow = slot("e", offset: 0)

        #expect(decide([startsIn120]) == .upcoming(startsIn120))
        #expect(decide([startsIn121]) == .none)
        #expect(decide([startedAgo300]) == .upcoming(startedAgo300))
        #expect(decide([startedAgo301]) == .none)
        #expect(decide([startsNow]) == .upcoming(startsNow))
    }

    @Test func dismissedSlotIsSkipped() {
        let first = slot("a", offset: 30)
        let second = slot("b", offset: 90)
        #expect(decide([first], dismissed: ["a"]) == .none)
        #expect(decide([first, second], dismissed: ["a"]) == .upcoming(second))
    }

    @Test func closestEligibleSlotWins() {
        let near = slot("near", offset: -10)
        let far = slot("far", offset: 100)
        #expect(decide([far, near]) == .upcoming(near))
    }

    @Test func endedSlotIsNotOffered() {
        let ended = slot("a", offset: -100, end: now.addingTimeInterval(-1))
        let openEnded = slot("b", offset: -100, end: now.addingTimeInterval(60))
        #expect(decide([ended]) == .none)
        #expect(decide([openEnded]) == .upcoming(openEnded))
    }

    @Test func recordingSuppressesEveryPrompt() {
        #expect(decide([slot("a", offset: 10)], app: .zoom, recording: true) == .none)
        #expect(decide(app: .teams, recording: true) == .none)
    }

    @Test func callDetectedWithoutSlot() {
        #expect(decide(app: .zoom) == .callDetected(.zoom))
        #expect(decide(app: .other("Webex")) == .callDetected(.other("Webex")))
        #expect(decide() == .none)
    }

    @Test func dismissedCallAppIsNotOfferedAgain() {
        #expect(decide(app: .meet, dismissedApps: [.meet]) == .none)
        #expect(decide(app: .meet, dismissedApps: [.zoom]) == .callDetected(.meet))
    }

    @Test func upcomingSlotWinsOverBareCallDetection() {
        let upcoming = slot("a", offset: 60)
        #expect(decide([upcoming], app: .teams) == .upcoming(upcoming))
        #expect(decide([upcoming], app: .teams, dismissed: ["a"]) == .callDetected(.teams))
    }
}
