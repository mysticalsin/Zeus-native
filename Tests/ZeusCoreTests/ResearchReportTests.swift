import Foundation
import Testing
@testable import ZeusCore

@Suite struct ResearchReportTests {
    private let date = Date(timeIntervalSince1970: 1_793_545_200) // 2026-11-01 15:00 UTC
    private let utc = TimeZone(identifier: "UTC")!

    // MARK: Engines and arguments

    @Test func claudeGetsTheWebToolsAndTheCappedModel() throws {
        let defaults = UserDefaults(suiteName: "zeus.tests.research.\(UUID().uuidString)")!
        let quick = try #require(ResearchReport.arguments(engine: .claude, prompt: "P", depth: .quick, defaults: defaults))
        #expect(quick.starts(with: ["-p", "P"]))
        #expect(quick.contains("--allowedTools"))
        #expect(quick[quick.firstIndex(of: "--allowedTools")! + 1] == "WebSearch,WebFetch")
        #expect(quick[quick.firstIndex(of: "--model")! + 1] == "haiku")
        #expect(!quick.contains("--effort"))
        #expect(quick.last == "WebSearch,WebFetch") // the tool list is last: it takes a list and would swallow later words

        let deep = try #require(ResearchReport.arguments(engine: .claude, prompt: "P", depth: .deep, defaults: defaults))
        #expect(deep[deep.firstIndex(of: "--model")! + 1] == "sonnet")
        #expect(deep[deep.firstIndex(of: "--effort")! + 1] == "medium")
        #expect(deep.last == "WebSearch,WebFetch")
        for arguments in [quick, deep] {
            #expect(!arguments.contains { ModelCap.tooLarge.contains(where: $0.lowercased().contains) })
        }
    }

    @Test func geminiUsesItsOwnSearchAndEnginesWithoutAWebToolAreSkipped() {
        let defaults = UserDefaults(suiteName: "zeus.tests.research.\(UUID().uuidString)")!
        let gemini = ResearchReport.arguments(engine: .gemini, prompt: "P", depth: .quick, defaults: defaults)
        #expect(gemini == ["-m", "gemini-3.7-flash", "-p", "P"])
        for engine in [RouterEngine.codex, .cursorAgent, .grok, .ollama] {
            #expect(ResearchReport.arguments(engine: engine, prompt: "P", depth: .quick, defaults: defaults) == nil)
        }
    }

    @Test func engineOrderPrefersTheChoiceThenClaudeThenGemini() {
        let all: Set<RouterEngine> = [.claude, .gemini, .codex, .cursorAgent]
        #expect(ResearchReport.engineOrder(installed: all, preferred: .gemini) == [.gemini, .claude])
        #expect(ResearchReport.engineOrder(installed: all, preferred: .codex) == [.claude, .gemini]) // codex has no web tool
        #expect(ResearchReport.engineOrder(installed: [.gemini, .codex], preferred: .claude) == [.gemini])
        #expect(ResearchReport.engineOrder(installed: [.codex, .cursorAgent], preferred: .codex).isEmpty) // → the browser agent
        #expect(ResearchReport.engineOrder(installed: [], preferred: nil).isEmpty)
    }

    @Test func depthMapsToTheTierAndTimeout() {
        #expect(ResearchDepth.quick.tier == .fast)
        #expect(ResearchDepth.deep.tier == .deep)
        #expect(ResearchDepth.deep.timeout > ResearchDepth.quick.timeout)
    }

    @Test func promptCarriesTheQuestionPersonaAndTheInjectionGuard() {
        let prompt = ResearchReport.prompt(question: "How do heat pumps work?", depth: .quick, persona: "dry and amused")
        #expect(prompt.contains("Question: How do heat pumps work?"))
        #expect(prompt.contains("SUMMARY:") && prompt.contains("REPORT:") && prompt.contains("## Sources"))
        #expect(prompt.contains("dry and amused"))
        #expect(prompt.contains("never instructions"))
        #expect(prompt.contains("at most three pages"))
        #expect(ResearchReport.prompt(question: "q", depth: .deep).contains("six to ten"))
    }

