import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One owned descriptor and one serial I/O worker. Reads apply backpressure before
/// accepting the next chunk; writes never block the MCP actor or the main actor.
final class MCPPipeIO: @unchecked Sendable {
    enum Failure: Error, Sendable { case stopped, timedOut, unavailable }
    private let fd: Int32
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var stopped = false
    // These fields are confined to queue, including cancellation and fd closure.
    private var source: DispatchSourceRead?
    private var suspended = false
    private var descriptorClosed = false

    init(handle: FileHandle, name: String) throws {
        fd = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard fd >= 0 else { throw Failure.unavailable }
        queue = DispatchQueue(label: "zeus.mcp." + name, qos: .utility)
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) >= 0,
              fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) >= 0 else {
            close(fd); throw Failure.unavailable
        }
        #if canImport(Darwin)
        guard fcntl(fd, F_SETNOSIGPIPE, 1) >= 0 else { close(fd); throw Failure.unavailable }
        #endif
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    /// The descriptor closes on its worker after pending I/O notices cancellation.
    /// Closing it on the actor could let a reused fd be written by an older worker.
    func stop() {
        let first = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            stopped = true
            return true
        }
        if first {
            queue.async { [self] in
                if let source {
                    source.cancel()
                    if suspended { suspended = false; source.resume() }
                    self.source = nil
                } else { closeDescriptor() }
            }
        }
    }

    func write(_ data: Data, deadline: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try writeNow(data, deadline: deadline)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func writeNow(_ data: Data, deadline: TimeInterval) throws {
        // Darwin's descriptor flag suppresses SIGPIPE. Linux validation uses a
        // worker-local mask and consumes only a newly generated EPIPE signal.
        #if !canImport(Darwin)
        var mask = sigset_t(), oldMask = sigset_t(), pending = sigset_t()
        sigemptyset(&mask); sigaddset(&mask, SIGPIPE)
        guard pthread_sigmask(SIG_BLOCK, &mask, &oldMask) == 0 else { throw Failure.unavailable }
        sigpending(&pending)
        let alreadyPending = sigismember(&pending, SIGPIPE) == 1
        defer {
            if !alreadyPending {
                sigpending(&pending)
                if sigismember(&pending, SIGPIPE) == 1 {
                    var zero = timespec(tv_sec: 0, tv_nsec: 0)
                    _ = sigtimedwait(&mask, nil, &zero)
                }
            }
            pthread_sigmask(SIG_SETMASK, &oldMask, nil)
        }
        #endif
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                guard !isStopped else { throw Failure.stopped }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.timedOut }
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let ready = poll(&descriptor, 1, 25)
                if ready < 0 { if errno == EINTR { continue }; throw Failure.unavailable }
                if ready == 0 { continue }
                guard descriptor.revents & Int16(POLLERR | POLLHUP | POLLNVAL) == 0 else { throw Failure.unavailable }
                #if canImport(Darwin)
                let count = Darwin.write(fd, base.advanced(by: offset), min(16_384, bytes.count - offset))
                #else
                let count = Glibc.write(fd, base.advanced(by: offset), min(16_384, bytes.count - offset))
                #endif
                if count > 0 { offset += count; continue }
                if count < 0, errno == EINTR || errno == EAGAIN { continue }
                throw Failure.unavailable
            }
        }
    }

    private func closeDescriptor() {
        guard !descriptorClosed else { return }
        descriptorClosed = true
        close(fd)
    }

    /// At most one 16 KiB chunk awaits the actor. A noisy child blocks on its OS
    /// pipe. A dispatch source sleeps when idle; no polling timer/thread is kept alive.
    func read(consume: @escaping @Sendable (Data) async -> Bool,
              ended: @escaping @Sendable () async -> Void) {
        queue.async { [self] in
            guard !isStopped else { return }
            let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source = reader
            reader.setCancelHandler { [self] in
                closeDescriptor()
                Task { await ended() }
            }
            reader.setEventHandler { [weak self] in self?.readAvailable(consume: consume) }
            reader.resume()
        }
    }

    /// Read readiness may coalesce the last bytes and EOF into a single event. After
    /// every consumed chunk, probe the nonblocking fd again before resuming the source.
    /// Waiting for a second event can otherwise strand a truncated final message.
    private func readAvailable(consume: @escaping @Sendable (Data) async -> Bool) {
        guard !isStopped else { return }
        var bytes = [UInt8](repeating: 0, count: 16_384)
        var count: Int
        repeat {
            #if canImport(Darwin)
            count = Darwin.read(fd, &bytes, bytes.count)
            #else
            count = Glibc.read(fd, &bytes, bytes.count)
            #endif
        } while count < 0 && errno == EINTR
        if count < 0, errno == EAGAIN {
            if suspended { suspended = false; source?.resume() }
            return
        }
        guard count > 0 else { stop(); return }
        if !suspended { source?.suspend(); suspended = true }
        let data = Data(bytes.prefix(count))
        Task {
            let keepReading = await consume(data)
            queue.async { [self] in
                if keepReading { readAvailable(consume: consume) }
                else { stop() }
            }
        }
    }

}
