import Foundation
import ZeusCore

/// Runs an AI dictation mode through the person's own `claude` login (print mode, no tools).
/// Only used when the chosen mode has a prompt; plain Voice mode never leaves the Mac.
enum ClaudeRewriter {
    enum Failure: Error { case notInstalled, failed(String), timedOut }

    static func rewrite(_ prompt: String, timeout: TimeInterval = RewriterStream.timeout) async throws -> String {
        guard let tool = CLILocator.tools.first(where: { $0.name == "claude" }),
              let path = CLILocator.locate(tool) else { throw Failure.notInstalled }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
                do {
                    let collected = try RewriterStream.collect(stdout: output, stderr: errors, timeout: timeout) {
                        try process.run()
                        input.fileHandleForWriting.write(Data(prompt.utf8))
                        try? input.fileHandleForWriting.close()
                        do {
                            try RewriterStream.waitUntilStopped(isRunning: { process.isRunning }, timeout: timeout) {
                                process.terminate()
                            }
                        } catch {
                            throw Failure.timedOut
                        }
                    }
                    guard once.claim() else { return }
                    if process.terminationStatus == 0 {
                        let text = String(decoding: collected.stdout, as: UTF8.self)
                        continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        let message = String(decoding: collected.stderr, as: UTF8.self)
                        continuation.resume(throwing: Failure.failed(String(message.prefix(200))))
                    }
                } catch {
                    guard once.claim() else { return }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