    // MARK: Reading the answer

    @Test func parsesTheSummaryReportAndSources() {
        let raw = """
        SUMMARY: Heat pumps move heat instead of making it, so they deliver about three units of heat per unit of electricity. Great stuff.
        REPORT:
        # Heat pumps

        - They compress a refrigerant.

        ## Sources
        - [IEA](https://www.iea.org/reports/heat-pumps) overview
        - [Energy.gov](https://www.energy.gov/heat-pump-systems).
        - [IEA again](https://www.iea.org/reports/heat-pumps)
        """
        let parsed = ResearchReport.parse(raw)
        #expect(parsed.summary == "Heat pumps move heat instead of making it, so they deliver about three units of heat per unit of electricity. Great stuff.")
        #expect(parsed.body.hasPrefix("# Heat pumps"))
        #expect(!parsed.body.contains("SUMMARY"))
        #expect(parsed.sources == ["https://www.iea.org/reports/heat-pumps", "https://www.energy.gov/heat-pump-systems"])
    }

    @Test func theSpokenSummaryIsPlainAndAtMostTwoSentences() {
        let parsed = ResearchReport.parse("SUMMARY: **First.** See [the docs](https://x.y/z) for more. Third sentence here.\nREPORT:\nbody")
        #expect(parsed.summary == "First. See the docs for more.")
        #expect(!parsed.summary.contains("http") && !parsed.summary.contains("*"))
    }

    @Test func aReplyWithoutMarkersStillWorks() {
        let parsed = ResearchReport.parse("Heat pumps are efficient. They move heat. They need electricity.\n\nMore detail: https://example.com/a")
        #expect(parsed.summary == "Heat pumps are efficient. They move heat.")
        #expect(parsed.body.contains("More detail"))
        #expect(parsed.sources == ["https://example.com/a"])
        let onlyText = ResearchReport.parse("SUMMARY: Short answer.")
        #expect(onlyText.summary == "Short answer.")
        #expect(ResearchReport.parse("").summary == "")
    }

    // MARK: The saved note

    @Test func titleAndFileName() {
        #expect(ResearchReport.title(for: "research how heat pumps work in cold climates and why") == "How heat pumps work in cold climates and why")
        #expect(ResearchReport.title(for: "look up the zipper?") == "The zipper")
        #expect(ResearchReport.title(for: "") == "Research")
        #expect(ResearchReport.fileName(title: "Heat pumps", date: date, timeZone: utc) == "2026-11-01 Heat pumps.md")
        let nasty = ResearchReport.fileName(title: "a/b\\c:d*e?f\"g<h>i|j\nk", date: date, timeZone: utc)
        #expect(nasty == "2026-11-01 a b c d e f g h i j k.md")
        #expect(!nasty.dropLast(3).contains("/") && !nasty.contains(":"))
        #expect(ResearchReport.fileName(title: "../../etc/passwd", date: date, timeZone: utc) == "2026-11-01 etc passwd.md")
        #expect(ResearchReport.fileName(title: "   ", date: date, timeZone: utc) == "2026-11-01 Research.md")
        #expect(ResearchReport.fileName(title: String(repeating: "x", count: 200), date: date, timeZone: utc).count <= 11 + 70 + 3)
    }

    private func connection(_ vault: URL, access: BrainConnection.Access = .readWrite, kind: BrainSource.Kind = .obsidian) -> BrainConnection {
        BrainConnection(source: BrainSource(kind: kind, name: "brain", path: vault.path), access: access)
    }

