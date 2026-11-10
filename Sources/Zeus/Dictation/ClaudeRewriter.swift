import Foundation
import ZeusCore

/// Runs an AI dictation mode through the person's own `claude` login (print mode, no tools).
/// Only used when the chosen mode has a prompt; plain Voice mode never leaves the Mac.
enum ClaudeRewriter {
    enum Failure: Error { case notInstalled, failed(String), timedOut }

    static func rewrite(_ prompt: String, timeout: TimeInterval = 45) async throws -> String {
        guard let tool = CLILocator.tools.first(where: { $0.name == "claude" }),
              let path = CLILocator.locate(tool) else { throw Failure.notInstalled }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ModelCap.arguments(for: .claude, tier: .fast)
                + ["-p", "--output-format", "text", "--disallowedTools", "Bash,Edit,Write,WebFetch,WebSearch"]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = (CLILocator.searchDirectories + ["/usr/bin", "/bin"]).joined(separator: ":")
            process.environment = environment
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            let input = Pipe(), output = Pipe(), errors = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            let once = OnceFlag()
            process.terminationHandler = { finished in
                let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                guard once.claim() else { return }
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    continuation.resume(throwing: Failure.failed(String(message.prefix(200))))
                }
            }
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(prompt.utf8))
                try? input.fileHandleForWriting.close()
            } catch {
                if once.claim() { continuation.resume(throwing: error) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard once.claim() else { return }
                process.terminate()
                continuation.resume(throwing: Failure.timedOut)
            }
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
