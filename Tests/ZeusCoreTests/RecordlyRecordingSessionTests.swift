import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

// Synthetic only: the mock port never touches ScreenCaptureKit, a writer, or any capture device.
// Every wait is a continuation or a beacon, never a sleep.

private enum TestSetupError: Error { case unresolved }

private let display17 = RecordlySourceSelection.SelectionIntent.display(id: 17)
private let window2142 = RecordlySourceSelection.SelectionIntent.window(number: 21, identityToken: "21:42")

private func resolvedSource(_ intent: RecordlySourceSelection.SelectionIntent) throws -> RecordlySourceSelection.ResolvedSource {
    let catalog = RecordlySourceSelection.CatalogSnapshot(
        displays: [.init(id: 17, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))],
        windows: [.init(number: 21, identityToken: "21:42", isPresent: true, title: "Notes", ownerName: "Notes")]
    )
    guard case .ready(let value) = RecordlySourceSelection.resolve(intent: intent, in: catalog, permission: .granted) else {
        throw TestSetupError.unresolved
    }
    return value
}

private func request(_ intent: RecordlySourceSelection.SelectionIntent) -> RecordlyStartRequest {
    RecordlyStartRequest(
        intent: intent,
        systemAudio: false,
        excludeZeusWindows: true,
        directory: URL(fileURLWithPath: "/tmp/zeus-recordly-session-tests", isDirectory: true)
    )
}

private let sampleOutput = RecordlyRecordingOutput(url: URL(fileURLWithPath: "/tmp/zeus-recordly-session-tests/a.mp4"), cursorSamples: [])

/// Counts events and lets a test wait for the nth one without sleeping.
@MainActor
private final class Beacon {
    private(set) var count = 0
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func hit() {
        count += 1
        let ready = waiters.filter { $0.target <= count }
        waiters.removeAll { $0.target <= count }
        for waiter in ready { waiter.continuation.resume() }
    }

    func wait(for target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { continuation in
            waiters.append((target, continuation))
        }
    }
}

@MainActor
private final class MockPort: RecordlyRecordingPort {
    let beginBeacon = Beacon()
    let cancelBeacon = Beacon()
    let endBeacon = Beacon()
    var holdCancel = false

    private(set) var begun: [(request: RecordlyStartRequest, attempt: RecordlyRecordingAttempt)] = []
    private(set) var cancelled: [RecordlyRecordingAttempt] = []
    private(set) var ended: [RecordlyRecordingAttempt] = []
    private(set) var stopHooks: [@Sendable (RecordlyRecordingAttempt, String) -> Void] = []

    private var beginContinuations: [CheckedContinuation<RecordlySourceSelection.ResolvedSource, Error>] = []
    private var cancelContinuations: [CheckedContinuation<Void, Never>] = []
    private var endContinuations: [CheckedContinuation<RecordlyRecordingOutput, Error>] = []

    func begin(
        request: RecordlyStartRequest,
        attempt: RecordlyRecordingAttempt,
        onUnexpectedStop: @escaping @Sendable (RecordlyRecordingAttempt, String) -> Void
    ) async throws -> RecordlySourceSelection.ResolvedSource {
        begun.append((request, attempt))
        stopHooks.append(onUnexpectedStop)
        return try await withCheckedThrowingContinuation { continuation in
            beginContinuations.append(continuation)
            beginBeacon.hit()
        }
    }

    func cancel(attempt: RecordlyRecordingAttempt) async {
        cancelled.append(attempt)
        guard holdCancel else {
            cancelBeacon.hit()
            return
        }
        await withCheckedContinuation { continuation in
            cancelContinuations.append(continuation)
            cancelBeacon.hit()
        }
    }

    func end(attempt: RecordlyRecordingAttempt) async throws -> RecordlyRecordingOutput {
        ended.append(attempt)
        return try await withCheckedThrowingContinuation { continuation in
            endContinuations.append(continuation)
            endBeacon.hit()
        }
    }

    func completeBegin(_ index: Int, _ result: Result<RecordlySourceSelection.ResolvedSource, Error>) {
        beginContinuations[index].resume(with: result)
    }

