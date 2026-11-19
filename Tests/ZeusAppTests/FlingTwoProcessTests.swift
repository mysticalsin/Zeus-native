import CryptoKit
import Foundation
import Testing
@testable import ZeusCore

/// Two or three real `zeus-fling-peer` processes talk over loopback TLS with a pre-shared key. Each has its own
/// save root and its own in-memory Keychain, so nothing here touches the real Downloads folder or Keychain.
private final class PeerProcess: @unchecked Sendable {
    let name: String
    let root: URL
    let id: String
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let condition = NSCondition()
    private var lines: [[String: Any]] = []
    private var buffer = Data()

    init(name: String, parent: URL, extraArguments: [String] = []) throws {
        self.name = name
        self.id = "id-" + name.replacingOccurrences(of: " ", with: "-") + "-" + UUID().uuidString.prefix(8)
        self.root = parent.appendingPathComponent(name.replacingOccurrences(of: " ", with: "-"), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        process.executableURL = try Self.helperURL()
        process.arguments = ["--name", name, "--id", id, "--root", root.path] + extraArguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self?.ingest(data)
        }
        try process.run()
    }

    static func helperURL() throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["ZEUS_FLING_PEER"] { candidates.append(URL(fileURLWithPath: env)) }
        // Next to the test bundle, which is where `swift build` puts every product.
        candidates.append(Bundle(for: PeerProcess.self).bundleURL.deletingLastPathComponent().appendingPathComponent("zeus-fling-peer"))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(root.appendingPathComponent(".build/debug/zeus-fling-peer"))
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) { return found }
        throw PeerError.missingHelper(candidates.map(\.path))
    }

    enum PeerError: Error, CustomStringConvertible {
        case missingHelper([String]), timeout(String, String)
        var description: String {
            switch self {
            case .missingHelper(let paths): return "zeus-fling-peer is missing. Run `swift build --product zeus-fling-peer` or set ZEUS_FLING_PEER. Looked in: \(paths)"
            case .timeout(let who, let what): return "\(who) never printed \(what)"
            }
        }
    }

    private func ingest(_ data: Data) {
        condition.lock(); defer { condition.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { lines.append(object) }
        }
        condition.broadcast()
    }

    func command(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    /// How many events have been printed so far; pass it to `wait(from:)` to ignore older ones.
    var mark: Int { condition.lock(); defer { condition.unlock() }; return lines.count }
    func events(named name: String, from: Int = 0) -> [[String: Any]] {
        condition.lock(); defer { condition.unlock() }
        return lines.dropFirst(from).filter { $0["event"] as? String == name }
    }

    @discardableResult
    func wait(for event: String, from: Int = 0, timeout: TimeInterval = 30, where match: ([String: Any]) -> Bool = { _ in true }) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock(); defer { condition.unlock() }
        while true {
            if let hit = lines.dropFirst(from).first(where: { $0["event"] as? String == event && match($0) }) { return hit }
            if !condition.wait(until: deadline) { throw PeerError.timeout(name, event) }
        }
    }

    func quit() {
        command(["cmd": "quit"])
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        output.fileHandleForReading.readabilityHandler = nil
    }
}

private struct Rig {
    let parent: URL
    let a: PeerProcess
    let b: PeerProcess
    var bPort = 0
    var bPairPort = 0

