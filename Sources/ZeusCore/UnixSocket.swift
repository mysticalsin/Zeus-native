import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Newline-delimited JSON over a Unix domain socket: one request (and optional reply) per connection.
public enum UnixSocket {
    static let maximumMessageBytes = 4 * 1024 * 1024
    static let maximumIdentifierBytes = 256
    static let requestReadTimeout: TimeInterval = 2
    static let replyWriteTimeout: TimeInterval = 1

    static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.contains(0), bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }

    static func makeSocket() -> Int32 {
        #if canImport(Darwin)
        socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
    }

    /// Each operation has one monotonic deadline, rather than a timeout restarted by every byte.
    static func prepare(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
              fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { return false }
        #if canImport(Darwin)
        var noSigPipe: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return false }
        #endif
        return true
    }

    private static func deadline(after seconds: TimeInterval) -> UInt64? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        return DispatchTime.now().uptimeNanoseconds + UInt64(min(seconds, 86_400) * 1_000_000_000)
    }

    private static func wait(_ fd: Int32, for event: Int16, until deadline: UInt64) -> Bool {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return false }
            let milliseconds = min((deadline - now + 999_999) / 1_000_000, UInt64(Int32.max))
            var descriptor = pollfd(fd: fd, events: event, revents: 0)
            let result = poll(&descriptor, 1, Int32(milliseconds))
            if result < 0 && errno == EINTR { continue }
            guard result > 0, descriptor.revents & Int16(POLLNVAL) == 0 else { return false }
            // HUP may have a final readable payload. The next read/send decides EOF/error.
            return descriptor.revents & (event | Int16(POLLHUP) | Int16(POLLERR)) != 0
        }
    }

    static func writeAll(_ fd: Int32, _ data: Data, timeout: TimeInterval = replyWriteTimeout) -> Bool {
        guard data.count <= maximumMessageBytes + 1, let deadline = deadline(after: timeout) else { return false }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                guard DispatchTime.now().uptimeNanoseconds < deadline else { return false }
                #if canImport(Darwin)
                let written = send(fd, base.advanced(by: offset), raw.count - offset, 0)
                #else
                let written = send(fd, base.advanced(by: offset), raw.count - offset, Int32(MSG_NOSIGNAL))
                #endif
                if written > 0 { offset += written; continue }
                if written < 0 && errno == EINTR { continue }
                if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK), wait(fd, for: Int16(POLLOUT), until: deadline) { continue }
                return false
            }
            return true
        }
    }

    /// How reading one line ended.
    enum LineRead: Equatable {
        case line(Data)
        /// The other end closed or reset before a line arrived.
        case closed
        case timedOut
        /// An unusable limit or timeout, or a line over the limit.
        case failed
    }

    /// Accept a complete line or clean EOF only. Oversize and timed-out partial messages
    /// never reach a handler, even if their current prefix happens to be valid JSON.
    static func readLine(_ fd: Int32, limit: Int = maximumMessageBytes,
                         timeout: TimeInterval = requestReadTimeout) -> Data? {
        if case .line(let line) = readLineOutcome(fd, limit: limit, timeout: timeout) { return line }
        return nil
    }

    /// `readLine`, saying how a read that gave nothing ended.
    static func readLineOutcome(_ fd: Int32, limit: Int = maximumMessageBytes,
                                timeout: TimeInterval = requestReadTimeout) -> LineRead {
        guard limit > 0, limit <= maximumMessageBytes, let deadline = deadline(after: timeout) else { return .failed }
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { return .timedOut }
            let count = recv(fd, &chunk, chunk.count, 0)
            if count == 0 { return result.isEmpty ? .closed : .line(result) }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    if wait(fd, for: Int16(POLLIN), until: deadline) { continue }
                    return .timedOut
                }
                return .closed
            }
            let newline = chunk[0..<count].firstIndex(of: 0x0A)
            let length = newline ?? count
            guard length <= limit - result.count else { return .failed }
            result.append(contentsOf: chunk[0..<length])
            if newline != nil { return .line(result) }
        }
    }

    /// Correlation IDs are echoed by command/hook/bridge handlers. Bound them before dispatch;
    /// the raw-line echo API remains available to generic local transport users.
    static func boundedMessage(_ data: Data) -> Bool {
        guard data.count <= maximumMessageBytes else { return false }
        struct Identifier: Decodable { let id: String? }
        guard let value = try? JSONDecoder().decode(Identifier.self, from: data), let id = value.id else { return true }
        return id.utf8.count <= maximumIdentifierBytes
    }

    /// A connected, non-blocking socket to `path`, or nil. The caller closes it.
    static func connectedSocket(to path: String) -> Int32? {
        guard var address = address(for: path) else { return nil }
        let fd = makeSocket()
        guard fd >= 0 else { return nil }
        guard prepare(fd), let connectDeadline = deadline(after: 1) else { close(fd); return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if connected != 0 {
            guard errno == EINPROGRESS, wait(fd, for: Int16(POLLOUT), until: connectDeadline) else { close(fd); return nil }
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { close(fd); return nil }
        }
        return fd
    }

    /// Sends one line. Returns nil on connect/write/read failure. No capture or permission API runs.
    public static func request(path: String, payload: Data, expectReply: Bool, timeout: TimeInterval) -> Data? {
        guard boundedMessage(payload), let fd = connectedSocket(to: path) else { return nil }
        defer { close(fd) }
        guard writeAll(fd, payload + Data([0x0A])) else { return nil }
        guard expectReply else { return Data() }
        guard let reply = readLine(fd, timeout: timeout), boundedMessage(reply) else { return nil }
        return reply
    }

    /// How a request that wanted a reply ended.
    public enum Outcome: Equatable, Sendable {
        /// Nothing to connect to, or the payload could not be sent at all.
        case notConnected
        /// Connected and sent, and no line came within the bound.
        case timedOut
        /// Connected, then the other end closed or reset first, a write failed, or the reply was unusable. A peer
        /// that refuses this program closes its connection without writing, which looks the same.
        case closedEarly
        case reply(Data)
    }

    /// `request` with a reply, saying how a failure happened. It shares `request`'s connect, write and read steps,
    /// so both keep the same bounds.
    public static func exchange(path: String, payload: Data, timeout: TimeInterval) -> Outcome {
        guard boundedMessage(payload), let fd = connectedSocket(to: path) else { return .notConnected }
        defer { close(fd) }
        guard writeAll(fd, payload + Data([0x0A])) else { return .closedEarly }
        switch readLineOutcome(fd, timeout: timeout) {
        case .line(let reply): return boundedMessage(reply) ? .reply(reply) : .closedEarly
        case .timedOut: return .timedOut
        case .closed, .failed: return .closedEarly
        }
    }
}