    func releaseCancel(_ index: Int) {
        cancelContinuations[index].resume()
    }

    func completeEnd(_ index: Int, _ result: Result<RecordlyRecordingOutput, Error>) {
        endContinuations[index].resume(with: result)
    }
}

/// A watchdog sleep that returns only when the test fires it, so no real timer is involved.
@MainActor
private final class WatchdogGate {
    let armed = Beacon()
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    func sleep() async {
        await withCheckedContinuation { continuation in
            sleepers.append(continuation)
            armed.hit()
        }
    }

    func fire() {
        let ready = sleepers
        sleepers = []
        for sleeper in ready { sleeper.resume() }
    }
}

@MainActor
@Suite("Recordly recording session")
struct RecordlyRecordingSessionTests {
    private func makeSession() -> (RecordlyRecordingSession, MockPort) {
        let port = MockPort()
        return (RecordlyRecordingSession(port: port), port)
    }

    /// Starts and drives to `recording`, returning the attempt.
    private func startRecording(
        _ session: RecordlyRecordingSession,
        _ port: MockPort,
        intent: RecordlySourceSelection.SelectionIntent = display17
    ) async throws -> RecordlyRecordingAttempt {
        let count = port.begun.count
        let task = Task { await session.start(request(intent)) }
        await port.beginBeacon.wait(for: count + 1)
        port.completeBegin(count, .success(try resolvedSource(intent)))
        _ = await task.value
        guard case .recording(let attempt) = session.phase else { throw TestSetupError.unresolved }
        return attempt
    }

    @Test func startIsPendingUntilTheEngineAcknowledges() async throws {
        let (session, port) = makeSession()
        let task = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        guard case .starting = session.phase else {
            Issue.record("expected starting, got \(session.phase)")
            return
        }
        #expect(port.begun.count == 1)
        #expect(port.begun[0].request.intent == display17)

        let resolved = try resolvedSource(display17)
        port.completeBegin(0, .success(resolved))
        let outcome = await task.value
        guard case .recording(let attempt) = session.phase else {
            Issue.record("expected recording, got \(session.phase)")
            return
        }
        #expect(outcome == .started(attempt, resolved))
        #expect(resolved.displayID == 17)
    }

    @Test func windowIdentityReachesThePortExactlyOnce() async throws {
        let (session, port) = makeSession()
        let attempt = try await startRecording(session, port, intent: window2142)
        #expect(port.begun.count == 1)
        #expect(port.begun[0].request.intent == window2142)
        #expect(port.begun[0].attempt == attempt)
    }

    @Test func startFailureWaitsInFailedUntilClearedThenRetries() async throws {
        let (session, port) = makeSession()
        let task = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        port.completeBegin(0, .failure(RecordlyPortFailure.engine("writer broke")))
        let outcome = await task.value
        #expect(outcome == .failed(.engine("writer broke")))
        #expect(session.phase == .failed("writer broke"))

        // Failed is not idle: a retry is refused until the failure is dismissed.
        if case .rejected = await session.start(request(display17)) {} else { Issue.record("retry must be rejected while failed") }
        #expect(port.begun.count == 1)

        #expect(session.clearFailure())
        #expect(session.phase == .idle)
        _ = try await startRecording(session, port)
        #expect(port.begun.count == 2)
    }

    @Test func denialAndLostSourceReturnToIdleWithTheirReason() async throws {
        let (session, port) = makeSession()
        let denied = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        port.completeBegin(0, .failure(RecordlyPortFailure.permissionDenied("off")))
        #expect(await denied.value == .failed(.permissionDenied("off")))
        #expect(session.phase == .idle)

        let lost = Task { await session.start(request(window2142)) }
        await port.beginBeacon.wait(for: 2)
        port.completeBegin(1, .failure(RecordlyPortFailure.noSource("gone")))
        #expect(await lost.value == .failed(.noSource("gone")))
        #expect(session.phase == .idle)
    }

