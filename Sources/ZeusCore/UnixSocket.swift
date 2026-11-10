import Darwin
import Foundation

/// Newline-delimited JSON over a Unix domain socket: one request (and optional reply) per connection.
public enum UnixSocket {
    static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }

    static func setTimeout(_ fd: Int32, option: Int32, seconds: TimeInterval) {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written <= 0 { return false }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }

    /// Reads until a newline or EOF (or the socket's receive timeout).
    static func readLine(_ fd: Int32, limit: Int = 4 * 1024 * 1024) -> Data? {
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while result.count < limit {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            if let newline = chunk[0..<count].firstIndex(of: 0x0A) {
                result.append(contentsOf: chunk[0..<newline])
                return result
            }
            result.append(contentsOf: chunk[0..<count])
        }
        return result.isEmpty ? nil : result
    }

    /// Sends one line. Returns the reply line when `expectReply`, or nil on any failure
    /// (no app listening, timeout). Never throws: callers fall back to their default behaviour.
    public static func request(path: String, payload: Data, expectReply: Bool, timeout: TimeInterval) -> Data? {
        guard var address = address(for: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        setTimeout(fd, option: SO_SNDTIMEO, seconds: 1)

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        guard writeAll(fd, payload + Data([0x0A])) else { return nil }
        guard expectReply else { return Data() }
        setTimeout(fd, option: SO_RCVTIMEO, seconds: timeout)
        return readLine(fd)
    }
}

/// Accepts connections on a background thread and hands each request line to `handler`.
/// The handler must call `reply` exactly once (nil = close without replying).
public final class UnixSocketServer: @unchecked Sendable {
    public typealias Reply = @Sendable (Data?) -> Void
    public typealias Handler = @Sendable (Data, @escaping Reply) -> Void

    private let path: String
    private let handler: Handler
    private var listenFD: Int32 = -1

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        unlink(path)

        guard var address = UnixSocket.address(for: path) else { throw POSIXError(.ENAMETOOLONG) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        chmod(path, 0o600) // only this user's processes may talk to ZEUS
        listenFD = fd

        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "zeus.socket.accept"
        thread.start()
    }

    public func stop() {
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return // listening socket closed
            }
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            UnixSocket.setTimeout(client, option: SO_RCVTIMEO, seconds: 2)
            DispatchQueue.global(qos: .userInitiated).async { [handler] in
                guard let line = UnixSocket.readLine(client) else {
                    close(client)
                    return
                }
                handler(line) { reply in
                    if let reply { _ = UnixSocket.writeAll(client, reply + Data([0x0A])) }
                    close(client)
                }
            }
        }
    }
}
