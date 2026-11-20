import Foundation

/// Reads a process's pipes while it is still running. Waiting until exit fills the pipe and the
/// process never finishes.
public enum RewriterStream {
    /// The rewrite budget. The caller kills the process at this many seconds.
    public static let timeout: TimeInterval = 45

    public struct Collected: Equatable, Sendable {
        public var stdout: Data
        public var stderr: Data
    }

    public enum Failure: Error { case timedOut }

    /// Starts the readers, then runs `body`. `body` closes both write ends, or the process does
    /// when it exits. A full pipe cannot stall the writer, because the readers are already going.
    public static func collect(stdout: Pipe, stderr: Pipe, timeout: TimeInterval = RewriterStream.timeout,
                                body: () throws -> Void) throws -> Collected {
        let out = Box()
        let err = Box()
        let readers = DispatchGroup()
        readers.enter()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            drain(stdout.fileHandleForReading, into: out)
            readers.leave()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            drain(stderr.fileHandleForReading, into: err)
            readers.leave()
        }
        do {
            try body()
        } catch {
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            _ = readers.wait(timeout: .now() + 1)
            throw error
        }
        if readers.wait(timeout: .now() + timeout) == .timedOut { throw Failure.timedOut }
        return Collected(stdout: out.data, stderr: err.data)
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
}