    @Test func cancelDuringStartStaysStoppingUntilTeardownIsAcknowledged() async throws {
        let (session, port) = makeSession()
        port.holdCancel = true
        let start = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        guard case .starting(let attempt) = session.phase else {
            Issue.record("expected starting")
            return
        }

        let cancel = Task { await session.cancel() }
        await port.cancelBeacon.wait(for: 1)
        #expect(session.phase == .stopping(attempt))
        #expect(port.cancelled == [attempt])

        // The pending start returns (cancelled), but the port has not acknowledged yet.
        port.completeBegin(0, .failure(RecordlyPortFailure.cancelled))
        #expect(await start.value == .cancelled)
        #expect(session.phase == .stopping(attempt))
        if case .rejected = await session.start(request(display17)) {} else { Issue.record("start must be rejected while stopping") }

        port.releaseCancel(0)
        await cancel.value
        #expect(session.phase == .idle)
    }

    @Test func lateSuccessAfterCancelIsUnwoundNotPublished() async throws {
        let (session, port) = makeSession()
        let start = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        guard case .starting(let attempt) = session.phase else {
            Issue.record("expected starting")
            return
        }
        await session.cancel()
        // cancel() returned (port acknowledged) but the start has not, so the session is still stopping.
        #expect(session.phase == .stopping(attempt))

        port.completeBegin(0, .success(try resolvedSource(display17)))
        #expect(await start.value == .cancelled)
        #expect(session.phase == .idle)
        // Once for the cancel, once more to unwind the late success.
        #expect(port.cancelled == [attempt, attempt])
    }

    @Test func stopDuringStartupCancels() async throws {
        let (session, port) = makeSession()
        let start = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        let outcome = await session.stop()
        #expect(outcome == .ignored)
        port.completeBegin(0, .failure(RecordlyPortFailure.cancelled))
        #expect(await start.value == .cancelled)
        #expect(session.phase == .idle)
        #expect(port.ended.isEmpty)
    }

    @Test func staleCallbackFromAnEarlierAttemptIsIgnored() async throws {
        let (session, port) = makeSession()
        let first = try await startRecording(session, port)
        let stop = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        port.completeEnd(0, .success(sampleOutput))
        _ = await stop.value

        let second = try await startRecording(session, port)
        #expect(second != first)

        await session.engineFailed(attempt: first, message: "old stream died")
        #expect(session.phase == .recording(second))
        #expect(port.cancelled.isEmpty)
    }

    @Test func unexpectedStopKeepsTheRecordingAndReportsIt() async throws {
        let (session, port) = makeSession()
        var recovered: [(RecordlyRecordingOutput, String)] = []
        session.onRecovered = { _, output, message in recovered.append((output, message)) }
        let attempt = try await startRecording(session, port)

        let failure = Task { await session.engineFailed(attempt: attempt, message: "stream stopped") }
        await port.endBeacon.wait(for: 1)
        #expect(session.phase == .stopping(attempt))
        // The recording is finalized, never cancelled; nothing can slip in while that is pending.
        #expect(port.cancelled.isEmpty)
        if case .rejected = await session.start(request(display17)) {} else { Issue.record("start must be rejected while stopping") }
        #expect(!session.clearFailure())
        #expect(!session.reset())
        #expect(await session.stop() == .ignored)

        port.completeEnd(0, .success(sampleOutput))
        await failure.value
        #expect(session.phase == .idle)
        #expect(recovered.count == 1)
        #expect(recovered.first?.0 == sampleOutput)
        #expect(recovered.first?.1 == "stream stopped")
        _ = try await startRecording(session, port)
    }

    @Test func unexpectedStopThatCannotBeSavedFailsWithBothReasons() async throws {
        let (session, port) = makeSession()
        var recovered = 0
        session.onRecovered = { _, _, _ in recovered += 1 }
        let attempt = try await startRecording(session, port)
        let failure = Task { await session.engineFailed(attempt: attempt, message: "stream stopped") }
        await port.endBeacon.wait(for: 1)
        port.completeEnd(0, .failure(RecordlyPortFailure.engine("disk full")))
        await failure.value
        #expect(recovered == 0)
        #expect(session.phase == .failed("stream stopped The recording could not be saved: disk full"))
        #expect(session.reset())
    }

