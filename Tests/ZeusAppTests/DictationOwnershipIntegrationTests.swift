import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Drives the same `DictationTurnOwnership`, `DictationFinishFlow`, `DictationInjectCompletion`,
/// `TextInserter.runPaste`/`runType`, `TextInserter.DeliveryGate` and `SpeechInput` tail helpers
/// that the controller, speech input and delivery path call, with synthetic closures.
/// No controller, SpeechInput, engine, settings, audio, accessibility, pasteboard, CGEvent or
/// NSWorkspace is created.
@MainActor
@Suite("Dictation ownership and delivery gate")
struct DictationOwnershipIntegrationTests {
    @Test func missingCloudKeyRetainsFailureDuringFinish() async {
        // A nil key exits before creating/resuming any socket. This exercises the real
        // stream's terminal lock snapshot without provider calls, audio or credentials.
        let stream = ElevenLabsStream(apiKey: nil, language: nil, keyterms: [])
        do {
            _ = try await stream.finish()
            Issue.record("Missing-key failure was lost while finishing the stream")
        } catch {
            #expect(error as? CloudTranscriptionError == .missingKey(ElevenLabsRealtime.provider))
        }
    }

    /// Holds queued work so a test can cancel or replace the turn before it runs.
    @MainActor
    private final class ManualQueue {
        var work: [@MainActor @Sendable () -> Void] = []
        func enqueue(_ item: @escaping @MainActor @Sendable () -> Void) { work.append(item) }
        func drain() {
            let pending = work
            work = []
            pending.forEach { $0() }
        }
    }

    private final class Sink: @unchecked Sendable {
        var written: [String] = []
    }

    @MainActor
    private final class Log {
        var events: [String] = []
        func add(_ event: String) { events.append(event) }
    }

    private func route(_ ownership: DictationTurnOwnership, session: Int, generation: UInt64, text: String,
                       queue: ManualQueue, sink: Sink) {
        ownership.route(sessionID: session, generation: generation, text: text,
                        enqueue: { queue.enqueue($0) }, write: { sink.written.append($0) })
    }

    @Test func activeTurnDeliversQueuedPartial() {
        let ownership = DictationTurnOwnership()
        let queue = ManualQueue(), sink = Sink()
        let turn = ownership.beginTurn()
        ownership.bind(speechSessionID: 7, generation: turn)
        route(ownership, session: 7, generation: turn, text: "hello", queue: queue, sink: sink)
        queue.drain()
        #expect(sink.written == ["hello"])
    }

    @Test func cancelBetweenEnqueueAndExecutionDropsThePartial() {
        let ownership = DictationTurnOwnership()
        let queue = ManualQueue(), sink = Sink()
        let turn = ownership.beginTurn()
        ownership.bind(speechSessionID: 7, generation: turn)
        route(ownership, session: 7, generation: turn, text: "stale", queue: queue, sink: sink)
        ownership.invalidate() // what DictationController.cancel() does
        queue.drain()
        #expect(sink.written.isEmpty)
    }

    @Test func replacementTurnDropsTheOldTurnsQueuedPartial() {
        let ownership = DictationTurnOwnership()
        let queue = ManualQueue(), sink = Sink()
        let first = ownership.beginTurn()
        ownership.bind(speechSessionID: 7, generation: first)
        route(ownership, session: 7, generation: first, text: "old", queue: queue, sink: sink)
        let second = ownership.beginTurn()
        ownership.bind(speechSessionID: 8, generation: second)
        route(ownership, session: 8, generation: second, text: "new", queue: queue, sink: sink)
        queue.drain()
        #expect(sink.written == ["new"])
    }

    @Test func sameSpeechSessionFromAnOlderControllerTurnIsRejected() {
        let ownership = DictationTurnOwnership()
        let queue = ManualQueue(), sink = Sink()
        let first = ownership.beginTurn()
        let second = ownership.beginTurn()
        ownership.bind(speechSessionID: 7, generation: second)
        route(ownership, session: 7, generation: first, text: "old turn", queue: queue, sink: sink)
        queue.drain()
        #expect(sink.written.isEmpty)
    }

    @Test func partialBeforeBindingIsRejected() {
        let ownership = DictationTurnOwnership()
        let queue = ManualQueue(), sink = Sink()
        let turn = ownership.beginTurn()
        route(ownership, session: 7, generation: turn, text: "early", queue: queue, sink: sink)
        queue.drain()
        #expect(sink.written.isEmpty)
    }