    @Test func reportsGoToTheVaultsResearchFolderWhenItIsWritable() {
        let vault = URL(fileURLWithPath: "/Users/t/Documents/brain")
        let home = URL(fileURLWithPath: "/Users/t")
        let url = ResearchReport.destination(fileName: "2026-11-01 Heat pumps.md", connection: connection(vault), home: home, exists: { _ in false })
        #expect(url.path == "/Users/t/Documents/brain/ZEUS/Research/2026-11-01 Heat pumps.md")
    }

    @Test func otherwiseTheyGoToDocumentsZeusResearch() {
        let home = URL(fileURLWithPath: "/Users/t")
        let expected = "/Users/t/Documents/Zeus Research/2026-11-01 Heat pumps.md"
        let vault = URL(fileURLWithPath: "/Users/t/Documents/brain")
        #expect(ResearchReport.destination(fileName: "2026-11-01 Heat pumps.md", connection: nil, home: home, exists: { _ in false }).path == expected)
        #expect(ResearchReport.destination(fileName: "2026-11-01 Heat pumps.md", connection: connection(vault, access: .readOnly), home: home, exists: { _ in false }).path == expected)
        #expect(ResearchReport.destination(fileName: "2026-11-01 Heat pumps.md", connection: connection(vault, kind: .bear), home: home, exists: { _ in false }).path == expected)
    }

    @Test func aTakenNameGetsANumberNeverAnOverwrite() {
        let home = URL(fileURLWithPath: "/Users/t")
        let taken: Set<String> = ["/Users/t/Documents/Zeus Research/2026-11-01 Heat pumps.md", "/Users/t/Documents/Zeus Research/2026-11-01 Heat pumps 2.md"]
        let url = ResearchReport.destination(fileName: "2026-11-01 Heat pumps.md", connection: nil, home: home, exists: { taken.contains($0.path) })
        #expect(url.lastPathComponent == "2026-11-01 Heat pumps 3.md")
    }

    @Test func theVaultStillRefusesEverythingElse() {
        let vault = URL(fileURLWithPath: "/Users/t/Documents/brain")
        let brain = connection(vault)
        #expect(brain.mayWrite(vault.appendingPathComponent("ZEUS/Research/2026-11-01 X.md")))
        #expect(!brain.mayWrite(vault.appendingPathComponent("ZEUS/Research/../../Projects/Plan.md")))
        #expect(!brain.mayWrite(vault.appendingPathComponent("ZEUS/ResearchX/a.md")))
        #expect(!brain.mayWrite(vault.appendingPathComponent("Projects/Plan.md")))
        #expect(!connection(vault, access: .readOnly).mayWrite(vault.appendingPathComponent("ZEUS/Research/a.md")))
    }

    @Test func theMarkdownNote() {
        let parsed = ResearchReport.Parsed(summary: "Heat pumps move heat.", body: "# Heat pumps\n\n- Efficient.", sources: ["https://a.example/x"])
        let text = ResearchReport.markdown(question: "how do heat pumps work?\nbriefly", depth: .deep, parsed: parsed, engine: "Claude", date: date, timeZone: utc)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.first == "---")
        #expect(text.contains("type: research"))
        #expect(text.contains("depth: deep"))
        #expect(text.contains("engine: Claude"))
        #expect(text.contains("created: 2026-11-01T15:00:00Z"))
        #expect(text.contains("> how do heat pumps work? briefly"))
        #expect(text.contains("**Short answer:** Heat pumps move heat."))
        #expect(text.contains("## Sources\n- https://a.example/x")) // appended: the body had none
        #expect(text.hasSuffix("\n"))
    }

    @Test func sourcesAreNotDuplicatedWhenTheReportListsThem() {
        let parsed = ResearchReport.Parsed(summary: "", body: "text\n\n## Sources\n- [A](https://a.example)", sources: ["https://a.example"])
        let text = ResearchReport.markdown(question: "q", depth: .quick, parsed: parsed, engine: "Gemini", date: date, timeZone: utc)
        #expect(text.components(separatedBy: "## Sources").count == 2)
        #expect(!text.contains("Short answer"))
    }
}