    @Test func engineFailureDuringStartupTearsDownThenFails() async throws {
        let (session, port) = makeSession()
        port.holdCancel = true
        let start = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        guard case .starting(let attempt) = session.phase else {
            Issue.record("expected starting")
            return
        }
        let failure = Task { await session.engineFailed(attempt: attempt, message: "stream died") }
        await port.cancelBeacon.wait(for: 1)
        #expect(session.phase == .stopping(attempt))
        port.completeBegin(0, .failure(RecordlyPortFailure.cancelled))
        port.releaseCancel(0)
        await failure.value
        #expect(await start.value == .failed(.engine("stream died")))
        #expect(session.phase == .failed("stream died"))
    }

    @Test func duplicateStartWhileStartingIsRejected() async throws {
        let (session, port) = makeSession()
        let start = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        if case .rejected = await session.start(request(display17)) {} else { Issue.record("duplicate start must be rejected") }
        #expect(port.begun.count == 1)
        port.completeBegin(0, .success(try resolvedSource(display17)))
        _ = await start.value
        if case .recording = session.phase {} else { Issue.record("expected recording") }
    }

    @Test func cancelWithAReasonEndsInFailedAfterTeardown() async throws {
        let (session, port) = makeSession()
        let start = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        guard case .starting(let attempt) = session.phase else {
            Issue.record("expected starting")
            return
        }
        await session.cancel(failing: "took too long")
        #expect(session.phase == .stopping(attempt))
        port.completeBegin(0, .failure(RecordlyPortFailure.cancelled))
        #expect(await start.value == .failed(.engine("took too long")))
        #expect(session.phase == .failed("took too long"))
        #expect(session.clearFailure())
        #expect(session.phase == .idle)
    }

    @Test func aCancelThatNeverReturnsTimesOutToARecoverableFailure() async throws {
        let port = MockPort()
        port.holdCancel = true
        let gate = WatchdogGate()
        let session = RecordlyRecordingSession(port: port, sleeper: { _ in await gate.sleep() })
        let failed = Beacon()
        session.onPhaseChange = { if case .failed = $0 { failed.hit() } }
        let start = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 1)
        let cancel = Task { await session.cancel(failing: "took too long") }
        await port.cancelBeacon.wait(for: 1)
        guard case .stopping = session.phase else {
            Issue.record("expected stopping")
            return
        }
        // Neither the start nor the port's cancel returns; the watchdog publishes the failure.
        await gate.armed.wait(for: 1)
        gate.fire()
        await failed.wait(for: 1)
        #expect(session.phase == .failed("took too long"))
        #expect(session.clearFailure())
        #expect(session.phase == .idle)