    static func make() throws -> Rig {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("fling-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let a = try PeerProcess(name: "Mac A", parent: parent)
        let b = try PeerProcess(name: "Mac B", parent: parent)
        return Rig(parent: parent, a: a, b: b)
    }

    /// Pairs A with B and returns B's transfer port, which changes because B rebuilds its listener with the new key.
    mutating func pair() throws {
        let listening = try b.wait(for: "listening")
        bPairPort = listening["pairPort"] as! Int
        try a.wait(for: "listening")
        let markA = a.mark, markB = b.mark
        a.command(["cmd": "pair", "host": "127.0.0.1", "pairPort": bPairPort])
        let codeB = try b.wait(for: "pairCode", from: markB)
        let codeA = try a.wait(for: "pairCode", from: markA)
        #expect(codeA["code"] as? String == codeB["code"] as? String)
        let code = try #require(codeA["code"] as? String)
        #expect(code.count == 6 && code.allSatisfy(\.isNumber))
        b.command(["cmd": "answerPairing", "accept": true])
        a.command(["cmd": "answerPairing", "accept": true])
        try a.wait(for: "paired", from: markA)
        try b.wait(for: "paired", from: markB)
        let rebuilt = try b.wait(for: "listening", from: markB)
        bPort = rebuilt["port"] as! Int
    }

    func stop() {
        a.quit(); b.quit()
        try? FileManager.default.removeItem(at: parent)
    }
}

private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func randomData(_ count: Int) -> Data {
    var data = Data(count: count)
    _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
    return data
}
@Suite("Fling two processes", .serialized, .timeLimit(.minutes(2)))
struct FlingTwoProcessTests {
    private func write(_ data: Data, _ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// REG-685: pair with a code, send four items including 50 MB, and every hash and the Shelf record match.
    @Test func pairsWithACodeAndSendsFourItemsIncludingFiftyMegabytes() throws {
        var rig = try Rig.make(); defer { rig.stop() }
        try rig.pair()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + randomData(4000)
        let mov = randomData(2048)
        let big = randomData(50 * 1024 * 1024)
        let src = rig.parent.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let items: [[String: Any]] = [
            ["path": try write(png, "photo.png", in: src).path],
            ["path": try write(mov, "clip.mov", in: src).path],
            ["link": "https://example.com"],
            ["path": try write(big, "big.bin", in: src).path],
        ]
        let markA = rig.a.mark, markB = rig.b.mark
        rig.a.command(["cmd": "send", "host": "127.0.0.1", "port": rig.bPort, "items": items])
        let done = try rig.a.wait(for: "sendDone", from: markA, timeout: 60)
        let stackID = try #require(done["stackID"] as? String)
        var got: [String: [String: Any]] = [:]
        let deadline = Date().addingTimeInterval(30)
        while got.count < 4 && Date() < deadline {
            for e in rig.b.events(named: "itemVerified", from: markB) { got[e["name"] as! String] = e }
            if got.count < 4 { Thread.sleep(forTimeInterval: 0.1) }
        }
        #expect(got.count == 4, "itemVerified events: \(got.keys.sorted())")
        #expect(got["photo.png"]?["sha256"] as? String == sha(png))
        #expect(got["clip.mov"]?["sha256"] as? String == sha(mov))
        #expect(got["big.bin"]?["sha256"] as? String == sha(big))
        #expect(got["example.com.webloc"]?["sha256"] as? String == sha(Data("https://example.com".utf8)))
        let folders = try FileManager.default.contentsOfDirectory(at: rig.b.root.appendingPathComponent("Fling"), includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        #expect(folders.count == 1)
        let folder = try #require(folders.first)
        #expect(folder.lastPathComponent.hasPrefix("Mac A "))
        #expect(try Data(contentsOf: folder.appendingPathComponent("photo.png")) == png)
        #expect(try Data(contentsOf: folder.appendingPathComponent("big.bin")) == big)
        let webloc = try Data(contentsOf: folder.appendingPathComponent("example.com.webloc"))
        let plist = try PropertyListSerialization.propertyList(from: webloc, format: nil) as? [String: String]
        #expect(plist?["URL"] == "https://example.com")
        #expect(listing(rig.b.root).allSatisfy { !$0.contains(".fling-partial-") })

        let loaded = FlingShelfPersistence(url: rig.b.root.appendingPathComponent("Shelf/shelf.json")).load()
        #expect(!loaded.unreadable && loaded.records.count == 4)
        #expect(loaded.records.allSatisfy { $0.origin == .fling(peer: "Mac A") && $0.verified && $0.stackID?.uuidString.lowercased() == stackID.lowercased() })
        #expect(loaded.records.filter { $0.link == "https://example.com" }.count == 1)
    }

    /// REG-673 and REG-686: a Mac that was never paired is stopped at the TLS handshake, and the open pairing port answers an offer with notPaired.
    @Test func anUnpairedMacIsRejectedAtTheHandshakeAndAtThePairingPort() throws {
        var rig = try Rig.make(); defer { rig.stop() }
        try rig.pair()
        let c = try PeerProcess(name: "Mac C", parent: rig.parent); defer { c.quit() }
        try c.wait(for: "listening")
        let before = listing(rig.b.root)
        let file = try write(randomData(1024), "x.bin", in: rig.parent)

        // With no key for B, C refuses to send at all.
        var markC = c.mark
        c.command(["cmd": "send", "host": "127.0.0.1", "port": rig.bPort, "peerID": rig.b.id, "items": [["path": file.path]]])
        let local = try c.wait(for: "failed", from: markC)
        #expect(local["reason"] as? String == "notPaired")

        // With a made-up key (a helper-only switch), the attempt reaches B and the TLS handshake fails there.
        markC = c.mark; let markB = rig.b.mark
        c.command(["cmd": "send", "host": "127.0.0.1", "port": rig.bPort, "peerID": rig.b.id, "forceUnknownKey": true, "items": [["path": file.path]]])
        let rejected = try rig.b.wait(for: "rejected", from: markB)
        #expect(rejected["reason"] as? String == "notPaired" && rejected["via"] as? String == "tls")
        let failed = try c.wait(for: "failed", from: markC)
        #expect(failed["reason"] as? String != nil)

        // The pairing port takes pairing frames only.
        markC = c.mark
        let markB2 = rig.b.mark
        c.command(["cmd": "probe", "host": "127.0.0.1", "pairPort": rig.bPairPort])
        let probe = try c.wait(for: "probeResult", from: markC)
        #expect(probe["reason"] as? String == "notPaired")
        let viaPairing = try rig.b.wait(for: "rejected", from: markB2) { $0["via"] as? String == "pairing" }
        #expect(viaPairing["reason"] as? String == "notPaired")
        #expect(listing(rig.b.root) == before)
    }

    /// REG-687: a name that climbs out of the stack folder declines the whole offer and writes nothing.
    @Test func aTraversalNameIsDeclinedAndWritesNothing() throws {
        var rig = try Rig.make(); defer { rig.stop() }
        try rig.pair()
        let file = try write(randomData(512), "ok.txt", in: rig.parent)
        let before = listing(rig.parent)
        let markA = rig.a.mark, markB = rig.b.mark
        rig.a.command(["cmd": "send", "host": "127.0.0.1", "port": rig.bPort, "rawName": "../evil.txt", "items": [["path": file.path]]])
        let onA = try rig.a.wait(for: "declined", from: markA)
        #expect(onA["reason"] as? String == "badName")
        let onB = try rig.b.wait(for: "declined", from: markB)
        #expect(onB["reason"] as? String == "badName")
        #expect(rig.b.events(named: "itemVerified", from: markB).isEmpty)
        #expect(listing(rig.parent) == before)
        #expect(!FileManager.default.fileExists(atPath: rig.parent.appendingPathComponent("evil.txt").path))
        #expect(!FileManager.default.fileExists(atPath: rig.b.root.appendingPathComponent("evil.txt").path))
    }

    /// REG-688: a cancelled send leaves no final or partial file, and the next send works.
    @Test func cancellingMidwayLeavesNothingAndTheNextSendSucceeds() throws {
        var rig = try Rig.make(); defer { rig.stop() }
        try rig.pair()
        let big = try write(randomData(50 * 1024 * 1024), "big.bin", in: rig.parent)
        let markA = rig.a.mark, markB = rig.b.mark
        rig.a.command(["cmd": "send", "host": "127.0.0.1", "port": rig.bPort, "chunkDelayMs": 20, "items": [["path": big.path]]])
        let progress = try rig.b.wait(for: "progress", from: markB, timeout: 30) {
            (($0["done"] as? Double) ?? 0) >= 0.1 * (($0["total"] as? Double) ?? .infinity)
        }
        let stackID = try #require(progress["stackID"] as? String)
        rig.a.command(["cmd": "cancel", "stackID": stackID])
        let onA = try rig.a.wait(for: "cancelled", from: markA)
        #expect(onA["stackID"] as? String == stackID)
        try rig.b.wait(for: "cancelled", from: markB)
        Thread.sleep(forTimeInterval: 0.3)
        #expect(listing(rig.b.root).allSatisfy { !$0.contains("big.bin") && !$0.contains(".fling-partial-") })
        #expect(rig.b.events(named: "itemVerified", from: markB).isEmpty)

        let small = try write(randomData(2048), "after.bin", in: rig.parent)
        let markA2 = rig.a.mark, markB2 = rig.b.mark
        rig.a.command(["cmd": "send", "host": "127.0.0.1", "port": rig.bPort, "chunkDelayMs": 0, "items": [["path": small.path]]])
        try rig.a.wait(for: "sendDone", from: markA2)
        try rig.b.wait(for: "itemVerified", from: markB2) { $0["name"] as? String == "after.bin" }
    }

    /// REG-688: one flipped byte in transit fails the hash, deletes the partial file and tells both sides.
    @Test func aCorruptedByteIsCaughtByTheHash() throws {
        var rig = try Rig.make(); defer { rig.stop() }
        try rig.pair()
        let file = try write(randomData(300_000), "c.bin", in: rig.parent)
        let markA = rig.a.mark, markB = rig.b.mark
        rig.a.command(["cmd": "send", "host": "127.0.0.1", "port": rig.bPort, "corruptByte": true, "items": [["path": file.path]]])
        let onB = try rig.b.wait(for: "failed", from: markB)
        #expect(onB["reason"] as? String == "hashMismatch")
        let onA = try rig.a.wait(for: "failed", from: markA)
        #expect(onA["reason"] as? String == "hashMismatch")
        Thread.sleep(forTimeInterval: 0.3)
        #expect(listing(rig.b.root).allSatisfy { !$0.contains("c.bin") && !$0.contains(".fling-partial-") })
        #expect(rig.b.events(named: "itemVerified", from: markB).isEmpty)
    }

    /// REG-770: the Mac that started the pairing can decline too, and then neither side keeps a key.
    @Test func theStartingMacCanDeclineAndNeitherSideStoresAKey() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("fling-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let a = try PeerProcess(name: "Mac A", parent: parent), b = try PeerProcess(name: "Mac B", parent: parent)
        defer { a.quit(); b.quit(); try? FileManager.default.removeItem(at: parent) }
        let pairPort = try b.wait(for: "listening")["pairPort"] as! Int
        try a.wait(for: "listening")
        let markA = a.mark, markB = b.mark
        a.command(["cmd": "pair", "host": "127.0.0.1", "pairPort": pairPort])
        try b.wait(for: "pairCode", from: markB); try a.wait(for: "pairCode", from: markA)
        b.command(["cmd": "answerPairing", "accept": true])
        Thread.sleep(forTimeInterval: 0.3)
        a.command(["cmd": "answerPairing", "accept": false])
        try a.wait(for: "pairEnded", from: markA)
        try b.wait(for: "pairEnded", from: markB)
        Thread.sleep(forTimeInterval: 0.4)
        #expect(a.events(named: "paired", from: markA).isEmpty && b.events(named: "paired", from: markB).isEmpty)
        // With no key the starting Mac cannot send at all.
        let file = parent.appendingPathComponent("x.bin"); try Data(count: 100).write(to: file)
        let markA2 = a.mark
        a.command(["cmd": "send", "host": "127.0.0.1", "port": 1, "peerID": b.id, "items": [["path": file.path]]])
        #expect(try a.wait(for: "failed", from: markA2)["reason"] as? String == "notPaired")
    }

    /// REG-772: a paired Mac that claims another paired Mac's id in its hello is turned away, and that other Mac still works.
    @Test func aPairedMacClaimingAnotherPairedMacsIdIsRejected() throws {
        var rig = try Rig.make(); defer { rig.stop() }
        try rig.pair()
        let c = try PeerProcess(name: "Mac C", parent: rig.parent); defer { c.quit() }
        try c.wait(for: "listening")
        let markC = c.mark, markB = rig.b.mark
        c.command(["cmd": "pair", "host": "127.0.0.1", "pairPort": rig.bPairPort])
        try rig.b.wait(for: "pairCode", from: markB); try c.wait(for: "pairCode", from: markC)
        rig.b.command(["cmd": "answerPairing", "accept": true]); c.command(["cmd": "answerPairing", "accept": true])
        try c.wait(for: "paired", from: markC); try rig.b.wait(for: "paired", from: markB)
        let port = try rig.b.wait(for: "listening", from: markB)["port"] as! Int
        let file = rig.parent.appendingPathComponent("spoof.bin"); try Data(count: 2000).write(to: file)
        let markA = rig.a.mark, markB2 = rig.b.mark
        rig.a.command(["cmd": "send", "host": "127.0.0.1", "port": port, "spoofID": c.id, "items": [["path": file.path]]])
        let rejected = try rig.b.wait(for: "rejected", from: markB2)
        #expect(rejected["reason"] as? String == "idMismatch")
        try rig.a.wait(for: "failed", from: markA)
        #expect(rig.b.events(named: "itemVerified", from: markB2).isEmpty)
        // The Mac whose id was claimed still sends normally.
        let markC2 = c.mark
        c.command(["cmd": "send", "host": "127.0.0.1", "port": port, "items": [["path": file.path]]])
        try c.wait(for: "sendDone", from: markC2)
    }
}
