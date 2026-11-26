import Testing
@testable import ZeusCore

@Suite("CLI tool catalog")
struct CLIToolCatalogTests {
    @Test func toolsStayInTheFinderSearchOrder() {
        #expect(CLIToolCatalog.tools.map(\.name) == [
            "claude", "codex", "gemini", "cursor-agent", "ollama", "gh",
        ])
        #expect(CLIToolCatalog.tools.map(\.provider) == [
            .claudeCLI, .codexCLI, .geminiCLI, .cursorAgent, .ollama, nil,
        ])
    }

    @Test func onlyCodexCarriesAPathOutsideTheBinFolders() {
        let extras = CLIToolCatalog.tools.map(\.extraPaths)
        #expect(extras == [
            [],
            ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"],
            [], [], [], [],
        ])
    }

    @Test func commonFoldersLeadAndARepeatedPathIsKeptOnce() {
        let home = "/Users/example"
        let directories = CLIToolCatalog.searchDirectories(
            home: home,
            pathEnvironment: "/usr/local/bin:/opt/custom/bin:/opt/custom/bin"
        )
        #expect(directories == [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "/opt/custom/bin",
        ])
    }

    @Test func anEmptyPathAddsNothing() {
        let home = "/Users/example"
        #expect(CLIToolCatalog.searchDirectories(home: home, pathEnvironment: "") == CLIToolCatalog.commonDirectories(home: home))
    }
}
