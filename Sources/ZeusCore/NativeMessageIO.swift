import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// An owned, nonblocking copy of a host stdio descriptor. Only its I/O queue closes it.
private final class NativeMessageDescriptor: @unchecked Sendable {
    let fd: Int32
    private var closed = false

    init(_ handle: FileHandle) throws {
        fd = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard fd >= 0 else { throw NativeMessageOutput.Failure.unavailable }
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            close(fd); throw NativeMessageOutput.Failure.unavailable
        }
        #if canImport(Darwin)
        guard fcntl(fd, F_SETNOSIGPIPE, 1) >= 0 else {
            close(fd); throw NativeMessageOutput.Failure.unavailable
        }
        #endif
    }

    func closeOnce() {
        guard !closed else { return }
        closed = true
        close(fd)
    }
}

/// Chrome's output pipe has one ordered writer, with admission before allocating a queued job.
/// A partial frame is terminal: later frames must never be appended to a corrupted byte stream.
public final class NativeMessageOutput: @unchecked Sendable {
    public enum Failure: Error, Equatable, Sendable { case closed, timedOut, unavailable }
    public enum Admission: Equatable, Sendable { case accepted, full, closed, tooLarge }
    public static let maximumQueuedFrames = 32
    public static let maximumQueuedBytes = 8 * 1024 * 1024

    private let descriptor: NativeMessageDescriptor
    private let queue = DispatchQueue(label: "zeus.bridge.output", qos: .utility)
    private let lock = NSLock()
    private let writeTimeout: TimeInterval
    private var terminal: Failure?
    private var finishing = false
    private var frames = 0
    private var bytes = 0

    public init(handle: FileHandle, writeTimeout: TimeInterval = 2) throws {
        guard writeTimeout.isFinite, writeTimeout > 0, writeTimeout <= 60 else { throw Failure.unavailable }
        self.writeTimeout = writeTimeout
        descriptor = try NativeMessageDescriptor(handle)
    }

    deinit { stop() }

    var queuedFrameCount: Int { lock.withLock { frames } }
    var queuedByteCount: Int { lock.withLock { bytes } }
    public var isOpen: Bool { lock.withLock { terminal == nil && !finishing } }

    /// `frame` includes its four-byte header. Completion is called exactly once for accepted work;
    /// rejected work never enters the queue and does not call completion.
    @discardableResult
    public func enqueue(_ frame: Data, completion: @escaping @Sendable (Result<Void, Failure>) -> Void) -> Admission {
        guard frame.count >= 4, frame.count <= NativeMessagingFrame.maxHostToChromeBytes + 4 else { return .tooLarge }
        let deadline = ProcessInfo.processInfo.systemUptime + writeTimeout
        return lock.withLock {
            guard terminal == nil, !finishing else { return .closed }
            guard frames < Self.maximumQueuedFrames, frame.count <= Self.maximumQueuedBytes - bytes else { return .full }
            frames += 1
            bytes += frame.count
            // Queue submission shares the admission lock, so finish cannot overtake accepted work.
            queue.async { [self] in performWrite(frame, deadline: deadline, completion: completion) }
            return .accepted
        }
    }

    private func performWrite(_ frame: Data, deadline: TimeInterval,
                              completion: @escaping @Sendable (Result<Void, Failure>) -> Void) {
        let result: Result<Void, Failure>
        do {
            try write(frame, deadline: deadline)
            result = .success(())
        } catch {
            let failure = error as? Failure ?? .unavailable
            stop(with: failure)
            result = .failure(failure)
        }
        lock.withLock { frames -= 1; bytes -= frame.count }
        completion(result)
    }

    /// Clean stdin EOF preserves already accepted responses. Reject new admission, then flush
    /// existing frames under their original deadlines before closing the output descriptor.
    @discardableResult
    public func finish(completion: @escaping @Sendable (Result<Void, Failure>) -> Void) -> Bool {
        lock.withLock {
            guard terminal == nil, !finishing else { return false }
            finishing = true
            queue.async { [self] in
                let result: Result<Void, Failure> = lock.withLock {
                    if let terminal { return .failure(terminal) }
                    terminal = .closed
                    return .success(())
                }
                descriptor.closeOnce()
                completion(result)
            }
            return true
        }
    }

    public func stop() { stop(with: .closed) }

    private func stop(with failure: Failure) {
        let first = lock.withLock { () -> Bool in
            guard terminal == nil else { return false }
            terminal = failure
            return true
        }
        if first {
            let descriptor = descriptor
            queue.async { descriptor.closeOnce() }
        }
    }

