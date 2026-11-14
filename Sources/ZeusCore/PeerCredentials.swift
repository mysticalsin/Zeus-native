import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Who is on the other end of a Unix socket connection, as the kernel reports it.
public struct PeerIdentity: Equatable, Sendable {
    public var uid: UInt32
    public var pid: Int32?
    public var executablePath: String?
    /// The kernel's audit token for the peer (32 bytes). Unlike a pid it cannot be reused by another
    /// process after the peer exits, so a signature read from it describes the process that connected.
    public var auditToken: Data?

    public init(uid: UInt32, pid: Int32? = nil, executablePath: String? = nil, auditToken: Data? = nil) {
        self.uid = uid
        self.pid = pid
        self.executablePath = executablePath
        self.auditToken = auditToken
    }
}

/// What a socket accepts. Mode 0600 on the socket file is not enough on its own (a stale or
/// inherited descriptor, a restored path), so every accepted connection is checked as well.
public enum PeerPolicy: Equatable, Sendable {
    /// The peer must run as the same user as the server.
    case sameUser
    /// Same user, and the peer's executable file name must be one of these (for example the app
    /// binary `Zeus` on the browser bridge socket). The name comes from the kernel's pid-to-path
    /// lookup, not from anything the peer sends. A file name is only a first filter: `UnixSocketServer`
    /// also requires the peer to be this app's own signed program (`PeerBinaryRule`).
    case sameUserExecutable(Set<String>)

    /// Whether the server must also verify the peer's code signature before it reads a byte.
    public var requiresSignedApp: Bool {
        switch self {
        case .sameUser: return false
        case .sameUserExecutable: return true
        }
    }
}

/// Reads and judges a peer's code signature from its audit token. Injected into the server so tests
/// need no real signed programs; the default is `PeerSigning.verifyApp`.
public typealias PeerVerifier = @Sendable (_ auditToken: Data?) -> PeerVerdict

/// What a handler may ask about the peer that sent it a line. The signature is read on the first
/// question and remembered, so a connection that never asks costs nothing.
public struct PeerContext: Sendable {
    private final class Memo: @unchecked Sendable {
        private let lock = NSLock()
        private var verdict: PeerVerdict?
        private let compute: @Sendable () -> PeerVerdict
        init(_ compute: @escaping @Sendable () -> PeerVerdict) { self.compute = compute }
        func value() -> PeerVerdict {
            lock.lock(); defer { lock.unlock() }
            if let verdict { return verdict }
            let result = compute()
            verdict = result
            return result
        }
    }

    private let memo: Memo

    public init(verify: @escaping @Sendable () -> PeerVerdict) { memo = Memo(verify) }

    /// Allowed only when the peer is this app's own signed program (for example the bundled `zeus` command).
    public func verifiedApp() -> PeerVerdict { memo.value() }
}

public enum PeerVerdict: Equatable, Sendable {
    case allow
    case deny(String)

    public var isAllowed: Bool { self == .allow }
}

public enum PeerCheck {
    /// Pure decision. A peer that could not be identified is always refused.
    public static func decide(_ policy: PeerPolicy, ownUID: UInt32, peer: PeerIdentity?) -> PeerVerdict {
        guard let peer else { return .deny("peer credentials unavailable") }
        guard peer.uid == ownUID else { return .deny("peer uid \(peer.uid) is not the owner") }
        switch policy {
        case .sameUser:
            return .allow
        case .sameUserExecutable(let names):
            guard let path = peer.executablePath, !path.isEmpty else { return .deny("peer executable unknown") }
            let name = (path as NSString).lastPathComponent
            return names.contains(name) ? .allow : .deny("peer executable \(name) is not allowed here")
        }
    }

    /// Reads the connected peer's uid (getpeereid, the LOCAL_PEERCRED data), pid (LOCAL_PEERPID)
    /// and executable path. Nil when the kernel will not say.
    public static func identify(fd: Int32) -> PeerIdentity? {
        #if canImport(Darwin)
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return nil }
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        var identity = PeerIdentity(uid: UInt32(uid))
        if getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 {
            identity.pid = Int32(pid)
            identity.executablePath = executablePath(pid: pid)
        }
        identity.auditToken = auditToken(fd: fd)
        return identity
        #else
        return nil
        #endif
    }

    #if canImport(Darwin)
    /// `LOCAL_PEERTOKEN` (sys/un.h): the connected peer's `audit_token_t`, eight 32-bit words.
    static func auditToken(fd: Int32) -> Data? {
        var token = [UInt32](repeating: 0, count: 8)
        var size = socklen_t(MemoryLayout<UInt32>.size * token.count)
        guard getsockopt(fd, SOL_LOCAL, 0x006, &token, &size) == 0, Int(size) == MemoryLayout<UInt32>.size * token.count else { return nil }
        return token.withUnsafeBytes { Data($0) }
    }

    static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    #endif
}

/// The browser bridge socket (`chrome.sock`) is served by `zeus-bridge`, which Chrome starts.
/// Its only legitimate client is the Zeus app itself. The program name below is a first filter; the
/// server then requires the peer's code signature to tie it to this app (`PeerBinaryRule`).
public enum ChromeSocketPeers {
    public static let allowedExecutables: Set<String> = ["Zeus"]

    /// The policy for this bridge process. A bridge started with `ZEUS_SUPPORT_DIR` set serves a
    /// relocated socket (tests, a second build) that the installed app never talks to, so only the
    /// same-user rule applies there. Whoever can set the bridge's environment can already move the socket.
    public static func policy(environment: [String: String]) -> PeerPolicy {
        if let override = environment["ZEUS_SUPPORT_DIR"], !override.isEmpty { return .sameUser }
        return .sameUserExecutable(allowedExecutables)
    }
}
