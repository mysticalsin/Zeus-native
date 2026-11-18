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

    /// The path of the program behind an audit token (32 bytes). Unlike a pid lookup it refuses once the process
    /// that owned the token has exited, even when another process has taken its pid.
    static func executablePath(auditToken data: Data) -> String? {
        guard data.count == MemoryLayout<audit_token_t>.size else { return nil }
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { _ = data.copyBytes(to: $0) }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath_audittoken(&token, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    #endif
}

public struct SupportDirectoryFacts: Equatable, Sendable {
    public var isSymlink: Bool
    public var uid: UInt32
    /// Permission bits only (`st_mode & 0777`), not the file type.
    public var mode: UInt32

    public init(isSymlink: Bool, uid: UInt32, mode: UInt32) {
        self.isSymlink = isSymlink
        self.uid = uid
        self.mode = mode
    }
}

public enum SupportDirectoryRule {
    /// The override exists for tests and debug builds. A release build never honours it.
    public static var allowOverride: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Usable only when the override is allowed and `lstat` says this user owns a real directory at 0700.
    public static func accepted(path: String, allowOverride: Bool, uid: UInt32, facts: SupportDirectoryFacts?) -> String? {
        guard allowOverride, !path.isEmpty, let facts else { return nil }
        guard !facts.isSymlink, facts.uid == uid, (facts.mode & 0o777) == 0o700 else { return nil }
        return path
    }

    public static func facts(at path: String) -> SupportDirectoryFacts? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let type = info.st_mode & mode_t(S_IFMT)
        return SupportDirectoryFacts(isSymlink: type == mode_t(S_IFLNK), uid: info.st_uid, mode: UInt32(info.st_mode))
    }

    /// The relocated support directory, or nil when the override is absent, forbidden, or not a private directory.
    public static func resolved(environment: [String: String] = ProcessInfo.processInfo.environment,
                                allowOverride: Bool = SupportDirectoryRule.allowOverride,
                                uid: UInt32 = UInt32(geteuid())) -> String? {
        guard let path = environment["ZEUS_SUPPORT_DIR"], !path.isEmpty else { return nil }
        return accepted(path: path, allowOverride: allowOverride, uid: uid, facts: facts(at: path))
    }
}

/// The browser bridge socket (`chrome.sock`) is served by `zeus-bridge`, which Chrome starts.
/// Its only legitimate client is the Zeus app itself. The program name below is a first filter; the
/// server then requires the peer's code signature to tie it to this app (`PeerBinaryRule`).
public enum ChromeSocketPeers {
    public static let allowedExecutables: Set<String> = ["Zeus"]

    /// The signing identifier of the app: its bundle identifier. The bridge's only client carries it.
    public static let expectedPeerIdentifier = ZeusPaths.bundleIdentifier

    /// The verifier the bridge's socket uses: the peer must be this app's program and carry the app's identifier. The
    /// bridge alone also accepts the app bundle that ships a bridge of its name (an ad hoc development build).
    public static let verifier: PeerVerifier = { PeerSigning.verifyApp(auditToken: $0, expectedPeerIdentifier: expectedPeerIdentifier, trustShippingBundle: true) }

    /// The policy for this bridge process. A relocated support directory never turns the signature check off.
    /// Release builds ignore `ZEUS_SUPPORT_DIR` entirely; a debug build may use the path only after
    /// `SupportDirectoryRule` confirms it is this user's directory at mode 0700.
    public static func policy(environment: [String: String]) -> PeerPolicy {
        _ = environment
        return .sameUserExecutable(allowedExecutables)
    }
}
