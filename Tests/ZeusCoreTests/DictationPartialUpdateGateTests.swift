import Dispatch
import Foundation
import Testing
import ZeusCore

@Suite("Dictation partial update ownership")
struct DictationPartialUpdateGateTests {
    @Test func rejectsSpeechSessionMismatchAlone() {
        #expect(!DictationPartialUpdateGate.accepts(
            queuedSpeechSessionID: 10,
            queuedControllerGeneration: 100,
            activeSpeechSessionID: 11,
            activeControllerGeneration: 100,
            currentControllerGeneration: 100
        ))
    }

    @Test func rejectsOriginatingControllerGenerationMismatchAlone() {
        #expect(!DictationPartialUpdateGate.accepts(
            queuedSpeechSessionID: 10,
            queuedControllerGeneration: 100,
            activeSpeechSessionID: 10,
            activeControllerGeneration: 101,
            currentControllerGeneration: 100
        ))
    }

    @Test func rejectsCurrentControllerGenerationMismatchAlone() {
        #expect(!DictationPartialUpdateGate.accepts(
            queuedSpeechSessionID: 10,
            queuedControllerGeneration: 100,
            activeSpeechSessionID: 10,
            activeControllerGeneration: 100,
            currentControllerGeneration: 101
        ))
    }

    @Test func rejectsNilActiveSpeechIdentityAlone() {
        #expect(!DictationPartialUpdateGate.accepts(
            queuedSpeechSessionID: 10,
            queuedControllerGeneration: 100,
            activeSpeechSessionID: nil,
            activeControllerGeneration: 100,
            currentControllerGeneration: 100
        ))
    }

    @Test func rejectsNilActiveControllerGenerationAlone() {
        #expect(!DictationPartialUpdateGate.accepts(
            queuedSpeechSessionID: 10,
            queuedControllerGeneration: 100,
            activeSpeechSessionID: 10,
            activeControllerGeneration: nil,
            currentControllerGeneration: 100
        ))
    }

    @Test func queuedUpdateIsCheckedAgainstOwnershipWhenItExecutes() async {
        struct Ownership: Sendable {
            var speechSessionID: Int?
            var controllerGeneration: UInt64?
            var currentControllerGeneration: UInt64
        }

        let ownership = OwnershipBox(Ownership(
            speechSessionID: 10,
            controllerGeneration: 100,
            currentControllerGeneration: 100
        ))
        let accepted = UpdatesBox()
        let afterReplacement = DispatchSemaphore(value: 0)

        await withCheckedContinuation { continuation in
            // This is the same queued acceptance check called by DictationController.
            DispatchQueue.main.async {
                afterReplacement.wait()
                let state = ownership.value
                if DictationPartialUpdateGate.accepts(
                    queuedSpeechSessionID: 10,
                    queuedControllerGeneration: 100,
                    activeSpeechSessionID: state.speechSessionID,
                    activeControllerGeneration: state.controllerGeneration,
                    currentControllerGeneration: state.currentControllerGeneration
                ) {
                    accepted.append("stale A")
                }
            }

            // Cancel A and start B before A's already-queued main-thread callback executes.
            ownership.value = Ownership(
                speechSessionID: 11,
                controllerGeneration: 101,
                currentControllerGeneration: 101
            )
            afterReplacement.signal()
            DispatchQueue.main.async {
                let state = ownership.value
                if DictationPartialUpdateGate.accepts(
                    queuedSpeechSessionID: 11,
                    queuedControllerGeneration: 101,
                    activeSpeechSessionID: state.speechSessionID,
                    activeControllerGeneration: state.controllerGeneration,
                    currentControllerGeneration: state.currentControllerGeneration
                ) {
                    accepted.append("current B")
                }
            }

            DispatchQueue.main.async { continuation.resume() }
        }

        #expect(accepted.values == ["current B"])

        // Queue A, then cancel A without starting B; its queued callback must be discarded.
        ownership.value = Ownership(
            speechSessionID: 10,
            controllerGeneration: 102,
            currentControllerGeneration: 102
        )
        let afterCancel = DispatchSemaphore(value: 0)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                afterCancel.wait()
                let state = ownership.value
                if DictationPartialUpdateGate.accepts(
                    queuedSpeechSessionID: 10,
                    queuedControllerGeneration: 102,
                    activeSpeechSessionID: state.speechSessionID,
                    activeControllerGeneration: state.controllerGeneration,
                    currentControllerGeneration: state.currentControllerGeneration
                ) {
                    accepted.append("late A after cancel")
                }
            }
            ownership.value = Ownership(
                speechSessionID: nil,
                controllerGeneration: nil,
                currentControllerGeneration: 103
            )
            afterCancel.signal()
            DispatchQueue.main.async { continuation.resume() }
        }

        // The queued callback after Cancel A did not replace the accepted current update.
        #expect(accepted.values == ["current B"])
    }
}

private final class OwnershipBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }
}

private final class UpdatesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }

    var values: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
