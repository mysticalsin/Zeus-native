import Foundation
import Testing
@testable import ZeusCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Peer checks for the agent socket (`zeus.sock`) and the browser bridge socket (`chrome.sock`).
/// Disposable AF_UNIX sockets only: no app, no network, no permissions.
@Suite("Socket peer credentials", .serialized)
struct PeerCredentialsTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    @Test func sameUserPolicyAllowsOnlyTheOwner() {
        #expect(PeerCheck.decide(.sameUser, ownUID: 501, peer: PeerIdentity(uid: 501, executablePath: "/usr/local/bin/zeus")) == .allow)
        #expect(PeerCheck.decide(.sameUser, ownUID: 501, peer: PeerIdentity(uid: 0)).isAllowed == false)
        #expect(PeerCheck.decide(.sameUser, ownUID: 501, peer: PeerIdentity(uid: 502)).isAllowed == false)
    }

    @Test func anUnidentifiedPeerIsAlwaysRefused() {
        #expect(PeerCheck.decide(.sameUser, ownUID: 501, peer: nil).isAllowed == false)
        #expect(PeerCheck.decide(.sameUserExecutable(["Zeus"]), ownUID: 501, peer: nil).isAllowed == false)
    }

    @Test func bridgePolicyNeedsTheSameUserAndTheNamedProgram() {
        let policy = PeerPolicy.sameUserExecutable(ChromeSocketPeers.allowedExecutables)
        let app = PeerIdentity(uid: 501, pid: 10, executablePath: "/Applications/Zeus.app/Contents/MacOS/Zeus")
        #expect(PeerCheck.decide(policy, ownUID: 501, peer: app) == .allow)
        let otherUser = PeerIdentity(uid: 0, pid: 10, executablePath: "/Applications/Zeus.app/Contents/MacOS/Zeus")
        #expect(PeerCheck.decide(policy, ownUID: 501, peer: otherUser).isAllowed == false)
        let script = PeerIdentity(uid: 501, pid: 11, executablePath: "/usr/bin/python3")
        #expect(PeerCheck.decide(policy, ownUID: 501, peer: script).isAllowed == false)
        let unknownPath = PeerIdentity(uid: 501, pid: 12, executablePath: nil)
        #expect(PeerCheck.decide(policy, ownUID: 501, peer: unknownPath).isAllowed == false)
        let lookalike = PeerIdentity(uid: 501, pid: 13, executablePath: "/tmp/Zeus/evil")
        #expect(PeerCheck.decide(policy, ownUID: 501, peer: lookalike).isAllowed == false, "only the file name counts, not a folder")
    }

    @Test func aRelocatedSupportFolderIsTheOnlyWayToDropTheProgramNameRule() {
        #expect(ChromeSocketPeers.policy(environment: [:]) == .sameUserExecutable(ChromeSocketPeers.allowedExecutables))
        #expect(ChromeSocketPeers.policy(environment: ["ZEUS_SUPPORT_DIR": ""]) == .sameUserExecutable(ChromeSocketPeers.allowedExecutables))
        #expect(ChromeSocketPeers.policy(environment: ["ZEUS_SUPPORT_DIR": "/tmp/zeus-test"]) == .sameUser)
    }

    @Test func theKernelReportsThisProcessForAConnectedPair() throws {
        var pair: [Int32] = [0, 0]
        #if canImport(Darwin)
        let stream = SOCK_STREAM
        #else
        let stream = Int32(SOCK_STREAM.rawValue)
        #endif
        try #require(socketpair(AF_UNIX, stream, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        let peer = try #require(PeerCheck.identify(fd: pair[0]))
        #expect(peer.uid == UInt32(geteuid()))
        #expect(PeerCheck.decide(.sameUser, ownUID: UInt32(geteuid()), peer: peer) == .allow)
    }

    @Test func aServerRefusesAPeerThatTheDecisionRejects() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-peer-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("p.sock").path
        let handled = Counter()
        let server = UnixSocketServer(path: path, peerPolicy: .sameUserExecutable(["definitely-not-this-test-binary"])) { _, reply in
            handled.bump()
            reply(Data("{}".utf8))
        }
        try server.start()
        defer { server.stop() }
        let reply = await Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 2) }.value
        #expect(reply == nil)
        #expect(handled.value == 0, "the handler never sees a refused peer's bytes")
    }

    @Test func aServerAcceptsTheOwnerUnderTheDefaultPolicy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-peer-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("q.sock").path
        let server = UnixSocketServer(path: path) { _, reply in reply(Data("{\"ok\":true}".utf8)) }
        try server.start()
        defer { server.stop() }
        let reply = await Task.detached { UnixSocket.request(path: path, payload: Data("{}".utf8), expectReply: true, timeout: 2) }.value
        #expect(reply == Data("{\"ok\":true}".utf8))
    }

    /// The path this process is running. Read here, not through `PeerCheck`, so a stand-in such as `/bin/sh` fails.
    private func thisExecutable() -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        #if canImport(Darwin)
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        #else
        let length = readlink("/proc/self/exe", &buffer, buffer.count)
        guard length > 0, length < buffer.count else { return nil }
        #endif
        let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return path.isEmpty ? nil : path
    }

    @Test func executablePathPinsThisProcessAndRejectsOtherPrograms() throws {
        let expected = try #require(thisExecutable())
        let reported = try #require(PeerCheck.executablePath(pid: getpid()))
        #expect(reported == expected)
        for other in ["/bin/sh", "/bin/bash", "/usr/bin/false", expected + " (deleted)"] {
            #expect(reported != other)
        }
        var pair = [Int32](repeating: 0, count: 2)
        #if canImport(Darwin)
        let stream = SOCK_STREAM
        #else
        let stream = Int32(SOCK_STREAM.rawValue)
        #endif
        try #require(socketpair(AF_UNIX, stream, 0, &pair) == 0)
        defer { close(pair[0]); close(pair[1]) }
        let peer = try #require(PeerCheck.identify(fd: pair[0]))
        #expect(peer.executablePath == expected)
        #expect(peer.executablePath != "/bin/sh")
    }

    @Test func aMissingExecutableIsRefusedForTheSameUser() {
        let unread = PeerIdentity(uid: 501, pid: 4242, executablePath: nil)
        #expect(!PeerCheck.decide(.sameUser, ownUID: 501, peer: unread).isAllowed)
        let empty = PeerIdentity(uid: 501, pid: 4242, executablePath: "")
        #expect(!PeerCheck.decide(.sameUser, ownUID: 501, peer: empty).isAllowed)
    }

    @Test func aDeletedExecutableIsRefusedForTheSameUser() throws {
        let removed = PeerIdentity(uid: 501, executablePath: "/tmp/zeus-peer (deleted)")
        #expect(!PeerCheck.decide(.sameUser, ownUID: 501, peer: removed).isAllowed)
        #if !canImport(Darwin)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-del-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ["/bin/sleep", "/usr/bin/sleep"].first { FileManager.default.isExecutableFile(atPath: $0) }
        let copy = root.appendingPathComponent("peer-sleep")
        try FileManager.default.copyItem(atPath: try #require(source), toPath: copy.path)
        let process = Process()
        process.executableURL = copy
        process.arguments = ["30"]
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        try FileManager.default.removeItem(at: copy)
        #expect(PeerCheck.executablePath(pid: process.processIdentifier) == nil)
        #endif
    }
}
