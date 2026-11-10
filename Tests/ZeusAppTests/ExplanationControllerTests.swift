import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
import Testing
import ZeusCore
@testable import Zeus

/// Production controller, synthetic services. No microphone, screen capture,
/// installed voices, network/provider calls, user vault, or audio output.
@MainActor
@Suite("Explanation controller with synthetic services", .serialized)
struct ExplanationControllerTests {
    /// Resolve only the trusted, existing OS scratch base. Foundation's path
    /// resolver can restore Darwin's /var alias, which the real store rejects.
    /// Production storage paths still pass through their unchanged no-follow checks.
    private func canonicalFixtureBase() throws -> URL {
        guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    @MainActor private final class Calls {
        var speech = 0, media = 0, captures = 0, screens = 0, permissions = 0
        var acquired = 0, released = 0
    }
    @MainActor private final class DiagnosticClock {
        var now = 10.0
        var step = 0.0
        func read() -> Double { defer { now += step }; return now }
    }
    @MainActor private final class Output: SpeechOutputProvider {
        let calls: Calls
        init(_ calls: Calls) { self.calls = calls }
        func render(_ request: ExplanationSpeechRequest) async throws -> ExplanationPreparedAudio {
            calls.speech += 1
            throw ExplanationAudioError.unavailable
        }
    }
    @MainActor private final class Permissions: ExplanationInputPermissions {
        let calls: Calls
        init(_ calls: Calls) { self.calls = calls }
        func microphone() async -> Bool { calls.permissions += 1; return false }
        func speechRecognition() async -> Bool { calls.permissions += 1; return false }
    }
    @MainActor private final class Capture: ExplanationInputCapturing {
        let calls: Calls
        var onPartial: ((UInt64, String) -> Void)?
        var onLevel: ((UInt64, Double) -> Void)?
        var onFailure: ((UInt64, SpeechInput.CaptureFailure) -> Void)?
        init(_ calls: Calls) { self.calls = calls }
        func start(generation: UInt64, appleRecognition: Bool, deviceUID: String?, locale: String?, hints: [String]) throws { calls.captures += 1 }
        func stop() async -> String { "" }
        func takeSamples() -> [Float] { [] }
        func cancel() {}
    }
    @MainActor private final class Provider: ExplanationModelProviding {
        var requests: [ExplanationModelRequest] = []
        var receivers: [@MainActor (ExplanationEvent) async throws -> Void] = []
        var invalidSecond = false
        var eventCount = 2
        func event(_ request: ExplanationModelRequest, index: Int) -> ExplanationEvent {
            let operation: ExplanationOperation = index == 0
                ? .create(.init(id: "point", geometry: .init(kind: .point, radius: 8), accessibleDescription: "Synthetic point"))
                : .move(id: invalidSecond ? "missing" : "point", position: .init(x: 40, y: 30))
            return .init(sessionID: request.scene.sessionID, turnID: request.turnID, sceneID: request.scene.sceneID,
                sequence: index, baseRevision: request.scene.revision + index, revision: request.scene.revision + index + 1,
                beatID: "beat-\(index)", speech: .init(chunkID: "chunk-\(index)", text: "Synthetic beat \(index)."),
                cues: [.init(id: "cue-\(index)", operations: [operation])], isFinal: index == eventCount - 1)
        }
        func respond(_ request: ExplanationModelRequest,
                     receive: @escaping @MainActor (ExplanationEvent) async throws -> Void) async throws {
            requests.append(request); receivers.append(receive)
            for index in 0..<eventCount { try await receive(event(request, index: index)) }
        }
    }
    @MainActor private final class Fixture {
        let calls = Calls()
        let diagnosticClock = DiagnosticClock()
        let provider = Provider()
        let controller: ExplanationController
        init(store: ExplanationHistoryStore? = nil, storeFactory: (() throws -> ExplanationHistoryStore)? = nil,
             speech: (any SpeechOutputProvider)? = nil, player suppliedPlayer: ExplanationAudioPlayer? = nil) {
            let calls = calls, provider = provider, diagnosticClock = diagnosticClock
            let context = ExplanationScreenContext(services: .init(
                hasPermission: { calls.screens += 1; return false },
                identity: { _ in calls.screens += 1; throw ExplanationScreenContextFailure.unavailable },
                capture: { _ in calls.screens += 1; throw ExplanationScreenContextFailure.unavailable },
                monotonicNow: { 0 }, observeChanges: { _ in nil },
                observeTime: { _ in ExplanationScreenObservation {} }))
            let microphone = ExplanationMicrophone(permissions: Permissions(calls), capture: Capture(calls))
            let player = suppliedPlayer ?? ExplanationAudioPlayer(factory: { _ in calls.media += 1; throw ExplanationAudioError.unavailable })
            controller = ExplanationController(provider: provider, speechProvider: speech ?? Output(calls), player: player,
                microphone: microphone, screenContext: context, store: store, storeFactory: storeFactory,
                acquireAudio: { calls.acquired += 1 }, releaseAudio: { calls.released += 1 },
                diagnosticsClock: { diagnosticClock.read() },
                processSample: { (1, 1_024) })
        }
        func open(captions: Bool = true, id: UUID = UUID()) async {
            await controller.open(conversationID: id)
            controller.setMuted(captions)
        }
        func submit() { controller.draft = "Explain this synthetic point."; controller.submit() }
        func wait(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
            try #require(predicate(), "Synthetic controller phase did not arrive")
        }
    }

    /// Fails only this fixture's owned commit, independently of platform permissions.
    private final class CommitFault: @unchecked Sendable {
        enum Failure: Error { case synthetic }
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        private var enabled = true
        private var attempts = 0
        private var holdNext = false
        private var didEnter = false
        private var didLeave = false
        var count: Int { lock.withLock { attempts } }
        var entered: Bool { lock.withLock { didEnter } }
        var leftGate: Bool { lock.withLock { didLeave } }
        func allowWrites() { lock.withLock { enabled = false } }
        func failWrites() { lock.withLock { enabled = true } }
        func holdNextWrite() { lock.withLock { holdNext = true } }
        func release() { gate.signal() }
        func check(_ stage: ExplanationHistoryStore.FaultStage) throws {
            guard stage == .beforeCommit else { return }
            let (shouldFail, shouldHold) = lock.withLock {
                attempts += 1
                let hold = holdNext; holdNext = false
                if hold { didEnter = true }
                return (enabled, hold)
            }
            // Finite fixture-only gate. Failed assertions cannot retain the real store actor forever.
            if shouldHold {
                _ = gate.wait(timeout: .now() + 1)
                lock.withLock { didLeave = true }
            }
            if shouldFail { throw Failure.synthetic }
        }
    }

    private func withOwnedHistoryFixture(_ fixture: Fixture, root: URL,
                                         body: () async throws -> Void) async throws {
        do { try await body() }
        catch {
            fixture.controller.stop()
            await fixture.controller.flushPendingSaves()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        fixture.controller.stop()
        await fixture.controller.flushPendingSaves()
        try FileManager.default.removeItem(at: root)
    }

    @Test func captionsCommitOnlyOnExplicitAdvanceWithoutAudioOrCapture() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        await fixture.open(); fixture.submit()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        #expect(controller.history?.canonicalScene.objects.isEmpty == true)
        #expect(controller.history?.messages.map(\.role) == [.user])
        controller.advanceCaption()
        #expect(controller.history?.canonicalScene.objects["point"]?.transform.position == .zero)
        #expect(controller.caption == "Synthetic beat 0.")
        controller.advanceCaption()
        #expect(controller.phase == .completed)
        #expect(controller.history?.canonicalScene.objects["point"]?.transform.position == .init(x: 40, y: 30))
        #expect(controller.history?.messages.map(\.role) == [.user, .assistant, .assistant])
        #expect(fixture.calls.speech == 0 && fixture.calls.media == 0 && fixture.calls.acquired == 0)
        #expect(fixture.calls.captures == 0 && fixture.calls.screens == 0 && fixture.calls.permissions == 0)
    }

    @Test func captionDiagnosticsNeverClaimAudibleOutputOrCountReplayAsNewGeneration() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        await fixture.open(); fixture.submit()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        #expect(controller.diagnosticsReport().firstVisualStateSubmissionLatency.count == 0)
        fixture.diagnosticClock.now = 12
        controller.advanceCaption(); controller.advanceCaption()
        let report = controller.diagnosticsReport()
        #expect(report.turnsStarted == 1 && report.firstAudioStartLatency.count == 0)
        #expect(report.firstVisualStateSubmissionLatency.count == 1)
        #expect(report.firstVisualStateSubmissionLatency.totalSeconds == 2)
        #expect(report.cueSchedulerLatenessMediaSeconds.count == 0)
        #expect(report.cancellationSynchronousCleanupSeconds.count == 0)
        #expect(report.peakPhysicalFootprintBytes == 1_024 && report.processCPUSecondsDelta == 0)
        controller.replay()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        controller.advanceCaption(); controller.advanceCaption()
        #expect(controller.diagnosticsReport() == report)
        let exported = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!exported.contains("Synthetic") && !exported.contains("point"))
        #expect(fixture.calls.speech == 0 && fixture.calls.media == 0)
    }

    @Test func failedNarrationDiagnosticsPreserveNumericFailureAndBoundedCleanupOnly() async throws {
        let fixture = Fixture(), controller = fixture.controller
        await fixture.open(captions: false)
        fixture.diagnosticClock.step = 0.125
        fixture.submit()
        try await fixture.wait { controller.problem != nil && !controller.isReceiving }
        let report = controller.diagnosticsReport()
        #expect(report.turnsStarted == 1 && report.failures.audio == 1)
        #expect(report.firstAudioStartLatency.count == 0 && report.firstVisualStateSubmissionLatency.count == 0)
        #expect(report.cancellationSynchronousCleanupSeconds.count == 1)
        #expect(report.cancellationSynchronousCleanupSeconds.totalSeconds > 0)
        controller.stop()
        #expect(controller.diagnosticsReport() == report)
        #expect(fixture.calls.speech == 1 && fixture.calls.media == 0)
    }

    @Test func stopDropsUnpresentedBeatsFromCanonicalHistoryAndReplay() async throws {
        let fixture = Fixture(), controller = fixture.controller
        await fixture.open(); fixture.submit()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        controller.stop()
        #expect(controller.history?.canonicalScene.objects.isEmpty == true)
        #expect(controller.history?.messages.map(\.role) == [.user])
        #expect(!controller.canReplay && controller.phase == .idle)
    }

    @Test func stoppedCaptionReplayContainsOnlyCompletedPrefixAndStaysReadOnly() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        await fixture.open(); fixture.submit()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        controller.advanceCaption() // First beat committed; second beat remains queued.
        controller.stop()
        let canonical = controller.history?.canonicalScene
        #expect(canonical?.objects["point"]?.transform.position == .zero)
        #expect(controller.history?.messages.count == 2 && controller.canReplay && controller.canUndo)
        controller.replay()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        #expect(controller.isReplaying && !controller.canUndo && !controller.canRedo)
        controller.advanceCaption()
        #expect(controller.phase == .completed && controller.problem == nil)
        #expect(controller.scene?.objects["point"]?.transform.position == .zero)
        #expect(controller.history?.canonicalScene == canonical && controller.history?.messages.count == 2)
        #expect(fixture.calls.speech == 0 && fixture.calls.media == 0)
    }

    @Test func lateProviderDeliveryCannotRewriteReplacementTurn() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        await fixture.open(); fixture.submit()
        try await fixture.wait { !controller.isReceiving && fixture.provider.requests.count == 1 }
        let old = fixture.provider.event(fixture.provider.requests[0], index: 0)
        let staleDelivery = fixture.provider.receivers[0]
        fixture.submit()
        try await fixture.wait { !controller.isReceiving && fixture.provider.requests.count == 2 }
        let current = controller.history?.canonicalScene
        await #expect(throws: CancellationError.self) { try await staleDelivery(old) }
        #expect(controller.history?.canonicalScene == current && controller.problem == nil)
        controller.advanceCaption()
        #expect(controller.history?.canonicalScene.objects["point"] != nil)
    }

    @Test func invalidFutureSceneDoesNotCommitEarlierQueuedCue() async throws {
        let fixture = Fixture(), controller = fixture.controller
        fixture.provider.invalidSecond = true
        await fixture.open(); fixture.submit()
        try await fixture.wait { controller.problem != nil && !controller.isReceiving }
        #expect(controller.phase == .idle && controller.history?.canonicalScene.objects.isEmpty == true)
        #expect(controller.history?.messages.map(\.role) == [.user])
        #expect(!controller.canReplay && fixture.calls.speech == 0 && fixture.calls.screens == 0)
        controller.stop()
    }

    @Test func replayDoesNotMutateCanonicalHistoryAndManualEditSupportsUndoRedo() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        await fixture.open(); fixture.submit()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        controller.advanceCaption(); controller.advanceCaption()
        let canonical = controller.history?.canonicalScene, messages = controller.history?.messages
        #expect(controller.canReplay)
        controller.replay()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        controller.advanceCaption(); controller.advanceCaption()
        #expect(controller.phase == .completed && controller.history?.canonicalScene == canonical)
        #expect(controller.history?.messages == messages)
        #expect(controller.isReplaying)
        controller.edit(.move(id: "point", position: .init(x: 90, y: 80)))
        #expect(controller.history?.canonicalScene == canonical) // Preview stays read-only.
        controller.stop() // Return to the canonical scene before editing it.
        controller.edit(.move(id: "point", position: .init(x: 90, y: 80)))
        #expect(controller.history?.canonicalScene.objects["point"]?.transform.position == .init(x: 90, y: 80))
        controller.undo()
        #expect(controller.history?.canonicalScene.objects["point"]?.transform.position == .init(x: 40, y: 30))
        controller.redo()
        #expect(controller.history?.canonicalScene.objects["point"]?.transform.position == .init(x: 90, y: 80))
        #expect(!controller.canReplay)
    }

    @Test func narrationFailureReleasesLeaseWithoutFallbackOrCapture() async throws {
        let fixture = Fixture(), controller = fixture.controller
        await fixture.open(captions: false); fixture.submit()
        try await fixture.wait { controller.problem != nil && !controller.isReceiving }
        #expect(fixture.calls.speech == 1 && fixture.calls.acquired == 1 && fixture.calls.released == 1)
        #expect(fixture.calls.media == 0 && fixture.calls.captures == 0 && fixture.calls.screens == 0)
        #expect(controller.history?.canonicalScene.objects.isEmpty == true)
        controller.stop()
        #expect(fixture.calls.released == 1)
    }

    @Test func deniedMicrophoneRetainsTypedCaptionPath() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        await fixture.open()
        _ = controller.beginListening()
        try await fixture.wait { controller.problem != nil }
        #expect(fixture.calls.captures == 0 && fixture.calls.permissions == 1)
        fixture.submit()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        controller.advanceCaption()
        #expect(controller.history?.canonicalScene.objects["point"] != nil)
    }

    @Test func sameRunLoopPressReleaseCannotStartCaptureOrAskPermissionAfterRelease() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        await fixture.open()
        let attempt = try #require(controller.beginListening())
        controller.finishListening(attemptID: attempt) // Deliberately no await between press/release.
        #expect(controller.inputAttemptID == nil && controller.microphone.state == .idle)
        // A positive independent task establishes that the actor queue has advanced.
        var advanced = false
        Task { @MainActor in advanced = true }
        try await fixture.wait { advanced }
        #expect(fixture.calls.permissions == 0 && fixture.calls.captures == 0)
        #expect(controller.inputAttemptID == nil && controller.problem == nil)
    }

    @Test func admittedHistorySavesAndChatDeletionCannotBeUndoneByLateWrite() async throws {
        let root = try canonicalFixtureBase().appendingPathComponent("zeus-controller-history-" + UUID().uuidString)
        let store = try ExplanationHistoryStore(root: root)
        let fixture = Fixture(store: store), controller = fixture.controller, conversationID = UUID()
        await fixture.open(id: conversationID); fixture.submit()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        controller.advanceCaption(); controller.advanceCaption(); controller.stop()
        await controller.flushPendingSaves()
        let list = try await store.list()
        let summary = try #require(list.records.first)
        let saved = try await store.load(id: summary.id)
        #expect(saved.canonicalScene == controller.history?.canonicalScene)
        #expect(saved.messages.count == 3 && list.failures.isEmpty)
        await controller.deleteConversation(conversationID)
        await controller.flushPendingSaves()
        #expect(try await store.list().records.isEmpty)
        try FileManager.default.removeItem(at: root)
    }

    @Test func failedSaveSurvivesConversationSwitchAndRetriesItsOwnedRecord() async throws {
        let root = try canonicalFixtureBase().appendingPathComponent("zeus-controller-failed-save-" + UUID().uuidString)
        let fault = CommitFault()
        let store = try ExplanationHistoryStore(root: root, faultHook: { try fault.check($0) })
        let fixture = Fixture(store: store), controller = fixture.controller, first = UUID(), second = UUID()
        try await withOwnedHistoryFixture(fixture, root: root) {
            await fixture.open(id: first); fixture.submit()
            try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
            controller.advanceCaption(); controller.stop()
            let original = try #require(controller.history)
            await controller.flushPendingSaves()
            #expect(fault.count > 0 && controller.hasUnsavedHistory && controller.saveProblem != nil)
            #expect(try await store.list().records.isEmpty)
            await controller.open(conversationID: second)
            #expect(controller.history?.canonicalScene.sessionID == second)
            #expect(controller.history?.revision == 0 && controller.hasUnsavedHistory)
            // This fixture owns the whole root; emulate unavailable storage without relying
            // on chmod behavior under privileged CI. There is no successful record to remove.
            try FileManager.default.removeItem(at: root)
            try Data("synthetic unavailable folder".utf8).write(to: root)
            await controller.open(conversationID: first)
            #expect(controller.history == original) // Recover the failed in-memory record, not an empty replacement.
            try FileManager.default.removeItem(at: root)
            fault.allowWrites()
            await controller.flushPendingSaves()
            #expect(!controller.hasUnsavedHistory && controller.saveProblem == nil)
            let loaded = try await store.load(id: original.id)
            #expect(loaded == original)
            #expect(try await store.list().records.count == 1) // Blank second conversation was never persisted.
        }
    }

    @Test func retryCannotRequeueFailedCheckpointBehindNewerInflightSave() async throws {
        let root = try canonicalFixtureBase().appendingPathComponent("zeus-controller-inflight-save-" + UUID().uuidString)
        let fault = CommitFault()
        let store = try ExplanationHistoryStore(root: root, faultHook: { try fault.check($0) })
        let fixture = Fixture(store: store), controller = fixture.controller
        defer { fault.release() }
        try await withOwnedHistoryFixture(fixture, root: root) {
            await fixture.open(); fixture.submit()
            try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
            controller.advanceCaption(); controller.stop()
            await controller.flushPendingSaves()
            #expect(controller.hasUnsavedHistory && controller.saveProblem != nil)
            fault.allowWrites(); fault.holdNextWrite()
            controller.edit(.move(id: "point", position: .init(x: 80, y: 90)))
            let latest = try #require(controller.history)
            try await fixture.wait { fault.entered }
            var retryEntered = false
            let retry = Task { @MainActor in retryEntered = true; await controller.flushPendingSaves() }
            do { try await fixture.wait { retryEntered } }
            catch { fault.release(); await retry.value; throw error }
            #expect(!fault.leftGate) // Prove the newer write is still in flight when retry runs.
            fault.release()
            await retry.value
            #expect(!controller.hasUnsavedHistory && controller.saveProblem == nil)
            #expect(try await store.load(id: latest.id) == latest)
        }
    }

    @Test func anotherRecordSavingCannotClearTheRemainingFailureNotice() async throws {
        let root = try canonicalFixtureBase().appendingPathComponent("zeus-controller-cross-record-save-" + UUID().uuidString)
        let fault = CommitFault()
        let store = try ExplanationHistoryStore(root: root, faultHook: { try fault.check($0) })
        let fixture = Fixture(store: store), controller = fixture.controller
        let first = UUID(), second = UUID(), third = UUID()
        try await withOwnedHistoryFixture(fixture, root: root) {
            await fixture.open(id: first); fixture.submit()
            try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
            controller.advanceCaption(); controller.stop(); await controller.flushPendingSaves()
            #expect(controller.hasUnsavedHistory && controller.saveProblem != nil)
            await controller.open(conversationID: second) // The old record remains a failed owned snapshot.
            fault.allowWrites()
            fixture.submit()
            try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
            controller.advanceCaption()
            // Opening waits for B's admitted write but does not explicitly retry A.
            await controller.open(conversationID: third)
            #expect(controller.history?.canonicalScene.sessionID == third)
            #expect(controller.hasUnsavedHistory && controller.saveProblem != nil)
            let list = try await store.list()
            #expect(list.records.count == 1 && list.records.first?.sessionID == second)
            await controller.flushPendingSaves()
            #expect(!controller.hasUnsavedHistory && controller.saveProblem == nil)
            #expect(try await store.list().records.count == 2)
        }
    }

    @Test func switchingAwaitsPendingSaveAndDoesNotWriteBlankConversation() async throws {
        let root = try canonicalFixtureBase().appendingPathComponent("zeus-controller-pending-save-" + UUID().uuidString)
        let store = try ExplanationHistoryStore(root: root)
        let fixture = Fixture(store: store), controller = fixture.controller, first = UUID(), second = UUID()
        try await withOwnedHistoryFixture(fixture, root: root) {
            await fixture.open(id: first)
            #expect(!controller.hasUnsavedHistory)
            fixture.submit()
            try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
            controller.advanceCaption()
            #expect(controller.hasUnsavedHistory)
            await controller.open(conversationID: second)
            #expect(controller.history?.canonicalScene.sessionID == second && !controller.hasUnsavedHistory)
            let records = try await store.list().records
            #expect(records.count == 1 && records.first?.sessionID == first)
            controller.stop(); await controller.flushPendingSaves()
            #expect(try await store.list().records.count == 1 && !controller.hasUnsavedHistory)
        }
    }

    @Test func memoryOnlyHistoryRefusesSwitchUntilExplicitStorageRecovery() async throws {
        let root = try canonicalFixtureBase().appendingPathComponent("zeus-controller-recover-store-" + UUID().uuidString)
        let store = try ExplanationHistoryStore(root: root)
        var available = false
        let fixture = Fixture(storeFactory: {
            guard available else { throw CommitFault.Failure.synthetic }
            return store
        }), controller = fixture.controller, first = UUID(), second = UUID()
        try await withOwnedHistoryFixture(fixture, root: root) {
            await fixture.open(id: first); fixture.submit()
            try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
            controller.advanceCaption(); controller.stop()
            let original = try #require(controller.history)
            await controller.open(conversationID: second)
            #expect(controller.history == original && controller.problem != nil && controller.hasUnsavedHistory)
            #expect(!controller.canInteract)
            let requests = fixture.provider.requests.count
            fixture.submit()
            #expect(fixture.provider.requests.count == requests && controller.history == original)
            #expect(controller.beginListening() == nil)
            await controller.flushPendingSaves()
            #expect(controller.hasUnsavedHistory && controller.saveProblem != nil)
            available = true
            await controller.flushPendingSaves()
            #expect(!controller.hasUnsavedHistory && controller.saveProblem == nil)
            #expect(try await store.load(id: original.id) == original)
            await controller.open(conversationID: second)
            #expect(controller.history?.canonicalScene.sessionID == second && !controller.hasUnsavedHistory)
        }
    }

    @Test func failedOpenCanRetryTheSameConversationAfterStorageReturns() async throws {
        let root = try canonicalFixtureBase()
            .appendingPathComponent("zeus-controller-retry-open-" + UUID().uuidString)
        try Data("synthetic unavailable folder".utf8).write(to: root)
        let store = try ExplanationHistoryStore(root: root)
        let fixture = Fixture(store: store), controller = fixture.controller, id = UUID()
        // No writes are admitted until a meaningful record exists.
        defer { controller.stop(); try? FileManager.default.removeItem(at: root) }
        await controller.open(conversationID: id)
        #expect(controller.history == nil && controller.problem != nil && !controller.canInteract)
        try FileManager.default.removeItem(at: root)
        await controller.open(conversationID: id)
        #expect(controller.history?.canonicalScene.sessionID == id && controller.problem == nil)
        #expect(controller.canInteract && !controller.hasUnsavedHistory)
    }

    @Test func closingRejectsNewWorkAndStaleDeliveryUntilQuitIsCancelled() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        await fixture.open(); fixture.submit()
        try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
        controller.advanceCaption()
        let stale = fixture.provider.receivers[0]
        let future = fixture.provider.event(fixture.provider.requests[0], index: 1)
        controller.beginClosing()
        let snapshot = controller.history
        #expect(controller.isClosing && !controller.canInteract && controller.hasUnsavedHistory)
        fixture.submit(); controller.replay(); controller.advanceCaption()
        controller.edit(.move(id: "point", position: .init(x: 80, y: 90)))
        controller.undo(); controller.redo(); controller.captureDisplay(1); controller.clearSnapshot()
        #expect(controller.beginListening() == nil)
        await #expect(throws: CancellationError.self) { try await stale(future) }
        #expect(controller.history == snapshot && !controller.isReceiving && controller.phase == .idle)
        #expect(fixture.provider.requests.count == 1 && fixture.calls.screens == 0)
        #expect(fixture.calls.permissions == 0 && fixture.calls.captures == 0 && fixture.calls.speech == 0)
        controller.resumeAfterCancelledQuit()
        #expect(!controller.isClosing && controller.canInteract)
        controller.edit(.move(id: "point", position: .init(x: 80, y: 90)))
        #expect(controller.history?.canonicalScene.objects["point"]?.transform.position == .init(x: 80, y: 90))
    }

    @Test func fullFailedSaveCapacityStillAllowsRecoveringAnOwnedConversation() async throws {
        let root = try canonicalFixtureBase()
            .appendingPathComponent("zeus-controller-retained-capacity-" + UUID().uuidString)
        let fault = CommitFault()
        let store = try ExplanationHistoryStore(root: root, faultHook: { try fault.check($0) })
        let fixture = Fixture(store: store), controller = fixture.controller
        let first = UUID()
        try await withOwnedHistoryFixture(fixture, root: root) {
            var retained: ExplanationHistory?
            for index in 0..<50 {
                await fixture.open(id: index == 0 ? first : UUID()); fixture.submit()
                try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
                controller.advanceCaption()
                if index == 0 { controller.stop(); retained = controller.history }
                // The next open joins this failed save, preserving the real debounce.
            }
            controller.stop(); await controller.flushPendingSaves()
            #expect(controller.hasUnsavedHistory && fault.count >= 50)
            let last = controller.history
            await controller.open(conversationID: UUID())
            #expect(controller.history == last && controller.problem != nil && !controller.canInteract)
            await controller.open(conversationID: first)
            #expect(controller.history == retained && controller.canInteract)
            #expect(controller.hasUnsavedHistory && controller.saveProblem != nil)
        }
    }

    @Test func knownCorruptRecordDeletionIsSafeAndRetryIsIdempotent() async throws {
        let root = try canonicalFixtureBase()
            .appendingPathComponent("zeus-controller-corrupt-delete-" + UUID().uuidString)
        let store = try ExplanationHistoryStore(root: root)
        let id = UUID()
        let record = try ExplanationHistory(scene: .init(sessionID: id, sceneID: UUID()), title: "Owned fixture", at: Date())
        try await store.save(record)
        let path = root.appendingPathComponent(ExplanationHistoryStore.fileName(record.id))
        try Data("synthetic corrupt record".utf8).write(to: path)
        let fixture = Fixture(store: store)
        try await withOwnedHistoryFixture(fixture, root: root) {
            let before = try await store.list()
            #expect(before.failures.count == 1)
            #expect(await fixture.controller.deleteConversation(id, expectedHistoryID: record.id))
            #expect(!FileManager.default.fileExists(atPath: path.path))
            #expect(await fixture.controller.deleteConversation(id, expectedHistoryID: record.id))
            let after = try await store.list()
            #expect(after.records.isEmpty)
        }
    }

    @Test func deletionWithoutOwnedIdentityCannotClaimUnreadableRecordWasRemoved() async throws {
        let root = try canonicalFixtureBase()
            .appendingPathComponent("zeus-controller-unknown-delete-" + UUID().uuidString)
        let store = try ExplanationHistoryStore(root: root)
        let record = try ExplanationHistory(scene: .init(sessionID: UUID(), sceneID: UUID()), title: "Owned fixture", at: Date())
        try await store.save(record)
        let path = root.appendingPathComponent(ExplanationHistoryStore.fileName(record.id))
        try Data("synthetic unreadable record".utf8).write(to: path)
        let fixture = Fixture(store: store)
        try await withOwnedHistoryFixture(fixture, root: root) {
            #expect(await !fixture.controller.deleteConversation(record.canonicalScene.sessionID))
            #expect(FileManager.default.fileExists(atPath: path.path))
            #expect(fixture.controller.saveProblem != nil)
        }
    }

    @Test func firstMeaningfulMemoryOnlySceneLinksExactlyOnceWithoutCapture() async throws {
        let fixture = Fixture(), controller = fixture.controller
        defer { controller.stop() }
        var labels: [String] = []
        controller.onSubmission = { labels.append($0) }
        await fixture.open()
        #expect(labels.isEmpty && !controller.hasUnsavedHistory)
        controller.clearSnapshot() // Valid manual scene mutation; no capture API is invoked.
        let id = try #require(controller.history?.id)
        #expect(labels == ["Visual explanation"] && controller.hasUnsavedHistory)
        controller.clearSnapshot(); controller.stop()
        await controller.flushPendingSaves()
        #expect(labels == ["Visual explanation"] && controller.history?.id == id)
        #expect(fixture.provider.requests.isEmpty && fixture.calls.screens == 0)
        #expect(fixture.calls.permissions == 0 && fixture.calls.captures == 0 && fixture.calls.speech == 0)
    }

    @Test func deletingReopenedHistoryCannotRecreateItsChatLinkDuringStop() async throws {
        let root = try canonicalFixtureBase()
            .appendingPathComponent("zeus-controller-delete-link-" + UUID().uuidString)
        let store = try ExplanationHistoryStore(root: root)
        let id = UUID()
        var record = try ExplanationHistory(scene: .init(sessionID: id, sceneID: UUID()), title: "Owned fixture", at: Date())
        try record.beginTurn(UUID(), at: Date())
        try await store.save(record)
        let fixture = Fixture(store: store), controller = fixture.controller
        try await withOwnedHistoryFixture(fixture, root: root) {
            await controller.open(conversationID: id)
            var relinks = 0
            controller.onSubmission = { _ in relinks += 1 }
            #expect(await controller.deleteConversation(id, expectedHistoryID: record.id))
            #expect(relinks == 0 && controller.history == nil)
            let listing = try await store.list()
            #expect(listing.records.isEmpty && listing.failures.isEmpty)
        }
    }

    @Test func retentionEvictionInvalidatesCheckpointBeforeEditingTheStillOpenRecord() async throws {
        let root = try canonicalFixtureBase()
            .appendingPathComponent("zeus-controller-retention-edit-" + UUID().uuidString)
        let fault = CommitFault(); fault.allowWrites()
        let store = try ExplanationHistoryStore(root: root, policy: .init(maxRecords: 1),
                                               faultHook: { try fault.check($0) })
        let fixture = Fixture(store: store), controller = fixture.controller, first = UUID(), second = UUID()
        try await withOwnedHistoryFixture(fixture, root: root) {
            await fixture.open(id: first); fixture.submit()
            try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
            controller.advanceCaption(); controller.stop(); await controller.flushPendingSaves()
            let firstRecord = try #require(controller.history)
            #expect(!controller.hasUnsavedHistory)
            await controller.open(conversationID: second)
            fault.failWrites(); fixture.submit()
            try await fixture.wait { !controller.isReceiving && controller.phase == .captions }
            controller.advanceCaption(); controller.stop(); await controller.flushPendingSaves()
            #expect(controller.hasUnsavedHistory && controller.saveProblem != nil)
            await controller.open(conversationID: first)
            #expect(controller.history == firstRecord)
            fault.allowWrites(); await controller.flushPendingSaves() // Retrying B evicts A while A remains open.
            let retained = try await store.list()
            #expect(retained.records.count == 1 && retained.records.first?.sessionID == second)
            controller.edit(.move(id: "point", position: .init(x: 80, y: 90)))
            let edited = try #require(controller.history)
            await controller.flushPendingSaves()
            #expect(!controller.hasUnsavedHistory && controller.saveProblem == nil)
            #expect(try await store.load(id: edited.id) == edited)
            let final = try await store.list()
            #expect(final.records.count == 1 && final.records.first?.sessionID == first)
        }
    }

    #if canImport(AVFoundation)
    @MainActor private final class SilentWriter: ExplanationSpeechWriting {
        var writes = 0
        func write(text: String, voiceIdentifier: String?, language: String,
                   receive: @escaping @Sendable (AVAudioBuffer) -> Void) throws {
            writes += 1
            let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240)!
            buffer.frameLength = 240
            buffer.floatChannelData![0].initialize(repeating: 0, count: 240)
            receive(buffer)
            let end = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
            end.frameLength = 0; receive(end)
        }
        func stop() {}
    }
    @MainActor private final class Media: ExplanationMediaPlaying {
        let duration = 0.01
        var currentTime = 0.0
        var rate: Float = 1
        var isPlaying = false
        var onFinish: ((Bool) -> Void)?
        func play() -> Bool { isPlaying = true; return true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false }
    }

    @Test func currentBeatSeekEndsPreviewWithoutPlayingOrSynthesizingQueuedFuture() async throws {
        let root = try canonicalFixtureBase().appendingPathComponent("zeus-controller-seek-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let writer = SilentWriter()
        let output = SystemExplanationSpeechOutput(writer: writer, temporaryRoot: root)
        var media: [Media] = []
        let player = ExplanationAudioPlayer(factory: { _ in
            let value = Media(); media.append(value); return value
        })
        let fixture = Fixture(speech: output, player: player), controller = fixture.controller
        defer { controller.stop(); try? FileManager.default.removeItem(at: root) }
        fixture.provider.eventCount = 3 // The third response waits at the two-clip admission boundary.
        await fixture.open(captions: false); fixture.submit()
        try await fixture.wait { controller.phase == .speaking && writer.writes == 2 }
        let priorFinish = try #require(media.first?.onFinish)
        #expect(controller.isReceiving && media.count == 1 && controller.currentDuration == 0.01)
        controller.seek(0.005)
        let canonical = controller.history?.canonicalScene
        #expect(controller.isReplaying && !controller.isReceiving && !controller.canUndo && !controller.canRedo)
        #expect(media.count == 2 && media.last?.currentTime == 0.005)
        // A stopped native attempt cannot finish its replacement or unblock future synthesis.
        priorFinish(true)
        media.last?.onFinish?(true)
        try await fixture.wait { controller.phase == .completed }
        #expect(controller.problem == nil && controller.history?.canonicalScene == canonical)
        #expect(controller.history?.messages.map(\.role) == [.user])
        #expect(writer.writes == 2 && media.count == 2 && !controller.canReplay)
        #expect(fixture.calls.captures == 0 && fixture.calls.screens == 0 && fixture.calls.permissions == 0)
        controller.stop()
        try await fixture.wait { (try? FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty) == true }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    #endif
}
