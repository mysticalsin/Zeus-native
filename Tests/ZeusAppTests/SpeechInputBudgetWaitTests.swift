import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Fires only when the test says so. The live stop path must arm the budget, not sleep 2.5 s.
private final class ManualFinalClock: @unchecked Sendable {
    private let lock = NSLock()
    private var fire: (@Sendable () -> Void)?
    private var waiter: CheckedContinuation<Int, Never>?
    private var armedMs: Int?

    func install(on input: SpeechInput) {
        input.scheduleFinalWait = { [weak self] milliseconds, fire in
            self?.arm(milliseconds: milliseconds, fire: fire)
        }
        input.cancelFinalWait = { [weak self] in
            self?.disarm()
        }
    }

    func waitArmed() async -> Int {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let armedMs {
                lock.unlock()
                continuation.resume(returning: armedMs)
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }

    func advance() {
        lock.lock()
        let fire = self.fire
        self.fire = nil
        lock.unlock()
        fire?()
    }

    private func arm(milliseconds: Int, fire: @escaping @Sendable () -> Void) {
        lock.lock()
        armedMs = milliseconds
        self.fire = fire
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(returning: milliseconds)
    }

    private func disarm() {
        lock.lock()
        fire = nil
        lock.unlock()
    }
}

@Suite("Speech input budget wait", .serialized)
struct SpeechInputBudgetWaitTests {
    @Test func keyUpReturnsThePartialAtTheBudgetWhenNoFinalArrives() async {
        let input = SpeechInput()
        let clock = ManualFinalClock()
        _ = input.beginSessionForTesting(requestFormat: nil)
        clock.install(on: input)
        input.acceptTranscriptForTesting("partial phrase", isFinal: false)

        async let transcript = input.stop()
        let armed = await clock.waitArmed()
        #expect(armed == TalkLatencyBudget.sttFinalCapMs)
        #expect(armed != 2_500)
        clock.advance()
        let text = await transcript
        #expect(text == "partial phrase")
        #expect(input.didCancelRecognitionForTesting)
    }

    @Test func aFinalAtTwoHundredMillisecondsWinsOverTheBudget() async {
        let input = SpeechInput()
        let clock = ManualFinalClock()
        _ = input.beginSessionForTesting(requestFormat: nil)
        clock.install(on: input)
        input.acceptTranscriptForTesting("hel", isFinal: false)

        async let transcript = input.stop()
        let armed = await clock.waitArmed()
        #expect(armed == 450)
        input.acceptTranscriptForTesting("hello there", isFinal: true)
        let text = await transcript
        #expect(text == "hello there")
        #expect(!input.didCancelRecognitionForTesting)
        clock.advance()
        #expect(text == "hello there")
    }
}
