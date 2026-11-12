import AppKit
import ZeusCore

/// QA runs `Zeus.app/Contents/MacOS/Zeus debug <subcommand>` directly (the app binary, not the
/// separate `zeus` CLI). Without this, `main.swift` falls straight through into a brand new
/// `AppDelegate`, spawning a second full Zeus. `DebugForward` recognises that one shape of
/// invocation and forwards it over the same Unix socket the `zeus` CLI uses, then exits: it must
/// never fall through to the normal app startup.
enum DebugForward {
    /// Pure: is this invocation a `debug` forward request? Exposed separately from
    /// `runIfRequested` so it is unit-testable without a process exit.
    static func isRequested(argv: [String]) -> Bool { argv.first == "debug" }

    /// Runs the forward and exits the process if `argv` (excluding the executable path) starts
    /// with `debug`. Returns false (and does nothing) otherwise, so callers can fall through.
    @discardableResult
    static func runIfRequested(argv: [String] = Array(CommandLine.arguments.dropFirst()),
                                socketPath: String = ZeusPaths.socket.path,
                                timeout: TimeInterval = 30) -> Bool {
        guard isRequested(argv: argv) else { return false }
        let rest = Array(argv.dropFirst())

        let invocation: ZeusCLIInvocation
        do {
            invocation = try ZeusCLI.parse(["debug"] + rest)
        } catch let error as ZeusCLIError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
        guard let command = invocation.command, let payload = try? JSONEncoder().encode(command) else {
            print(ZeusCLI.usage)
            exit(0)
        }
        guard let data = UnixSocket.request(path: socketPath, payload: payload, expectReply: true, timeout: timeout),
              !data.isEmpty else {
            FileHandle.standardError.write(Data("Zeus isn't running.\n".utf8))
            exit(3)
        }
        guard let reply = try? JSONDecoder().decode(ZeusCommandReply.self, from: data) else {
            FileHandle.standardError.write(Data("Zeus sent a reply this build can't read.\n".utf8))
            exit(1)
        }
        let text = ZeusCLI.render(reply, op: command.op)
        if !text.isEmpty { print(text) }
        exit(reply.ok ? 0 : 1)
    }
}

/// Pure decision for the single-instance guard: a second launch of `Zeus.app` should hand off to
/// the one already running (and quit itself) unless this launch needs its own process image
/// (snapshots, the settings/onboarding parity harnesses, the offline voice self-test).
enum InstanceGuard {
    static let exemptFlags: Set<String> = ["--snapshots", "--settings-only", "--onboarding-only", "--voice-selftest", "--voice-engine-selftest", "--engine-logos", "--render-film", "--pointing-selftest"]

    /// `argv` excludes the executable path. `others` are pids of other running instances of this
    /// app (excluding our own pid).
    static func shouldExit(argv: [String], others: [Int32]) -> Bool {
        guard !others.isEmpty else { return false }
        return !argv.contains { exemptFlags.contains($0) }
    }
}