    @Test func bindingAStaleGenerationDoesNotActivateIt() {
        let ownership = DictationTurnOwnership()
        let stale = ownership.beginTurn()
        _ = ownership.beginTurn()
        ownership.bind(speechSessionID: 7, generation: stale)
        #expect(!ownership.accepts(sessionID: 7, generation: stale))
    }

    @Test func retireOnlyClosesLiveWordsForTheTurnItBelongsTo() {
        let ownership = DictationTurnOwnership()
        let finished = ownership.beginTurn()
        let next = ownership.beginTurn()
        ownership.bind(speechSessionID: 9, generation: next)
        ownership.retire(generation: finished)
        #expect(ownership.accepts(sessionID: 9, generation: next))
        ownership.retire(generation: next)
        #expect(!ownership.accepts(sessionID: 9, generation: next))
    }

    @Test func retireKeepsTheFinishingTurnAsOwner() {
        let ownership = DictationTurnOwnership()
        let turn = ownership.beginTurn()
        ownership.bind(speechSessionID: 3, generation: turn)
        ownership.retire(generation: turn)
        #expect(ownership.owns(generation: turn))
        ownership.invalidate()
        #expect(!ownership.owns(generation: turn))
    }

    @Test func recognitionTurnCarriesIdentityThroughRestart() {
        let first = SpeechInput.RecognitionTurn(sessionID: 4, origin: 99)
        let restarted = first.restarted().restarted()
        #expect(restarted == first)
        let seen = Sink()
        let identified = Identified()
        restarted.emit("words", legacy: { seen.written.append($0) },
                       identified: { identified.calls.append(Call(session: $0, origin: $1, text: $2)) })
        #expect(seen.written == ["words"])
        #expect(identified.calls == [Call(session: 4, origin: 99, text: "words")])
    }

    @Test func recognitionTurnWorksWithoutALegacyCallback() {
        let identified = Identified()
        SpeechInput.RecognitionTurn(sessionID: 1, origin: 2)
            .emit("x", legacy: nil, identified: { identified.calls.append(Call(session: $0, origin: $1, text: $2)) })
        #expect(identified.calls.count == 1)
    }

    // MARK: Finish flow (what DictationController.finish() runs)

    private func finishFlow(_ ownership: DictationTurnOwnership, turn: UInt64, log: Log, heard: String = "hello world",
                            review: ((String) async -> String?)? = nil,
                            onTranscribe: @escaping () -> Void = {}, onProcess: @escaping () -> Void = {},
                            onReview: @escaping () -> Void = {}, onDeliver: @escaping () -> Void = {}) -> DictationFinishFlow {
        var wrappedReview: ((String) async -> String?)?
        if let review {
            wrappedReview = { (text: String) async -> String? in
                log.add("review")
                onReview()
                return await review(text)
            }
        }
        return DictationFinishFlow(
            isCurrent: { ownership.owns(generation: turn) },
            transcribe: {
                log.add("transcribe")
                onTranscribe()
                return .init(text: heard, engine: .apple, samples: [0.1])
            },
            closePartials: { ownership.retire(generation: turn); log.add("closePartials") },
            process: { raw in log.add("process"); onProcess(); return raw.uppercased() },
            review: wrappedReview,
            deliver: { text in log.add("deliver \(text)"); onDeliver(); return .pasted },
            onEmpty: { log.add("empty") },
            onDiscarded: { log.add("discarded") },
            onDelivered: { raw, text, outcome, _ in log.add("delivered \(raw)|\(text)|\(outcome)") })
    }

