import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Automated native-controller scenarios. Every provider is inert; no device, permission prompt or UI click.
@MainActor @Suite("Scribe lifecycle scenarios")
struct ScribeLifecycleScenarioTests {
    private final class Clock {
        var time: TimeInterval = 100
    }

    private final class Capture: ScribeCaptureProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var callback: (@Sendable (ScribeCaptureEvent) -> Void)?
        private var current: ScribeSessionID?
        private var stops = 0
        var stopCount: Int { lock.withLock { stops } }
        func start(session: ScribeSessionID, frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
                   events: @escaping @Sendable (ScribeCaptureEvent) -> Void) {
            lock.withLock { current = session; callback = events }
        }
        func stop(session: ScribeSessionID) { lock.withLock { if current == session { stops += 1 } } }
        func send(_ event: ScribeCaptureEvent) { lock.withLock { callback }?(event) }
    }

    private enum Failure: Error { case eventTimedOut }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw Failure.eventTimedOut
    }

    private func start(_ controller: ScribeController, provider: Capture) async throws -> ScribeSessionID {
        controller.start()
        let id = try #require(controller.phase.sessionID)
        provider.send(.captureAcknowledged(id))
        try await waitUntil { controller.isRecording }
        return id
    }

    @Test func manualCountdownKeepAndRepeatedTicksStopExactlyOnceAfterNineSeconds() async throws {
        let clock = Clock(), capture = Capture()
        let controller = ScribeController(provider: capture, monotonicClock: { clock.time })
        let id = try await start(controller, provider: capture)
        defer { controller.cancel() }
        controller.requestEnd()
        clock.time += 8.9
        controller.tickClock()
        #expect(capture.stopCount == 0)
        controller.keepRecording()
        clock.time += 20
        controller.tickClock()
        #expect(capture.stopCount == 0)
        #expect(controller.phase == .recording(id, since: 100))
        controller.requestEnd()
        clock.time += 9
        controller.tickClock()
        controller.tickClock()
        controller.confirmEnd()
        controller.keepRecording()
        #expect(capture.stopCount == 1)
        #expect(controller.endStopRequested)
        #expect(controller.phase.isActive)
        #expect(controller.completedNoticeID == nil)
        capture.send(.captureEnded(id))
        try await waitUntil { controller.phase == .processing(id) }
        #expect(controller.completedNoticeID == nil)
        controller.cancel()
        #expect(capture.stopCount == 1)
    }

    @Test func failedFinalSaveDoesNotCompleteAndRetryKeepsNewerPrivateNotes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("meetings")
        try Data([0]).write(to: blocked) // deterministic directory-write failure, independent of chmod/root.
        let store = ScribeMeetingStore(directory: blocked)
        let capture = Capture()
        let controller = ScribeController(provider: capture, store: store)
        let id = try await start(controller, provider: capture)
        controller.receive(ScribeTranscriptSegment(id: "synthetic", session: id, speaker: .participant("Fixture"),
            start: 0, end: 1, text: "We decided to test durable notes.", isFinal: true))
        controller.requestEnd()
        controller.confirmEnd()
        capture.send(.captureEnded(id))
        try await waitUntil { controller.phase == .processing(id) }
        controller.transcriptDidFinish(session: id)
        #expect(controller.phase == .processing(id))
        #expect(controller.completedNoticeID == nil)
        #expect(controller.completionSaveIssue != nil)
        #expect(controller.topBarFeedback()?.phase == .failed)
        #expect(controller.topBarFeedback()?.label == "Meeting needs saving")
        controller.setPrivateNotes("Synthetic private note survives retry", for: id)
        controller.retrySave(id) // still failing; must retain the edited payload.
        #expect(controller.phase == .processing(id))
        #expect(controller.recaps.first(where: { $0.id == id })?.notes.privateNotes == "Synthetic private note survives retry")
        try FileManager.default.removeItem(at: blocked)
        // Flushing the queued private-note edit must use the successful retry transition too; it must
        // not clear the failure banner while leaving an already-saved session stuck in processing.
        controller.closeRecap()
        #expect(controller.phase == .complete(id))
        #expect(controller.completedNoticeID == id)
        #expect(controller.topBarFeedback()?.phase == .completed)
        #expect(controller.topBarFeedback()?.sessionKey == id.rawValue.uuidString)
        #expect(controller.completionSaveIssue == nil)
        #expect(controller.notes?.privateNotes == "Synthetic private note survives retry")
        #expect(store.loadAll().records.first(where: { $0.id == id.rawValue })?.privateNotes == "Synthetic private note survives retry")
        controller.closeNotes()
        #expect(controller.completedNoticeID == nil)
        #expect(controller.topBarFeedback() == nil)
    }

    @Test func boundAppExitDuringManualCountdownCannotRearmAfterKeep() async throws {
        let clock = Clock(), capture = Capture()
        let controller = ScribeController(provider: capture, monotonicClock: { clock.time })
        let app = ScribeCallProcessIdentity(pid: 1234, bundleID: "synthetic.call", launchedAt: 10)
        controller.meetingCallHint = app
        let id = try await start(controller, provider: capture)
        defer { controller.cancel() }
        controller.requestEnd()
        controller.boundCallApplicationDidTerminate(app)
        controller.keepRecording()
        controller.boundCallApplicationDidTerminate(app)
        controller.boundCallApplicationDidTerminate(.init(pid: app.pid, bundleID: app.bundleID, launchedAt: 20))
        clock.time += 20
        controller.tickClock()
        #expect(controller.phase == .recording(id, since: 100))
        #expect(capture.stopCount == 0)
        #expect(controller.endingRemaining == nil)
    }

    @Test func discardingAFailedFinalSaveAlsoDeletesItsEarlierTranscriptCheckpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scribe-discard-\(UUID().uuidString)")
        let store = ScribeMeetingStore(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = Capture()
        var rejectFinal = false
        let controller = ScribeController(provider: capture, store: store, writeMeeting: { record in
            if rejectFinal { throw Failure.eventTimedOut }
            try store.save(record)
        })
        let id = try await start(controller, provider: capture)
        controller.receive(ScribeTranscriptSegment(id: "checkpoint", session: id, speaker: .participant("Fixture"),
            start: 0, end: 1, text: "Synthetic checkpoint to discard.", isFinal: true))
        controller.requestEnd()
        controller.confirmEnd()
        capture.send(.captureEnded(id))
        try await waitUntil { controller.phase == .processing(id) }
        #expect(store.loadAll().records.contains(where: { $0.id == id.rawValue }))
        rejectFinal = true
        controller.transcriptDidFinish(session: id)
        #expect(controller.phase == .processing(id))
        #expect(controller.completionSaveIssue != nil)
        controller.requestDiscardUnsaved(id)
        controller.discardUnsaved(id)
        #expect(controller.phase == .idle)
        #expect(controller.completedNoticeID == nil)
        #expect(!store.loadAll().records.contains(where: { $0.id == id.rawValue }))
        #expect(!ScribeCancelTombstones.ids.contains(id.rawValue))
    }
}