/// Accepts a bounded number of local connections. Handlers may retain a reply during long CLI
/// tasks or approvals. Calling a reply is always nonblocking, including from MainActor. Only
/// the first call can write, and every connection descriptor closes exactly once.
public final class UnixSocketServer: @unchecked Sendable {
    public typealias Reply = @Sendable (Data?) -> Void
    public typealias Handler = @Sendable (Data, @escaping Reply) -> Void
    /// Like `Handler`, plus what the handler may ask about the peer that sent the line.
    public typealias ContextHandler = @Sendable (Data, PeerContext, @escaping Reply) -> Void
    static let maximumConnections = 32

    private let path: String
    private let peerPolicy: PeerPolicy
    private let peerVerifier: PeerVerifier
    private let handler: ContextHandler
    private let lock = NSLock()
    private let acceptQueue = DispatchQueue(label: "zeus.socket.accept")
    private var listener: DispatchSourceRead?
    private var listenFD: Int32 = -1
    private var connections: [UUID: Connection] = [:]
    /// dev/inode of the socket created by a successful bind. A later file at the same path is left alone.
    private var boundDevice: UInt64?
    private var boundInode: UInt64?
    /// Test hook. Called after bind and before chmod/listen. Return false to take the failure path.
    nonisolated(unsafe) static let rejectListenLock = NSLock()
    nonisolated(unsafe) static var rejectListenAfterBind: (@Sendable (String) -> Bool)?

    var activeConnectionCount: Int { lock.withLock { connections.count } }

    public init(path: String, peerPolicy: PeerPolicy = .sameUser, peerVerifier: @escaping PeerVerifier = PeerSigning.defaultVerifier,
                handler: @escaping Handler) {
        self.path = path
        self.peerPolicy = peerPolicy
        self.peerVerifier = peerVerifier
        self.handler = { line, _, reply in handler(line, reply) }
    }

    public init(path: String, peerPolicy: PeerPolicy = .sameUser, peerVerifier: @escaping PeerVerifier = PeerSigning.defaultVerifier,
                contextHandler: @escaping ContextHandler) {
        self.path = path
        self.peerPolicy = peerPolicy
        self.peerVerifier = peerVerifier
        self.handler = contextHandler
    }

    deinit { stop() }

