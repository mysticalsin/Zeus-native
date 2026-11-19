import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// QA7 round 11: with Claude parked and Gemini signed out, the headless CLI fallback chain
/// (Codex/Gemini/Grok/Ollama/Cursor Agent) repeated a previous answer verbatim or leaked a bare
/// "User" onto the end of its reply. Root cause: the old prompt ended in a literal
/// "User: <question>\nAssistant:" cue, which invites a weaker, non-chat-tuned model to keep
/// completing the transcript instead of just answering. These lock the fixed shape in place.
@Suite("CLIEngineProvider prompt (QA7 round 11)")
struct CLIEngineProviderPromptTests {
    @Test func neverEndsWithACompletionCue() {
        let request = BrainRequest(transcript: "why is the sky blue", systemPrompt: "You are ZEUS.")
        let prompt = CLIEngineProvider.prompt(for: request)
        #expect(!prompt.hasSuffix("Assistant:"))
        #expect(prompt.contains("why is the sky blue"))
    }

    @Test func tellsTheModelNotToRepeatOrLabelTurns() {
        let request = BrainRequest(transcript: "and New Zealand?",
                                   history: [Exchange(user: "capital of Australia", assistant: "Canberra.")],
                                   systemPrompt: "You are ZEUS.")
        let prompt = CLIEngineProvider.prompt(for: request)
        #expect(prompt.contains("do not repeat or continue any of it"))
        #expect(prompt.contains("never write the words"))
        #expect(prompt.contains("and New Zealand?"))
    }

    @Test func historyIsLabelledAsPastContextNotAsAnOpenTranscript() {
        let request = BrainRequest(transcript: "new question",
                                   history: [Exchange(user: "old question", assistant: "old answer")],
                                   systemPrompt: "sys")
        let prompt = CLIEngineProvider.prompt(for: request)
        // The old shape ("User: old question\nAssistant: old answer") is gone; history reads as
        // a labelled, prefixed record instead of more lines in the same open pattern.
        #expect(!prompt.contains("User: old question"))
        #expect(!prompt.contains("Assistant: old answer"))
        #expect(prompt.contains("Tony asked: old question"))
        #expect(prompt.contains("You answered: old answer"))
    }

    @Test func withNoHistoryThereIsNoPastContextBlock() {
        let request = BrainRequest(transcript: "hello", systemPrompt: "sys")
        let prompt = CLIEngineProvider.prompt(for: request)
        #expect(!prompt.contains("Earlier in this same conversation"))
    }

    @Test func onlyTheLastSixTurnsAreKept() {
        let history = (1...8).map { Exchange(user: "q\($0)", assistant: "a\($0)") }
        let request = BrainRequest(transcript: "latest", history: history, systemPrompt: "sys")
        let prompt = CLIEngineProvider.prompt(for: request)
        #expect(!prompt.contains("q1"))
        #expect(!prompt.contains("q2"))
        #expect(prompt.contains("q3"))
        #expect(prompt.contains("q8"))
    }

    @Test func aCliEngineNeverListsScreenshotsItCannotReceive() {
        let shot = ScreenShot(jpegData: Data([1]), label: "screen 1 of 1", pixelWidth: 10, pixelHeight: 10, displayFrame: .zero)
        let request = BrainRequest(transcript: "what is on my screen", screenshots: [shot], systemPrompt: "You are ZEUS.",
                                   firstTextBudget: 8)
        let prompt = CLIEngineProvider.prompt(for: request)
        #expect(prompt.contains("you cannot see the screen"))
        #expect(!prompt.contains("Screenshots attached"))
        #expect(!prompt.contains("screen 1 of 1"))
    }
}
