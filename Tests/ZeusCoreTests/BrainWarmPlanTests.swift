import Foundation
import Testing
@testable import ZeusCore

@Suite("Brain warm plan")
struct BrainWarmPlanTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func idleMacMakesNoCalls() {
        #expect(BrainWarmPlan.due(now: now, lastActivity: nil, lastCloud: nil, lastLocal: nil).isEmpty)
        let longAgo = now.addingTimeInterval(-BrainWarmPlan.activeWindow - 1)
        #expect(BrainWarmPlan.due(now: now, lastActivity: longAgo, lastCloud: nil, lastLocal: nil).isEmpty)
    }

    @Test func launchAndWakeWarmEverythingOnce() {
        #expect(BrainWarmPlan.due(now: now, lastActivity: nil, lastCloud: now, lastLocal: now, forced: true)
                == [.localModel, .cloudConnection])
    }

    @Test func whileInUseTheConnectionIsRefreshedBeforeItGoesCold() {
        let active = now.addingTimeInterval(-30)
        let recent = now.addingTimeInterval(-60)
        #expect(BrainWarmPlan.due(now: now, lastActivity: active, lastCloud: recent, lastLocal: recent).isEmpty)
        let cloudStale = now.addingTimeInterval(-BrainWarmPlan.cloudInterval)
        #expect(BrainWarmPlan.due(now: now, lastActivity: active, lastCloud: cloudStale, lastLocal: recent) == [.cloudConnection])
        let localStale = now.addingTimeInterval(-BrainWarmPlan.localInterval)
        #expect(BrainWarmPlan.due(now: now, lastActivity: active, lastCloud: recent, lastLocal: localStale) == [.localModel])
    }

    @Test func intervalsAreLooseAndBeatTheIdleTimeouts() {
        #expect(BrainWarmPlan.checkEvery >= 60)          // never a tight timer
        #expect(BrainWarmPlan.cloudInterval <= 5 * 60)   // idle HTTPS connections drop within minutes
        #expect(BrainWarmPlan.localInterval < 30 * 60)   // before Ollama's keep_alive runs out
    }

    @Test func raceOrderPutsTheFastestHTTPEngineFirst() {
        let book = BrainLatencyBook()
        let ids = ["ollama", "anthropic-api", "codex", "claude", "ollama"]
        // Nothing measured: the configured order stands.
        #expect(book.ordered(ids, id: { $0 }) == ids)
        book.record("anthropic-api", firstTokenMs: 600)
        book.record("ollama", firstTokenMs: 900)
        #expect(book.ordered(ids, id: { $0 }) == ["anthropic-api", "ollama", "codex", "claude", "ollama"])
    }

    @Test func aMissingLocalServerStopsTakingARaceSlot() {
        let book = BrainLatencyBook()
        book.recordFailure("ollama")
        let ordered = book.ordered(["ollama", "anthropic-api", "openai", "codex"], id: { $0 })
        #expect(Array(ordered.prefix(2)) == ["anthropic-api", "openai"])
        // CLI engines never jump ahead of HTTP ones.
        #expect(ordered.last == "codex")
    }

    @Test func theCLIOfTheSameNameIsNotReordered() {
        let book = BrainLatencyBook()
        book.record("anthropic-api", firstTokenMs: 100)
        let ids = ["anthropic-api", "ollama"]  // no server entry: "ollama" here is the CLI
        #expect(book.ordered(ids, id: { $0 }) == ids)
    }
}