    public func start() throws {
        try lock.withLock {
            guard listener == nil else { throw POSIXError(.EALREADY) }
            guard var address = UnixSocket.address(for: path) else { throw POSIXError(.ENAMETOOLONG) }
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            var existing = stat()
            if lstat(path, &existing) == 0 {
                guard (existing.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK), existing.st_uid == geteuid() else { throw POSIXError(.EEXIST) }
                guard unlink(path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            } else if errno != ENOENT { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let fd = UnixSocket.makeSocket()
            guard fd >= 0 else { throw POSIXError(.EIO) }
            var started = false
            defer { if !started { close(fd) } }
            guard UnixSocket.prepare(fd) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let listenAccepted = Self.rejectListenLock.withLock { Self.rejectListenAfterBind?(path) ?? true }
            guard listenAccepted, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
                unlink(path)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
            source.setEventHandler { [weak self] in self?.acceptAvailable(fd) }
            source.setCancelHandler { close(fd) }
            listener = source
            listenFD = fd
            started = true
            rememberBoundNode()
            source.resume()
        }
    }

    /// `lstat` of the socket we just bound. A symlink is not recorded, so finish cannot follow it.
    private func rememberBoundNode() {
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK) else {
            boundDevice = nil
            boundInode = nil
            return
        }
        boundDevice = UInt64(info.st_dev)
        boundInode = UInt64(info.st_ino)
    }

    /// Unlink only the inode from a successful bind. A replacement or a symlink stays.
    private func unlinkIfStillBound() {
        guard let boundDevice, let boundInode else { return }
        var info = stat()
        guard lstat(path, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK),
              UInt64(info.st_dev) == boundDevice,
              UInt64(info.st_ino) == boundInode else { return }
        unlink(path)
        self.boundDevice = nil
        self.boundInode = nil
    }

    public func stop() {
        let active = lock.withLock { () -> [Connection] in
            if let listener {
                self.listener = nil
                listenFD = -1
                listener.cancel()
                unlinkIfStillBound()
            }
            return Array(connections.values)
        }
        active.forEach { $0.cancel() }
    }

    private func acceptAvailable(_ fd: Int32) {
        while lock.withLock({ listenFD == fd }) {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            guard UnixSocket.prepare(client) else { close(client); continue }
            // Refuse before any byte is read: only the owner (and, where set, the named program) may talk.
            let peer = PeerCheck.identify(fd: client)
            let verdict = PeerCheck.decide(peerPolicy, ownUID: UInt32(geteuid()), peer: peer)
            if case .deny(let reason) = verdict {
                NSLog("[ZEUS] socket %@: connection refused (%@, pid %d)", (path as NSString).lastPathComponent, reason, peer?.pid ?? -1)
                close(client)
                continue
            }
            let verifier = peerVerifier, token = peer?.auditToken
            let context = PeerContext { verifier(token) }
            let id = UUID()
            let connection = Connection(fd: client, context: context) { [weak self] in
                guard let self else { return }
                _ = self.lock.withLock { self.connections.removeValue(forKey: id) }
            }
            let admitted = lock.withLock { () -> Bool in
                guard listenFD == fd, connections.count < Self.maximumConnections else { return false }
                connections[id] = connection
                return true
            }
            guard admitted else { connection.cancel(); continue }
            guard peerPolicy.requiresSignedApp else { connection.receive(handler); continue }
            // A program that must be this app's own is judged by its signature too, since a file name proves nothing.
            // The check reads the peer's code and can be slow, so it runs per connection off the accept queue: one slow
            // check never holds up another accept. The connection is already counted against the limit and reads
            // nothing until the check allows it.
            let name = (path as NSString).lastPathComponent, pid = peer?.pid ?? -1, handler = self.handler
            DispatchQueue.global(qos: .userInitiated).async {
                if case .deny(let reason) = verifier(token) {
                    NSLog("[ZEUS] socket %@: connection refused (%@, pid %d)", name, reason, pid)
                    connection.cancel()
                    return
                }
                connection.receive(handler)
            }
        }
    }

    private final class Connection: @unchecked Sendable {
        private enum State { case reading, waiting, writing, closed }
        private let fd: Int32
        private let context: PeerContext
        private let lock = NSLock()
        private let onClose: @Sendable () -> Void
        private var state = State.waiting
        private var cancelled = false

        init(fd: Int32, context: PeerContext, onClose: @escaping @Sendable () -> Void) {
            self.fd = fd
            self.context = context
            self.onClose = onClose
        }

        func receive(_ handler: @escaping ContextHandler) {
            let start = lock.withLock { () -> Bool in
                guard !cancelled, state == .waiting else { return false }
                state = .reading
                return true
            }
            guard start else { return }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                guard let line = UnixSocket.readLine(fd), UnixSocket.boundedMessage(line) else { finish(); return }
                let deliver = lock.withLock { () -> Bool in
                    guard !cancelled, state == .reading else { return false }
                    state = .waiting
                    return true
                }
                guard deliver else { finish(); return }
                handler(line, context) { [self] in reply($0) }
            }
        }

        func reply(_ data: Data?) {
            let claimed = lock.withLock { () -> Bool in
                guard !cancelled, state == .waiting else { return false }
                state = .writing
                return true
            }
            guard claimed else { return }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { finish() }
                if let data, UnixSocket.boundedMessage(data) { _ = UnixSocket.writeAll(fd, data + Data([0x0A])) }
            }
        }

        func cancel() {
            let closeIdle = lock.withLock { () -> Bool in
                guard state != .closed else { return false }
                cancelled = true
                _ = shutdown(fd, Int32(SHUT_RDWR))
                return state == .waiting
            }
            if closeIdle { finish() }
            // Reading/writing workers own the fd until their interrupted I/O returns.
        }

        private func finish() {
            let closed = lock.withLock { () -> Bool in
                guard state != .closed else { return false }
                state = .closed
                close(fd)
                return true
            }
            if closed { onClose() }
        }
    }
}
