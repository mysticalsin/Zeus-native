import Foundation

/// Reads a process's pipes while it is still running. Waiting until exit fills the pipe and the
/// process never finishes.
public enum RewriterStream {
    /// The rewrite budget. The caller kills the process at this many seconds.
    public static let timeout: TimeInterval = 45
    /// How long the readers may finish after the body returns. This is not the process budget.
    public static let readerDrain: TimeInterval = 15

    public struct Collected: Equatable, Sendable {
        public var stdout: Data
        public var stderr: Data
    }

    public enum Failure: Error { case timedOut }

    /// Starts the readers, then runs `body`. `body` closes both write ends, or the process does
    /// when it exits. After `body` returns, the readers have `readerDrain` seconds, not `timeout`.
    public static func collect(stdout: Pipe, stderr: Pipe, timeout: TimeInterval = RewriterStream.timeout,
                                readerDrain: TimeInterval = RewriterStream.readerDrain,
                                body: () throws -> Void) throws -> Collected {
        _ = timeout
        let out = Box()
        let err = Box()
        let stdoutDone = Gate()
        let stderrDone = Gate()
        DispatchQueue.global(qos: .userInitiated).async {
            drain(stdout.fileHandleForReading, into: out)
            stdoutDone.mark()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            drain(stderr.fileHandleForReading, into: err)
            stderrDone.mark()
        }
        do {
            try body()
        } catch {
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            _ = bothDone(stdoutDone, stderrDone, within: readerDrain)
            throw error
        }
        if !bothDone(stdoutDone, stderrDone, within: readerDrain) { throw Failure.timedOut }
        return Collected(stdout: out.data, stderr: err.data)
    }

    /// The process budget, polled. `kill` runs once the budget is spent and the process is still up.
    public static func waitUntilStopped(isRunning: () -> Bool, timeout: TimeInterval, kill: () -> Void) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while isRunning(), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard isRunning() else { return }
        kill()
        let stopped = Date().addingTimeInterval(1)
        while isRunning(), Date() < stopped {
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw Failure.timedOut
    }

    private static func bothDone(_ first: Gate, _ second: Gate, within bound: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(bound)
        while Date() < deadline {
            if first.isOpen, second.isOpen { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return first.isOpen && second.isOpen
    }

    private static func drain(_ handle: FileHandle, into box: Box) {
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            box.append(chunk)
        }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        var data: Data { lock.withLock { storage } }
        func append(_ chunk: Data) { lock.withLock { storage.append(chunk) } }
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = false
        var isOpen: Bool { lock.withLock { open } }
        func mark() { lock.withLock { open = true } }
    }
}
