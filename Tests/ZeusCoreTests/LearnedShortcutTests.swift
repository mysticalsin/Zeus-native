import Foundation
import Testing
@testable import ZeusCore

@Suite struct LearnedShortcutTests {
    @Test func namedPhraseParsesTwoSteps() {
        let parsed = NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")
        #expect(parsed?.phrase == "focus mode")
        #expect(parsed?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when I say focus mode do close Slack then open Notes")?.steps == ["close Slack", "open Notes"])
    }

    @Test func onlyVerifiedRunsAreSavedAndReplayMakesNoModelCall() {
        var store = LearnedShortcutStore()
        var engine = LearnEngine()
        let steps = ["close Slack", "open Notes"]
        #expect(store.save(phrase: "focus mode", steps: steps, verified: false) == .rejected("unverified"))
        #expect(store.items.isEmpty)

        let first = engine.run(phrase: "focus mode", store: &store, perform: { _ in true }, brain: { steps })
        #expect(first == .brain(steps))
        #expect(engine.llmCalls == 1)
        guard case .saved = store.save(phrase: "focus mode", steps: steps, verified: true) else {
            Issue.record("save"); return
        }

        let second = engine.run(phrase: "Focus Mode", store: &store, perform: { _ in true }, brain: { ["nope"] })
        #expect(second == .replayed)
        #expect(engine.llmCalls == 1)
    }

    @Test func failedReplayFallsBackAndUnlearns() {
        var store = LearnedShortcutStore()
        var engine = LearnEngine()
        _ = store.save(phrase: "focus mode", steps: ["close Slack", "open Notes"], verified: true)
        var brainCalls = 0
        let result = engine.run(phrase: "focus mode", store: &store, perform: { $0 == "close Slack" }, brain: {
            brainCalls += 1
            return ["ask"]
        })
        #expect(result == .fallback)
        #expect(engine.llmCalls == 1)
        #expect(brainCalls == 1)
        #expect(store.match("focus mode") == nil)
    }

    @Test func coordinatesAndLengthAreRejectedAndUndoRestoresTheList() {
        var store = LearnedShortcutStore()
        #expect(store.save(phrase: "spot", steps: ["click 120, 40"], verified: true) == .rejected("coordinates"))
        let long = String(repeating: "a", count: 601)
        #expect(store.save(phrase: "long", steps: [long], verified: true) == .rejected("too long"))
        _ = store.save(phrase: "focus mode", steps: ["open Notes"], verified: true)
        #expect(store.items.map(\.phrase) == ["focus mode"])
        let undone = store.undo()
        #expect(undone)
        #expect(store.items.isEmpty)
        let again = store.undo()
        #expect(!again)
    }

    @Test func listRoundTripsAndAcceptancePasses() throws {
        var store = LearnedShortcutStore()
        _ = store.save(phrase: "focus mode", steps: ["open Notes"], verified: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-learn-\(UUID().uuidString).json")
        try store.write(to: url)
        let loaded = LearnedShortcutStore.load(from: url)
        #expect(loaded.items.map(\.phrase) == ["focus mode"])
        try? FileManager.default.removeItem(at: url)
        let report = LearnAcceptance.report()
        #expect(report.passed)
        #expect(report.text.hasPrefix("PASS"))
    }
}