        // Late returns from the abandoned attempt change nothing, and a late success is still unwound.
        port.holdCancel = false
        port.completeBegin(0, .success(try resolvedSource(display17)))
        #expect(await start.value == .cancelled)
        port.releaseCancel(0)
        await cancel.value
        #expect(session.phase == .idle)
        #expect(port.cancelled.count == 2)
    }

    @Test func aStopThatNeverReturnsTimesOutToARecoverableFailure() async throws {
        let port = MockPort()
        let gate = WatchdogGate()
        let session = RecordlyRecordingSession(port: port, sleeper: { _ in await gate.sleep() })
        let failed = Beacon()
        session.onPhaseChange = { if case .failed = $0 { failed.hit() } }
        var recovered: [(RecordlyRecordingOutput, String)] = []
        session.onRecovered = { _, output, message in recovered.append((output, message)) }
        _ = try await startRecording(session, port)
        let stop = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        await gate.armed.wait(for: 1)
        gate.fire()
        await failed.wait(for: 1)
        #expect(session.phase == .failed(RecordlyRecordingSession.stuckMessage))
        #expect(session.reset())
        port.completeEnd(0, .success(sampleOutput))
        // The late result is not a Stop result, but it is handed over once instead of being lost.
        #expect(await stop.value == .ignored)
        #expect(session.phase == .idle)
        #expect(recovered.count == 1)
        #expect(recovered.first?.0 == sampleOutput)
        #expect(recovered.first?.1 == RecordlyRecordingSession.lateFinishMessage)
    }

    @Test func aLateFinishWhileStillFailedClearsTheStuckFailureAndIsDeliveredOnce() async throws {
        let port = MockPort()
        let gate = WatchdogGate()
        let session = RecordlyRecordingSession(port: port, sleeper: { _ in await gate.sleep() })
        let failed = Beacon()
        session.onPhaseChange = { if case .failed = $0 { failed.hit() } }
        var recovered = 0
        session.onRecovered = { _, _, _ in recovered += 1 }
        _ = try await startRecording(session, port)
        let stop = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        await gate.armed.wait(for: 1)
        gate.fire()
        await failed.wait(for: 1)
        port.completeEnd(0, .success(sampleOutput))
        #expect(await stop.value == .ignored)
        #expect(session.phase == .idle)
        #expect(recovered == 1)
        #expect(await session.stop() == .ignored)
        #expect(recovered == 1)
    }

    @Test func aLateFinishAfterAFailedRetryClearsTheRetryFailureAndIsDelivered() async throws {
        let port = MockPort()
        let gate = WatchdogGate()
        let session = RecordlyRecordingSession(port: port, sleeper: { _ in await gate.sleep() })
        let failed = Beacon()
        session.onPhaseChange = { if case .failed = $0 { failed.hit() } }
        var recovered: [(RecordlyRecordingAttempt, RecordlyRecordingOutput, String)] = []
        session.onRecovered = { attempt, output, message in recovered.append((attempt, output, message)) }
        let first = try await startRecording(session, port)
        let stop = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        await gate.armed.wait(for: 1)
        gate.fire()
        await failed.wait(for: 1)
        #expect(session.clearFailure())

        // The suggested retry fails because the first attempt still owns the engine.
        let retry = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 2)
        port.completeBegin(1, .failure(RecordlyPortFailure.engine("Another recording is already starting or running.")))
        _ = await retry.value
        #expect(session.phase == .failed("Another recording is already starting or running."))

        port.completeEnd(0, .success(sampleOutput))
        #expect(await stop.value == .ignored)
        #expect(session.phase == .idle)
        #expect(recovered.count == 1)
        #expect(recovered.first?.0 == first)
        #expect(recovered.first?.1 == sampleOutput)
        #expect(recovered.first?.2 == RecordlyRecordingSession.lateFinishMessage)
    }

    @Test func aLateFinishDuringANewStartIsKeptWithItsAttemptAndLeavesTheNewPhaseAlone() async throws {
        let port = MockPort()
        let gate = WatchdogGate()
        let session = RecordlyRecordingSession(port: port, sleeper: { _ in await gate.sleep() })
        let failed = Beacon()
        session.onPhaseChange = { if case .failed = $0 { failed.hit() } }
        var recovered: [(RecordlyRecordingAttempt, RecordlyRecordingOutput)] = []
        session.onRecovered = { attempt, output, _ in recovered.append((attempt, output)) }
        let first = try await startRecording(session, port)
        let stop = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        await gate.armed.wait(for: 1)
        gate.fire()
        await failed.wait(for: 1)
        #expect(session.clearFailure())

        let next = Task { await session.start(request(display17)) }
        await port.beginBeacon.wait(for: 2)
        guard case .starting(let second) = session.phase else {
            Issue.record("expected starting")
            return
        }
        port.completeEnd(0, .success(sampleOutput))
        #expect(await stop.value == .ignored)
        // Reported with its own attempt, and the newer start is untouched.
        #expect(recovered.count == 1)
        #expect(recovered.first?.0 == first)
        #expect(recovered.first?.0 != second)
        #expect(recovered.first?.1 == sampleOutput)
        #expect(session.phase == .starting(second))

        port.completeBegin(1, .success(try resolvedSource(display17)))
        _ = await next.value
        #expect(session.phase == .recording(second))
        #expect(recovered.count == 1)
    }

    @Test func aLateFinishFailureAfterTheTimeoutDeliversNothing() async throws {
        let port = MockPort()
        let gate = WatchdogGate()
        let session = RecordlyRecordingSession(port: port, sleeper: { _ in await gate.sleep() })
        let failed = Beacon()
        session.onPhaseChange = { if case .failed = $0 { failed.hit() } }
        var recovered = 0
        session.onRecovered = { _, _, _ in recovered += 1 }
        _ = try await startRecording(session, port)
        let stop = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        await gate.armed.wait(for: 1)
        gate.fire()
        await failed.wait(for: 1)
        port.completeEnd(0, .failure(RecordlyPortFailure.engine("disk full")))
        #expect(await stop.value == .ignored)
        #expect(recovered == 0)
        #expect(session.phase == .failed(RecordlyRecordingSession.stuckMessage))
    }

    @Test func engineHookReachesTheSessionWithItsAttempt() async throws {
        let (session, port) = makeSession()
        var recovered = 0
        session.onRecovered = { _, _, _ in recovered += 1 }
        let attempt = try await startRecording(session, port)
        let idle = Beacon()
        session.onPhaseChange = { if $0 == .idle { idle.hit() } }
        port.stopHooks[0](attempt, "hook failure")
        // The hook hops to the main actor; the port's end beacon proves the session handled it.
        await port.endBeacon.wait(for: 1)
        #expect(port.ended == [attempt])
        port.completeEnd(0, .success(sampleOutput))
        await idle.wait(for: 1)
        #expect(session.phase == .idle)
        #expect(recovered == 1)
    }

    @Test func duplicateStopIsANoOpAndTheResultIsDeliveredOnce() async throws {
        let (session, port) = makeSession()
        let attempt = try await startRecording(session, port)

        let first = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        #expect(session.phase == .stopping(attempt))

        #expect(await session.stop() == .ignored)
        #expect(port.ended == [attempt])

        port.completeEnd(0, .success(sampleOutput))
        #expect(await first.value == .finished(sampleOutput))
        #expect(session.phase == .idle)

        // A third Stop after the result was delivered has nothing left to deliver.
        #expect(await session.stop() == .ignored)
        #expect(port.ended.count == 1)
    }

    @Test func stopFailureSurfacesTheErrorAndHoldsFailed() async throws {
        let (session, port) = makeSession()
        _ = try await startRecording(session, port)
        let stop = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        port.completeEnd(0, .failure(RecordlyPortFailure.engine("disk full")))
        #expect(await stop.value == .failed("disk full"))
        #expect(session.phase == .failed("disk full"))
        #expect(session.failureMessage == "disk full")
    }

    @Test func phaseChangesAreReportedInOrder() async throws {
        let (session, port) = makeSession()
        var seen: [RecordlyRecordingSession.Phase] = []
        session.onPhaseChange = { seen.append($0) }
        let attempt = try await startRecording(session, port)
        let stop = Task { await session.stop() }
        await port.endBeacon.wait(for: 1)
        port.completeEnd(0, .success(sampleOutput))
        _ = await stop.value
        #expect(seen == [.starting(attempt), .recording(attempt), .stopping(attempt), .idle])
    }

    // MARK: Layout

    @Test func recordFooterStaysInsideThePageForAnyNumberOfSources() {
        #expect(Double(RecordlyPageLayout.innerHeight) == 208)
        #expect(Double(RecordlyPageLayout.scrollMaxHeight) == 162)
        for rows in [0, 1, 3, 10, 50, 500] {
            for rowHeight in [RecordlyPageLayout.displayRowHeight, RecordlyPageLayout.windowRowHeight] {
                let content = RecordlyPageLayout.estimatedContentHeight(rows: rows, rowHeight: rowHeight)
                #expect(RecordlyPageLayout.stackHeight(contentHeight: content) <= RecordlyPageLayout.innerHeight)
            }
        }
        // The unbounded stack (the old nested 86 pt list plus the rest) did overflow; the bounded one never does.
        #expect(RecordlyPageLayout.stackHeight(contentHeight: .greatestFiniteMagnitude) == RecordlyPageLayout.innerHeight)
    }

    @Test func sourceListKeepsAtLeastFourRowsVisibleWhileRecordStaysPinned() {
        let fourRows = RecordlyPageLayout.estimatedContentHeight(rows: RecordlyPageLayout.minVisibleDisplayRows, rowHeight: RecordlyPageLayout.displayRowHeight)
            - RecordlyPageLayout.headerHeight
        #expect(RecordlyPageLayout.visibleRowsHeight >= fourRows)
        // Scroll area, one gap, footer: nothing else shares the column, so the footer ends at the inner height.
        #expect(RecordlyPageLayout.scrollMaxHeight + RecordlyPageLayout.footerGap + RecordlyPageLayout.footerHeight == RecordlyPageLayout.innerHeight)
    }

    @Test func recordButtonIsOnTheOpenShapesHitArea() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let size = GlanceTopBar.panelSize(home: false)
        let footerBottom = GlanceTopBar.cardTop + RecordlyPageLayout.tilePadding + RecordlyPageLayout.innerHeight
        let footerCenter = footerBottom - RecordlyPageLayout.footerHeight / 2
        // The footer's bottom edge is inside the page, above the panel's bottom gap.
        #expect(footerBottom <= GlanceTopBar.cardTop + GlanceTopBar.tallPageHeight)
        for dx in [-300, -100, 0, 100, 300] as [CGFloat] {
            let point = CGPoint(x: screen.midX + dx, y: screen.maxY - footerCenter)
            #expect(GlanceTopBar.openShapeContains(point, screen: screen, size: size))
        }
        // A control placed where the old stack overflowed (about 32 pt below the page) is not hittable.
        let overflow = CGPoint(x: screen.midX, y: screen.maxY - (GlanceTopBar.cardTop + GlanceTopBar.tallPageHeight + 32))
        #expect(!GlanceTopBar.openShapeContains(overflow, screen: screen, size: size))
    }

    // MARK: Discard

    @Test func discardRemovesTheRecordAndOnlyRemovesMediaWhenAsked() throws {
        let fileManager = FileManager.default
        // Darwin realpath keeps "/private/var/..."; Foundation's resolvingSymlinksInPath leaves the "/var" symlink.
        let tmp = NSTemporaryDirectory()
        var canonical = tmp
        if let resolved = realpath(tmp, nil) {
            canonical = String(cString: resolved)
            free(resolved)
        }
        let base = URL(fileURLWithPath: canonical, isDirectory: true)
            .appendingPathComponent("zeus-discard-\(UUID().uuidString)", isDirectory: true)
        let checkpoints = base.appendingPathComponent(RecordlyCheckpointStore.checkpointDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: checkpoints, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let record = checkpoints.appendingPathComponent(RecordlyCheckpointStore.recordName)
        let media = base.appendingPathComponent("capture-1.mp4")
        try Data("{}".utf8).write(to: record)
        try Data([1, 2, 3]).write(to: media)
        let store = RecordlyCheckpointStore(mediaRoot: base.path, checkpointRoot: checkpoints.path)

        try RecordlyDiscard.removeCheckpointRecord(store)
        #expect(!fileManager.fileExists(atPath: record.path))
        #expect(fileManager.fileExists(atPath: media.path))
        // Already gone counts as removed.
        try RecordlyDiscard.removeCheckpointRecord(store)

        #expect(throws: RecordlyCheckpointStore.StoreError.mediaOutsideTrustedRoot) {
            try RecordlyDiscard.removeMedia(store, rawPath: "/etc/hosts")
        }
        #expect(throws: RecordlyCheckpointStore.StoreError.mediaOutsideTrustedRoot) {
            try RecordlyDiscard.removeMedia(store, rawPath: record.path)
        }
        #expect(fileManager.fileExists(atPath: media.path))

        try RecordlyDiscard.removeMedia(store, rawPath: media.path)
        #expect(!fileManager.fileExists(atPath: media.path))
    }
}
