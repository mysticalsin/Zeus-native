import Foundation
import ZeusCore

/// Finds the AI and dev CLIs ZEUS can drive. An app launched from Finder gets a minimal PATH
/// (/usr/bin:/bin:/usr/sbin:/sbin), so the usual install locations are searched explicitly.
enum CLILocator {
    struct Tool: Sendable {
        let name: String
        let provider: ProviderID?
        /// Locations outside the normal bin folders, e.g. Codex bundled inside ChatGPT.app.
        let extraPaths: [String]
    }

    static let tools: [Tool] = [
        Tool(name: "claude", provider: .claudeCLI, extraPaths: []),
        Tool(name: "codex", provider: .codexCLI, extraPaths: [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        ]),
        Tool(name: "gemini", provider: .geminiCLI, extraPaths: []),
        Tool(name: "cursor-agent", provider: .cursorAgent, extraPaths: []),
        Tool(name: "ollama", provider: .ollama, extraPaths: []),
        Tool(name: "gh", provider: nil, extraPaths: []),
    ]

    static var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fromEnvironment = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let common = [
            "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.cargo/bin",
        ]
        var seen = Set<String>()
        return (common + fromEnvironment).filter { seen.insert($0).inserted }
    }

    static func locate(_ tool: Tool) -> String? {
        let candidates = searchDirectories.map { "\($0)/\(tool.name)" } + tool.extraPaths
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// First line of `<tool> --version`, or nil if it fails or takes longer than 5 s.
    static func version(at path: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--version"]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = searchDirectories.joined(separator: ":")
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            process.standardInput = FileHandle.nullDevice

            process.terminationHandler = { finished in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let firstLine = String(decoding: data, as: UTF8.self)
                    .split(whereSeparator: \.isNewline).first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces)
                continuation.resume(returning: finished.terminationStatus == 0 ? firstLine : nil)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