    @Test func finishDeliversAndRecordsForTheOwningTurn() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        ownership.bind(speechSessionID: 1, generation: turn)
        let result = await finishFlow(ownership, turn: turn, log: log).run()
        #expect(result == .delivered(.pasted))
        #expect(log.events == ["transcribe", "closePartials", "process", "deliver HELLO WORLD", "delivered hello world|HELLO WORLD|pasted"])
        // Closing the live words did not stop the turn from owning its own finish.
        #expect(ownership.owns(generation: turn))
    }

    @Test func finishCancelledDuringTranscribeTouchesNothing() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await finishFlow(ownership, turn: turn, log: log, onTranscribe: { ownership.invalidate() }).run()
        #expect(result == .superseded)
        #expect(log.events == ["transcribe"])
    }

    @Test func finishCancelledDuringProcessNeverDelivers() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await finishFlow(ownership, turn: turn, log: log, onProcess: { ownership.invalidate() }).run()
        #expect(result == .superseded)
        #expect(!log.events.contains { $0.hasPrefix("deliver") || $0.hasPrefix("delivered") })
    }

    @Test func finishReplacedDuringPreviewNeverDeliversIntoTheNewTurn() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await finishFlow(ownership, turn: turn, log: log, review: { $0 },
                                      onReview: { _ = ownership.beginTurn() }).run()
        #expect(result == .superseded)
        #expect(log.events == ["transcribe", "closePartials", "process", "review"])
    }

    @Test func finishCancelledDuringDeliveryWritesNoHistoryOrStatus() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await finishFlow(ownership, turn: turn, log: log, onDeliver: { ownership.invalidate() }).run()
        #expect(result == .superseded)
        #expect(!log.events.contains { $0.hasPrefix("delivered") })
    }

    @Test func unconfirmedReplacementIsReportedWithoutRelabelingItCopiedOrRetrying() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        var flow = finishFlow(ownership, turn: turn, log: log)
        var deliveries = 0
        var reported: TextInserter.Outcome?
        flow.deliver = { _ in deliveries += 1; return .unconfirmed }
        flow.onDelivered = { _, _, outcome, _ in reported = outcome }
        #expect(await flow.run() == .delivered(.unconfirmed))
        #expect(reported == .unconfirmed)
        #expect(deliveries == 1)
    }

    @Test func discardedPreviewReportsDiscardOnlyWhileCurrent() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await finishFlow(ownership, turn: turn, log: log, review: { _ in nil }).run()
        #expect(result == .discarded)
        #expect(log.events.last == "discarded")
        let second = ownership.beginTurn()
        let log2 = Log()
        let stale = await finishFlow(ownership, turn: second, log: log2, review: { _ in nil },
                                     onReview: { ownership.invalidate() }).run()
        #expect(stale == .superseded)
        #expect(!log2.events.contains("discarded"))
    }

    @Test func emptyTranscriptIsReportedAndNeverDelivered() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await finishFlow(ownership, turn: turn, log: log, heard: "  \n").run()
        #expect(result == .empty)
        #expect(log.events == ["transcribe", "closePartials", "empty"])
    }

    @Test func aTurnAlreadySupersededNeverStartsTranscribing() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        _ = ownership.beginTurn()
        let result = await finishFlow(ownership, turn: turn, log: log).run()
        #expect(result == .superseded)
        #expect(log.events.isEmpty)
    }

    // MARK: Inject completion (what injectDictationFile runs after the feed)

    private func injectCompletion(_ ownership: DictationTurnOwnership, turn: UInt64, log: Log, fed: Bool = true,
                                  onFeed: @escaping () -> Void = {}, onSleep: @escaping () -> Void = {}) -> DictationInjectCompletion {
        DictationInjectCompletion(
            isCurrent: { ownership.owns(generation: turn) },
            sleep: { _ in log.add("sleep"); onSleep() },
            feed: { log.add("feed"); onFeed(); return fed },
            activate: { log.add("activate") },
            finish: { log.add("finish") })
    }

    @Test func ownedInjectFocusesThenFinishes() async throws {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let finished = try await injectCompletion(ownership, turn: turn, log: log).run()
        #expect(finished)
        #expect(log.events == ["feed", "activate", "sleep", "finish"])
    }

    @Test func injectThatLostItsSessionDuringTheFeedDoesNothing() async throws {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let finished = try await injectCompletion(ownership, turn: turn, log: log, fed: false).run()
        #expect(!finished)
        #expect(log.events == ["feed"])
    }

    @Test func injectReplacedAfterTheFeedNeverActivatesOrFinishesTheNewTurn() async throws {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let finished = try await injectCompletion(ownership, turn: turn, log: log,
                                                  onFeed: { _ = ownership.beginTurn() }).run()
        #expect(!finished)
        #expect(log.events == ["feed"])
    }

    @Test func injectReplacedDuringTheFocusDelayNeverFinishesTheNewTurn() async throws {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let finished = try await injectCompletion(ownership, turn: turn, log: log,
                                                  onSleep: { ownership.invalidate() }).run()
        #expect(!finished)
        #expect(!log.events.contains("finish"))
    }

    // MARK: SpeechInput inject tail

    @Test func ownedInjectTailEndsAudio() {
        var stop = false
        var ended = 0
        let done = SpeechInput.applyInjectTail(owner: 5, current: 5, stopRequested: &stop, endAudio: { ended += 1 })
        #expect(done)
        #expect(stop)
        #expect(ended == 1)
    }

    @Test func staleInjectTailNeverEndsTheNewerSessionsAudio() {
        var stop = false
        var ended = 0
        let done = SpeechInput.applyInjectTail(owner: 5, current: 6, stopRequested: &stop, endAudio: { ended += 1 })
        #expect(!done)
        #expect(!stop)
        #expect(ended == 0)
    }

    @Test func staleInjectDoesNotClearTheNewerSessionsLiveTapSuppression() {
        var suppress = true
        SpeechInput.releaseLiveTapSuppression(owner: 5, current: 6, suppress: &suppress)
        #expect(suppress)
        SpeechInput.releaseLiveTapSuppression(owner: 6, current: 6, suppress: &suppress)
        #expect(!suppress)
    }

    @Test func aNewLiveSessionClearsSuppressionLeftByACancelledInject() {
        var suppress = false
        SpeechInput.acquireLiveTapSuppression(owner: 5, current: 5, suppress: &suppress)
        #expect(suppress)
        // The inject is cancelled by a normal start(): its release is stale and leaves the flag set.
        SpeechInput.releaseLiveTapSuppression(owner: 5, current: 6, suppress: &suppress)
        #expect(suppress)
        SpeechInput.resetLiveTapSuppression(suppress: &suppress) // what start() runs
        #expect(!suppress)
    }

    @Test func aReplacedInjectNeverSuppressesTheLiveTap() {
        var suppress = false
        SpeechInput.acquireLiveTapSuppression(owner: 5, current: 6, suppress: &suppress)
        #expect(!suppress)
        SpeechInput.acquireLiveTapSuppression(owner: 6, current: 6, suppress: &suppress)
        #expect(suppress)
    }

    @Test func staleStopTimerCannotFinishAReplacementSession() {
        #expect(!SpeechInput.shouldFinishAfterStopTimeout(session: 5, current: 6))
        #expect(SpeechInput.shouldFinishAfterStopTimeout(session: 6, current: 6))
    }

    @Test func staleStopTimerLeavesReplacementFinishedAndWaitersUntouched() {
        var finished = false
        var waiters = [1, 2]
        let stale = SpeechInput.finishWaitersIfOwned(session: 5, current: 6, finished: &finished, waiters: &waiters)
        #expect(stale == nil)
        #expect(!finished)
        #expect(waiters == [1, 2])

        let owned = SpeechInput.finishWaitersIfOwned(session: 6, current: 6, finished: &finished, waiters: &waiters)
        #expect(owned == [1, 2])
        #expect(finished)
        #expect(waiters.isEmpty)
    }

    // MARK: Clipboard snapshot (what TextInserter.insert saves before writing)

    private typealias Board = TextInserter.Snapshot
    private func item(_ text: String) -> Board { [[.string: Data(text.utf8)]] }

    @Test func replacementOverOurOwnDictatedWriteInheritsTheTrueOriginal() {
        let original = item("user clipboard")
        let pending = TextInserter.PendingOriginal(changeCount: 42, saved: original)
        var reads = 0
        let saved = TextInserter.resolveSnapshot(boardChangeCount: 42, pending: pending,
                                                 read: { reads += 1; return item("cancelled turn text") })
        #expect(saved == original)
        #expect(reads == 0)
    }

    @Test func replacementOverAnOriginallyEmptyClipboardRestoresNothing() {
        let pending = TextInserter.PendingOriginal(changeCount: 7, saved: nil)
        let saved = TextInserter.resolveSnapshot(boardChangeCount: 7, pending: pending,
                                                 read: { item("cancelled turn text") })
        #expect(saved == nil)
    }

    @Test func aBoardSomeoneElseChangedIsSnapshottedFresh() {
        let pending = TextInserter.PendingOriginal(changeCount: 42, saved: item("old"))
        var reads = 0
        let saved = TextInserter.resolveSnapshot(boardChangeCount: 43, pending: pending,
                                                 read: { reads += 1; return item("copied since") })
        #expect(saved == item("copied since"))
        #expect(reads == 1)
        #expect(TextInserter.resolveSnapshot(boardChangeCount: 1, pending: nil, read: { item("first") }) == item("first"))
    }

    // MARK: Delayed paste and typing (what TextInserter.insert / type run)

    private func steps(_ log: Log, onSleep: @escaping (Int) -> Void = { _ in }) -> TextInserter.SinkSteps {
        TextInserter.SinkSteps(
            sleep: { ms in log.add("sleep \(ms)"); onSleep(ms) },
            pasteKey: { log.add("paste") },
            returnKey: { log.add("return") },
            typeChunk: { log.add("chunk \(String(decoding: $0, as: UTF16.self))") },
            newline: { log.add("newline") },
            copyText: { log.add("copy") },
            restoreIfUnchanged: { log.add("restore") })
    }

    @Test func readyTargetPastesThenRestoresTheClipboard() async {
        let log = Log()
        let result = await TextInserter.runPaste(pressReturn: false, restoreClipboard: true, steps: steps(log), check: { .paste })
        #expect(result == .pasted)
        #expect(log.events == ["sleep 60", "paste", "sleep 450", "restore"])
    }

    @Test func ungatedPasteKeepsLegacyBehaviour() async {
        let log = Log()
        let result = await TextInserter.runPaste(pressReturn: true, restoreClipboard: false, steps: steps(log), check: nil)
        #expect(result == .pasted)
        #expect(log.events == ["sleep 60", "paste", "sleep 120", "return"])
    }

    @Test func turnCancelledDuringTheSettleDelayNeverPastes() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await TextInserter.runPaste(
            pressReturn: true, restoreClipboard: true,
            steps: steps(log, onSleep: { _ in ownership.invalidate() }),
            check: { ownership.owns(generation: turn) ? .paste : .abort })
        #expect(result == .aborted)
        #expect(log.events == ["sleep 60", "restore"])
    }

    @Test func targetDriftingDuringTheSettleDelayLeavesTheTextOnTheClipboard() async {
        let log = Log()
        let result = await TextInserter.runPaste(pressReturn: false, restoreClipboard: true, steps: steps(log),
                                                 check: { .clipboardOnly })
        #expect(result == .clipboardOnly)
        #expect(log.events == ["sleep 60"])
    }

    @Test func returnIsSkippedWhenTheTurnIsGoneBeforeIt() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await TextInserter.runPaste(
            pressReturn: true, restoreClipboard: true,
            steps: steps(log, onSleep: { if $0 == 120 { ownership.invalidate() } }),
            check: { ownership.owns(generation: turn) ? .paste : .abort })
        #expect(result == .pasted)
        #expect(log.events == ["sleep 60", "paste", "sleep 120", "sleep 450", "restore"])
    }

    @Test func clipboardRestoreStillRunsForACancelledTurnSoItsTextDoesNotLinger() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        _ = await TextInserter.runPaste(
            pressReturn: false, restoreClipboard: true,
            steps: steps(log, onSleep: { if $0 == 450 { ownership.invalidate() } }),
            check: { ownership.owns(generation: turn) ? .paste : .abort })
        #expect(log.events.last == "restore")
    }

    private func pieces(_ text: String) -> [KeystrokeTyping.Piece] { KeystrokeTyping.pieces(text) }

    @Test func readyTargetTypesEveryPiece() async {
        let log = Log()
        let result = await TextInserter.runType(pieces: pieces("ab\ncd"), pressReturn: true, steps: steps(log), check: { .paste })
        #expect(result == .typed)
        #expect(log.events == ["sleep 60", "chunk ab", "sleep 8", "newline", "sleep 8", "chunk cd", "sleep 8",
                               "sleep 120", "newline"])
    }

    @Test func typingStopsAtThePieceWhereTheTurnIsCancelled() async {
        let ownership = DictationTurnOwnership(), log = Log()
        let turn = ownership.beginTurn()
        let result = await TextInserter.runType(
            pieces: pieces("ab\ncd"), pressReturn: true,
            steps: steps(log, onSleep: { if $0 == 8 { ownership.invalidate() } }),
            check: { ownership.owns(generation: turn) ? .paste : .abort })
        #expect(result == .aborted(piecesTyped: 1))
        #expect(log.events == ["sleep 60", "chunk ab", "sleep 8"])
    }

    @Test func typingTargetDriftCopiesInsteadOfTypingOn() async {
        let log = Log()
        var calls = 0
        let result = await TextInserter.runType(pieces: pieces("ab\ncd"), pressReturn: false, steps: steps(log),
                                                check: { calls += 1; return calls == 1 ? .paste : .clipboardOnly })
        #expect(result == .clipboardOnly)
        #expect(log.events == ["sleep 60", "chunk ab", "sleep 8", "copy"])
    }

    @Test func typedReturnNeedsTheGateAgain() async {
        let log = Log()
        var calls = 0
        let result = await TextInserter.runType(pieces: pieces("ab"), pressReturn: true, steps: steps(log),
                                                check: { calls += 1; return calls <= 1 ? .paste : .abort })
        #expect(result == .aborted(piecesTyped: 1))
        #expect(!log.events.contains("newline"))
    }

    // MARK: Delivery gate

    private typealias Identity = DictationFileInject.TargetIdentity

    private func probe(frontmost: Identity?, focus: Identity?) -> TextInserter.DeliveryGate.Probe {
        .init(frontmost: { frontmost }, focused: { focus })
    }

    private func app(_ pid: Int32, _ bundle: String? = "com.example.app") -> Identity { .init(pid: pid, bundleID: bundle) }

    @Test func onlyAReadyTargetPastes() {
        let gate = TextInserter.DeliveryGate.self
        let ready = gate.state(target: app(10), terminated: false, probe: probe(frontmost: app(10), focus: app(10)))
        #expect(ready == .ready)
        #expect(gate.action(for: ready, allowClipboardFallback: false) == .paste)
        #expect(gate.action(for: ready, allowClipboardFallback: true) == .paste)
    }

    @Test func everyUnknownOrNegativeStateNeverPastes() {
        let gate = TextInserter.DeliveryGate.self
        let cases: [(Identity?, Bool, Identity?, Identity?, DictationFileInject.TargetState)] = [
            (nil, false, app(10), app(10), .unavailable),
            (app(10), true, app(10), app(10), .unavailable), // target terminated
            (app(10), false, nil, app(10), .frontmostUnavailable),
            (app(10), false, app(11), app(10), .frontmostDrift),
            (app(10), false, app(10), nil, .focusUnavailable),
            (app(10), false, app(10), app(11), .focusDrift),
        ]
        for (target, terminated, frontmost, focus, expected) in cases {
            let state = gate.state(target: target, terminated: terminated, probe: probe(frontmost: frontmost, focus: focus))
            #expect(state == expected)
            #expect(gate.action(for: state, allowClipboardFallback: false) == .abort)
            #expect(gate.action(for: state, allowClipboardFallback: true) == .clipboardOnly)
        }
    }

    @Test func aReusedPIDUnderAnotherBundleIsNotTheTarget() {
        let gate = TextInserter.DeliveryGate.self
        let target = app(10, "com.apple.TextEdit")
        let frontmostSwap = gate.state(target: target, terminated: false,
                                       probe: probe(frontmost: app(10, "com.example.other"), focus: target))
        #expect(frontmostSwap == .frontmostDrift)
        let focusSwap = gate.state(target: target, terminated: false,
                                   probe: probe(frontmost: target, focus: app(10, "com.example.other")))
        #expect(focusSwap == .focusDrift)
    }

    @Test func aMissingBundleOnOneSideDoesNotMatch() {
        let gate = TextInserter.DeliveryGate.self
        let withBundle = app(10, "com.apple.TextEdit"), without = app(10, nil)
        #expect(gate.state(target: withBundle, terminated: false, probe: probe(frontmost: without, focus: without)) == .frontmostDrift)
        #expect(gate.state(target: without, terminated: false, probe: probe(frontmost: without, focus: without)) == .ready)
    }

    @Test func terminatedTargetIsNotProbed() {
        var probed = false
        let spy = TextInserter.DeliveryGate.Probe(frontmost: { probed = true; return app(10) }, focused: { probed = true; return app(10) })
        let state = TextInserter.DeliveryGate.state(target: app(10), terminated: true, probe: spy)
        #expect(state == .unavailable)
        #expect(!probed)
    }
}

private struct Call: Equatable { let session: Int; let origin: UInt64; let text: String }
private final class Identified: @unchecked Sendable { var calls: [Call] = [] }
