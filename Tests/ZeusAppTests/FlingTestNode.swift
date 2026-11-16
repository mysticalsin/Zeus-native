import Foundation
import Testing
import ZeusCore
import ZeusFling

/// One Mac in the room: a real endpoint over loopback with its own memory Keychain and temp folders.
final class Node: @unchecked Sendable {
    let id: String, name: String, root: URL
    let endpoint: FlingEndpoint
    private let lock = NSLock()
    private var log: [FlingEvent] = []

    init(_ name: String, parent: URL, hooks: FlingTestHooks = FlingTestHooks()) {
        self.name = name
        self.id = "id-\(name)-\(UUID().uuidString.prefix(6))"
        self.root = parent.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let keys = KeychainStore(backend: MemoryKeychain(), defaults: UserDefaults(suiteName: "zeus.fling-modes.\(UUID().uuidString)")!)
        endpoint = FlingEndpoint(identity: FlingIdentity(id: id, name: name, model: "Mac-test"), keys: keys,
                                 supportDirectory: root.appendingPathComponent("Support"), saveRoot: root,
                                 inbox: root.appendingPathComponent("Inbox"), discovery: .direct, hooks: hooks)
        let events = endpoint.events
        Task { [self] in for await event in events { lock.withLock { log.append(event) } } }
        endpoint.start()
    }

    var events: [FlingEvent] { lock.withLock { log } }

    func wait<T>(_ what: String, timeout: TimeInterval = 20, _ pick: @escaping (FlingEvent) -> T?) async -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let hit = events.lazy.compactMap(pick).first { return hit }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("\(name) never saw \(what)")
        return nil
    }

    /// The newest transfer port: the listener is rebuilt, on a new port, whenever the paired Macs change.
    func transferPort() async -> UInt16? {
        _ = await wait("a transfer port") { if case .listening(let port?, _) = $0 { return port } else { return nil } }
        return events.reversed().compactMap { if case .listening(let port?, _) = $0 { return port } else { return nil } }.first
    }
    func pairPort() async -> UInt16? { await wait("a pairing port") { if case .listening(_, let port?) = $0 { return port } else { return nil } } }
}

func pair(_ a: Node, _ b: Node) async -> UInt16? {
    guard let pairPort = await b.pairPort() else { return nil }
    a.endpoint.pair(with: .direct(port: nil, pairPort: pairPort))
    _ = await a.wait("a code") { if case .pairCode = $0 { return true } else { return nil } }
    _ = await b.wait("a code") { if case .pairCode = $0 { return true } else { return nil } }
    b.endpoint.answerPairing(accept: true, peerID: a.id)
    a.endpoint.answerPairing(accept: true, peerID: b.id)
    _ = await a.wait("paired") { if case .paired = $0 { return true } else { return nil } }
    _ = await b.wait("paired") { if case .paired = $0 { return true } else { return nil } }
    return await b.transferPort()
}

func listing(_ root: URL) -> [String] {
    let base = root.resolvingSymlinksInPath()
    let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
    return (e?.allObjects as? [URL] ?? []).map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: base.path, with: "") }.sorted()
}
