import Foundation

/// One CLI Zeus can launch. The app probes the disk. This record only names the tool.
public struct CLITool: Equatable, Sendable {
    public var name: String
    public var provider: ProviderID?
    /// Locations outside the normal bin folders, such as Codex bundled inside ChatGPT.app.
    public var extraPaths: [String]

    public init(name: String, provider: ProviderID?, extraPaths: [String]) {
        self.name = name
        self.provider = provider
        self.extraPaths = extraPaths
    }
}

/// The tool list and the folders searched before `PATH`.
public enum CLIToolCatalog {
    public static let tools: [CLITool] = [
        CLITool(name: "claude", provider: .claudeCLI, extraPaths: []),
        CLITool(name: "codex", provider: .codexCLI, extraPaths: [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        ]),
        CLITool(name: "gemini", provider: .geminiCLI, extraPaths: []),
        CLITool(name: "cursor-agent", provider: .cursorAgent, extraPaths: []),
        CLITool(name: "ollama", provider: .ollama, extraPaths: []),
        CLITool(name: "gh", provider: nil, extraPaths: []),
    ]

    /// Install folders checked before `PATH`. `home` is the current user's home directory.
    public static func commonDirectories(home: String) -> [String] {
        [
            "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.cargo/bin",
        ]
    }

    /// Common folders first, then each `PATH` entry once. An empty environment adds nothing.
    /// A folder that already appeared is kept at its first place.
    public static func searchDirectories(home: String, pathEnvironment: String) -> [String] {
        let fromEnvironment = pathEnvironment.split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (commonDirectories(home: home) + fromEnvironment).filter { seen.insert($0).inserted }
    }
}