    private func write(_ data: Data, deadline: TimeInterval) throws {
        #if !canImport(Darwin)
        // Linux has no F_SETNOSIGPIPE for pipes. Mask only this worker, and consume only
        // a newly generated SIGPIPE before restoring its previous signal mask.
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
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                if let failure = lock.withLock({ terminal }) { throw failure }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.timedOut }
                var pollFD = pollfd(fd: descriptor.fd, events: Int16(POLLOUT), revents: 0)
                let ready = poll(&pollFD, 1, 25)
                if ready < 0 && errno == EINTR { continue }
                guard ready >= 0 else { throw Failure.unavailable }
                if ready == 0 { continue }
                guard pollFD.revents & Int16(POLLERR | POLLHUP | POLLNVAL) == 0 else { throw Failure.unavailable }
                #if canImport(Darwin)
                let written = Darwin.write(descriptor.fd, base.advanced(by: offset), min(16_384, raw.count - offset))
                #else
                let written = Glibc.write(descriptor.fd, base.advanced(by: offset), min(16_384, raw.count - offset))
                #endif
                if written > 0 { offset += written; continue }
                if written < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                throw Failure.unavailable
            }
        }
    }
}

/// Cancelable fixed-chunk stdin readiness. Idle input has no worker, polling timer or Task.
/// The serial consumer gets one chunk at a time and must not retain an unbounded stream of chunks.
public final class NativeMessageInput: @unchecked Sendable {
    public enum End: Equatable, Sendable { case eof, failed, stopped }
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var end: End?
        var started = false
        // Source/suspension are confined to the input queue.
        var source: DispatchSourceRead?
        var suspended = false
        var isStopped: Bool { lock.withLock { end != nil } }
    }
    private let state = State()
    private let descriptor: NativeMessageDescriptor
    private let queue = DispatchQueue(label: "zeus.bridge.input", qos: .utility)

    public init(handle: FileHandle) throws { descriptor = try NativeMessageDescriptor(handle) }
    deinit { stop() }

    @discardableResult
    public func start(consume: @escaping @Sendable (Data) throws -> Void,
                      ended: @escaping @Sendable (End) -> Void) -> Bool {
        let accepted = state.lock.withLock { () -> Bool in
            guard !state.started else { return false }
            state.started = true
            return true
        }
        guard accepted else { return false }
        queue.async { [self] in
            guard !state.isStopped else {
                descriptor.closeOnce()
                ended(state.lock.withLock { state.end ?? .stopped })
                return
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor.fd, queue: queue)
            let lifecycle = self.state, ownedDescriptor = self.descriptor
            lifecycle.source = source
            source.setCancelHandler {
                ownedDescriptor.closeOnce()
                ended(lifecycle.lock.withLock { lifecycle.end ?? .stopped })
            }
            source.setEventHandler { [weak self] in self?.readAvailable(consume: consume) }
            source.resume()
        }
        return true
    }

    public func stop() { stop(with: .stopped) }

    private func stop(with end: End) {
        let first = state.lock.withLock { () -> Bool in
            guard state.end == nil else { return false }
            state.end = end
            return true
        }
        guard first else { return }
        let lifecycle = self.state, ownedDescriptor = self.descriptor
        queue.async {
            if let source = lifecycle.source {
                source.cancel()
                if lifecycle.suspended { lifecycle.suspended = false; source.resume() }
                lifecycle.source = nil
            } else { ownedDescriptor.closeOnce() }
        }
    }

    private func readAvailable(consume: @escaping @Sendable (Data) throws -> Void) {
        guard !state.isStopped else { return }
        var bytes = [UInt8](repeating: 0, count: 16_384)
        var count: Int
        repeat {
            #if canImport(Darwin)
            count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            #else
            count = Glibc.read(descriptor.fd, &bytes, bytes.count)
            #endif
        } while count < 0 && errno == EINTR
        if count < 0 && errno == EAGAIN {
            if state.suspended { state.suspended = false; state.source?.resume() }
            return
        }
        guard count > 0 else { stop(with: count == 0 ? .eof : .failed); return }
        if !state.suspended { state.source?.suspend(); state.suspended = true }
        do { try consume(Data(bytes.prefix(count))) }
        catch { stop(with: .failed); return }
        // Probe again after yielding this queue. Data and EOF can share one readiness event.
        queue.async { [self] in readAvailable(consume: consume) }
    }
}
