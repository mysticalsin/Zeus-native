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

    public init(uid: UInt32, pid: Int32? = nil, executablePath: String? = nil) {
        self.uid = uid
        self.pid = pid
        self.executablePath = executablePath
    }
}

/// What a socket accepts. Mode 0600 on the socket file is not enough on its own (a stale or
/// inherited descriptor, a restored path), so every accepted connection is checked as well.
public enum PeerPolicy: Equatable, Sendable {
    /// The peer must run as the same user as the server.
    case sameUser
    /// Same user, and the peer's executable file name must be one of these (for example the app
    /// binary `Zeus` on the browser bridge socket). The name comes from the kernel's pid-to-path
    /// lookup, not from anything the peer sends.
    case sameUserExecutable(Set<String>)
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
        return identity
        #else
        return nil
        #endif
    }

    #if canImport(Darwin)
    static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    #endif
}

/// The browser bridge socket (`chrome.sock`) is served by `zeus-bridge`, which Chrome starts.
/// Its only legitimate client is the Zeus app itself.
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
