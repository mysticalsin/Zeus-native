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

    static let tools: [Tool] = CLIToolCatalog.tools.map { record in
        Tool(name: record.name, provider: record.provider, extraPaths: record.extraPaths)
    }

    static var searchDirectories: [String] {
        CLIToolCatalog.searchDirectories(
            home: FileManager.default.homeDirectoryForCurrentUser.path,
            pathEnvironment: ProcessInfo.processInfo.environment["PATH"] ?? ""
        )
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
                    .split(whereSeparator: \.isNewline).first
                    .map { CLIVersionLineBox.trimmedLine(String($0)) }
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
