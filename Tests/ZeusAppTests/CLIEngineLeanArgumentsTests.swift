import Testing
@testable import Zeus
import ZeusCore

/// A spoken turn's race launches `claude` through the generic CLI route. Without the lean flags it loaded
/// the owner's MCP servers, hooks and plugins on every turn (qdrant and Playwright started first) and missed
/// the 8 s first-text budget every time: "No AI answered in time" on the owner's Mac.
@Suite struct CLIEngineLeanArgumentsTests {
    private let lean = ["--safe-mode", "--strict-mcp-config", "--tools", "", "--no-session-persistence"]

    @Test func aSpokenClaudeTurnRunsLean() {
        let arguments = CLIEngineProvider.stdinArguments(engine: .claude, localModel: "x", tier: .fast, lean: true, claudeLean: lean)
        #expect(arguments.starts(with: ModelCap.arguments(for: .claude, tier: .fast) + ["-p"]))
        #expect(Array(arguments.suffix(lean.count)) == lean)
    }

    @Test func aWrittenClaudeTurnKeepsTheOwnersSetup() {
        let arguments = CLIEngineProvider.stdinArguments(engine: .claude, localModel: "x", tier: .fast, lean: false, claudeLean: lean)
        #expect(!arguments.contains("--safe-mode"))
    }

    @Test func theLeanFlagsAreTheDedicatedClaudePathsSpokenFlags() {
        #expect(CLIEngineProvider.claudeLeanArguments(voice: true) == ClaudeCLIProvider.leanArguments(voice: true))
    }
}
