import Foundation
import Testing
@testable import ZeusCore

private actor PromptRecoveryDecoder {
    var results: [Result<String, Error>]
    private(set) var attempts: [WhisperPromptRecovery.Attempt] = []
    init(_ results: [Result<String, Error>]) { self.results = results }
    func decode(_ attempt: WhisperPromptRecovery.Attempt) throws -> String {
        attempts.append(attempt)
        return try results.removeFirst().get()
    }
}

@Suite struct WhisperPromptRecoveryTests {
    private let prompt = "Names: Zeus, Parakeet, WhisperKit, São Paulo."

    @Test func identifiesWholePromptAndLoopedTerms() {
        #expect(WhisperPromptRecovery.shouldRetry("Zeus, Parakeet, WhisperKit, São Paulo.", sentPrompt: prompt))
        #expect(WhisperPromptRecovery.shouldRetry("NAMES: ZEUS PARAKEET WHISPERKIT SÃO PAULO", sentPrompt: prompt))
        #expect(WhisperPromptRecovery.shouldRetry("WhisperKit WhisperKit WhisperKit", sentPrompt: prompt))
    }

    @Test func preservesShortAndOrdinaryDictionarySpeech() {
        for text in ["Zeus", "Zeus, Parakeet", "Zeus Zeus", "Ship Zeus to São Paulo.", "WhisperKit has made this much faster."] {
            #expect(!WhisperPromptRecovery.shouldRetry(text, sentPrompt: prompt), "\(text)")
        }
        #expect(!WhisperPromptRecovery.shouldRetry("Zeus, Parakeet, WhisperKit", sentPrompt: ""))
        #expect(!WhisperPromptRecovery.shouldRetry("Quiet speech is still speech", sentPrompt: prompt))
    }

    @Test func recoveryUsesOnePromptFreeVadFreeLocalRetry() async throws {
        let decoder = PromptRecoveryDecoder([.success("Zeus, Parakeet, WhisperKit, São Paulo."), .success("Send it tomorrow.")])
        let result = try await WhisperPromptRecovery.transcribe(sentPrompt: prompt) { try await decoder.decode($0) }
        #expect(result == "Send it tomorrow.")
        let attempts = await decoder.attempts
        #expect(attempts.map(\.prompt) == [prompt, ""])
        #expect(attempts.map(\.skipVoiceActivityDetection) == [false, true])
    }

    @Test func unpromptedConfirmationKeepsGenuineDictionaryRecitals() async throws {
        let text = "Zeus, Parakeet, WhisperKit, São Paulo."
        let decoder = PromptRecoveryDecoder([.success(text), .success(text)])
        let result = try await WhisperPromptRecovery.transcribe(sentPrompt: prompt) { try await decoder.decode($0) }
        #expect(result == text)
        #expect(await decoder.attempts.count == 2)
    }

    @Test func ordinarySpeechDoesNotDecodeTwice() async throws {
        let decoder = PromptRecoveryDecoder([.success("Please send the Zeus notes.")])
        let result = try await WhisperPromptRecovery.transcribe(sentPrompt: prompt) { try await decoder.decode($0) }
        #expect(result == "Please send the Zeus notes.")
        #expect(await decoder.attempts.count == 1)
    }

    @Test func failedRetryPropagatesInsteadOfReturningTheSuspectPrompt() async {
        let decoder = PromptRecoveryDecoder([.success("Zeus, Parakeet, WhisperKit, São Paulo."), .failure(URLError(.timedOut))])
        await #expect(throws: URLError.self) {
            _ = try await WhisperPromptRecovery.transcribe(sentPrompt: prompt) { try await decoder.decode($0) }
        }
        #expect(await decoder.attempts.count == 2)
    }

    @Test func silenceOnTheUnpromptedRetryDoesNotInsertTheDictionary() async throws {
        let decoder = PromptRecoveryDecoder([.success("Zeus, Parakeet, WhisperKit, São Paulo."), .success("")])
        let result = try await WhisperPromptRecovery.transcribe(sentPrompt: prompt) { try await decoder.decode($0) }
        #expect(result.isEmpty)
    }

    @Test func cancelledTurnNeverStartsRecovery() async {
        let decoder = PromptRecoveryDecoder([.success("Zeus, Parakeet, WhisperKit, São Paulo.")])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await WhisperPromptRecovery.transcribe(sentPrompt: prompt) { try await decoder.decode($0) }
        }
        do { _ = try await task.value; Issue.record("expected cancellation") } catch is CancellationError {} catch { Issue.record("\(error)") }
        #expect(await decoder.attempts.isEmpty)
    }
}
