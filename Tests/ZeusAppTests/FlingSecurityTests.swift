import CoreServices
import Foundation
import Network
import Testing
import ZeusCore
import ZeusFling
@testable import Zeus

/// Fixes from the independent security review: real endpoints over loopback, one test per finding.
@Suite("Fling security round", .serialized, .timeLimit(.minutes(3)))
struct FlingSecurityTests {
    private func parent() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fling-sec-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func write(_ bytes: Int, _ name: String, in dir: URL) -> URL {
        let url = dir.appendingPathComponent(name)
        try? Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    /// REG-739: eight connections that never speak lock out neither transfers nor, once they time out, pairing.
    @Test func eightSilentPairingConnectionsBlockNeitherTransfersNorLaterPairing() async throws {
        let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = Node("Alpha", parent: dir), b = Node("Beta", parent: dir)
        defer { a.endpoint.stop(); b.endpoint.stop() }
        let port = try #require(await pair(a, b))
        let pairPort = try #require(await b.pairPort())
        let queue = DispatchQueue(label: "silent")
        let silent = (0..<8).map { _ -> NWConnection in
            let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: pairPort)!, using: { let p = NWParameters.tcp; p.requiredInterfaceType = .loopback; return p }())
            c.start(queue: queue); return c
        }
        defer { silent.forEach { $0.cancel() } }
        try await Task.sleep(nanoseconds: 400_000_000)
        let file = write(1000, "during.bin", in: dir)
        a.endpoint.send([.file(file)], to: .direct(id: b.id, port: port, pairPort: nil))
        _ = try #require(await b.wait("a transfer while pairing is flooded") { if case .itemArrived(_, _, let n, _, _, _, _) = $0, n == "during.bin" { return true } else { return nil } })
        // After the handshake timeout the silent connections are gone and a new Mac can pair.
        try await Task.sleep(nanoseconds: 11_000_000_000)
        let c = Node("Gamma", parent: dir); defer { c.endpoint.stop() }
        #expect(await pair(c, b) != nil)
    }

    /// REG-740: bytes promised to a stack that is still arriving count against the free space of the next offer.
    @Test func bytesReservedByARunningStackCountAgainstTheNextOffer() async throws {
        let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
        let slow = FlingTestHooks(); slow.chunkDelayMs = 700
        let a = Node("Alpha", parent: dir, hooks: slow), c = Node("Gamma", parent: dir)
        let hooks = FlingTestHooks(); hooks.freeBytes = FlingLimits.freeSpaceReserveBytes + 1_200_000
        let b = Node("Beta", parent: dir, hooks: hooks)
        defer { a.endpoint.stop(); b.endpoint.stop(); c.endpoint.stop() }
        let portA = try #require(await pair(a, b))
        _ = portA
        let port = try #require(await pair(c, b))
        let big = write(700_000, "one.bin", in: dir), big2 = write(700_000, "two.bin", in: dir)
        let latest = try #require(await b.transferPort())
        _ = port
        a.endpoint.send([.file(big)], to: .direct(id: b.id, port: latest, pairPort: nil))
        _ = try #require(await b.wait("the first stack under way") { if case .progress(_, .receive, _, _) = $0 { return true } else { return nil } })
        c.endpoint.send([.file(big2)], to: .direct(id: b.id, port: latest, pairPort: nil))
        let reason = await b.wait("a refusal for the second stack") { if case .declined(_, .receive, let r) = $0 { return r } else { return nil } }
        #expect(reason == .diskFull)
        _ = try #require(await b.wait("the first stack done") { if case .stackFinished(_, .receive) = $0 { return true } else { return nil } })
        // The reservation is released, so the same offer now fits.
        c.endpoint.send([.file(big2)], to: .direct(id: b.id, port: latest, pairPort: nil))
        _ = try #require(await b.wait("the second stack") { if case .itemArrived(_, _, let n, _, _, _, _) = $0, n == "two.bin" { return true } else { return nil } })
    }

    /// REG-741: stopping an endpoint ends every transfer with an event, so nothing hangs on a progress ring.
    @Test func stoppingAnEndpointCancelsItsTransfersWithEvents() async throws {
        for stopTheReceiver in [true, false] {
            let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
            let slow = FlingTestHooks(); slow.chunkDelayMs = 400
            let a = Node("Alpha", parent: dir, hooks: slow), b = Node("Beta", parent: dir)
            defer { a.endpoint.stop(); b.endpoint.stop() }
            let port = try #require(await pair(a, b))
            a.endpoint.send([.file(write(1_200_000, "slow.bin", in: dir))], to: .direct(id: b.id, port: port, pairPort: nil))
            _ = try #require(await b.wait("progress") { if case .progress(_, .receive, _, _) = $0 { return true } else { return nil } })
            if stopTheReceiver {
                b.endpoint.stop()
                _ = try #require(await b.wait("a cancelled receive") { if case .cancelled(_, .receive) = $0 { return true } else { return nil } })
            } else {
                a.endpoint.stop()
                _ = try #require(await a.wait("a cancelled send") { if case .cancelled(_, .send) = $0 { return true } else { return nil } })
            }
        }
    }

    /// REG-742: typing a device name rebuilds the listeners once, not on every keystroke.
    @Test func aDeviceNameTypedQuicklyRebuildsTheListenersOnce() async throws {
        let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
        let count = Counter()
        let hooks = FlingTestHooks(); hooks.diagnostics = { if $0.hasPrefix("listeners rebuilt") { count.bump() } }
        let b = Node("Beta", parent: dir, hooks: hooks)
        defer { b.endpoint.stop() }
        _ = await b.pairPort()
        let before = count.value
        for name in ["N", "Ne", "New", "New ", "New n", "New na", "New nam", "New name"] {
            var s = FlingEndpointSettings(); s.deviceName = name
            b.endpoint.updateSettings(s)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(count.value - before <= 1, "rebuilds: \(count.value - before)")
        #expect(count.value - before == 1, "and the last name is applied")
    }

    /// REG-743: an id that is already paired is refused at the hello on both sides and its key is untouched.
    @Test func anAlreadyPairedMacIsRefusedAndKeepsItsKey() async throws {
        let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = Node("Alpha", parent: dir), b = Node("Beta", parent: dir)
        defer { a.endpoint.stop(); b.endpoint.stop() }
        _ = try #require(await pair(a, b))
        let stamp = b.endpoint.pairedPeers.first?.pairedAt
        let pairPort = try #require(await b.pairPort())
        let markA = a.events.count
        a.endpoint.pair(with: .direct(port: nil, pairPort: pairPort))
        let ended = await a.wait("a refusal on the starting Mac") { e -> Bool? in
            if case .pairEnded(.failed(.alreadyPaired)) = e { return true } else { return nil } }
        #expect(ended == true)
        #expect(a.events.dropFirst(markA).allSatisfy { if case .pairCode = $0 { false } else { true } }, "no code is shown for an id that is already paired")
        #expect(b.endpoint.pairedPeers.first?.pairedAt == stamp)
    }

    /// REG-744: an answer for another Mac's pairing does nothing; the right one does.
    @Test func anAnswerForAnotherMacDoesNotAnswerThePairing() async throws {
        let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = Node("Alpha", parent: dir), b = Node("Beta", parent: dir)
        defer { a.endpoint.stop(); b.endpoint.stop() }
        let pairPort = try #require(await b.pairPort())
        a.endpoint.pair(with: .direct(port: nil, pairPort: pairPort))
        _ = await a.wait("a code") { if case .pairCode = $0 { return true } else { return nil } }
        _ = await b.wait("a code") { if case .pairCode = $0 { return true } else { return nil } }
        b.endpoint.answerPairing(accept: true, peerID: "someone-else")
        a.endpoint.answerPairing(accept: true, peerID: "someone-else")
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(!b.events.contains { if case .paired = $0 { true } else { false } } && !a.events.contains { if case .paired = $0 { true } else { false } })
        b.endpoint.answerPairing(accept: true, peerID: a.id)
        a.endpoint.answerPairing(accept: true, peerID: b.id)
        #expect(await a.wait("paired") { if case .paired = $0 { return true } else { return nil } } == true)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

@MainActor
@Suite("Fling security round, app side")
struct FlingSecurityAppTests {
    private func model() -> TopBarModel { TopBarModel(defaults: UserDefaults(suiteName: "zeus.fling-secapp.\(UUID().uuidString)")!) }
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// REG-745: a card ignores clicks for its first second, so a stray click or a scripted one cannot answer it, but the timeout still declines.
    @Test func aNewCardIgnoresAnswersForItsFirstSecond() {
        var now = Date(timeIntervalSince1970: 1000)
        var answers: [Bool] = []
        let card = FlingPromptModel(kind: .offer(peerName: "Mac B", itemCount: 1, totalBytes: 5), deadline: now.addingTimeInterval(60), clock: { now }, onAnswer: { answers.append($0) })
        card.answer(true)
        #expect(answers.isEmpty && !card.answered)
        now = now.addingTimeInterval(0.99); card.answer(true)
        #expect(answers.isEmpty)
        now = now.addingTimeInterval(0.02); card.answer(true)
        #expect(answers == [true])
        var late: [Bool] = []
        var t = Date(timeIntervalSince1970: 0)
        let timing = FlingPromptModel(kind: .offer(peerName: "x", itemCount: 1, totalBytes: 1), deadline: t.addingTimeInterval(60), clock: { t }, onAnswer: { late.append($0) })
        t = t.addingTimeInterval(60); timing.tick()
        #expect(late == [false], "the timeout is not an answer a click can block")
    }

    /// REG-737: private, loopback and local links are kept on the Shelf but never opened by themselves.
    @Test func privateLinksNeverOpenWithoutAClick() async {
        for (address, expected) in [("https://example.com", 1), ("http://192.168.1.1/admin", 0), ("http://localhost:3000", 0), ("http://printer.local", 0), ("https://[::1]/", 0)] {
            let transport = FakeTransport()
            let s = FlingService(model: model(), transport: transport, setting: { id in id == "fling.enabled" ? "true" : (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
            var opened: [URL] = []
            s.openLink = { opened.append($0) }
            s.reconfigure(); await settle { s.eventsAreFlowing }
            let stack = UUID()
            transport.emit(.itemArrived(stackID: stack, index: 0, name: "x.webloc", url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).webloc"), sha256: "x", peerName: "Mac B", link: address))
            transport.emit(.stackFinished(stackID: stack, direction: .receive))
            await settle { opened.count == expected }
            try? await Task.sleep(nanoseconds: 30_000_000)
            #expect(opened.count == expected, "\(address)")
        }
    }

    /// REG-746: when a Mac that was paired refuses our key, the person is told to pair again.
    @Test func aRejectedStoredKeySaysPairAgain() async {
        let transport = FakeTransport()
        let s = FlingService(model: model(), transport: transport, setting: { id in id == "fling.enabled" ? "true" : (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
        s.reconfigure(); await settle { s.eventsAreFlowing }
        transport.emit(.failed(stackID: UUID(), direction: .send, reason: "tlsRejected"))
        await settle { s.lastProblem != nil }
        #expect(s.lastProblem?.contains("Pair again") == true)
    }

    /// REG-747: the answer to a pairing names the Mac it is for.
    @Test func thePairingAnswerNamesItsMac() async {
        let transport = FakeTransport()
        let s = FlingService(model: model(), transport: transport, setting: { id in id == "fling.enabled" ? "true" : (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
        s.reconfigure(); await settle { s.eventsAreFlowing }
        transport.emit(.pairCode(code: "123456", role: .responder, peerID: "idB", peerName: "Mac B"))
        await settle { s.pairingPrompt != nil }
        s.answerPairing(accept: true)
        #expect(transport.pairingPeers == ["idB"])
    }

    /// REG-748: a received file carries Zeus's quarantine mark, so Gatekeeper still looks at what a peer sent.
    @Test func receivedFilesAreQuarantinedAsFromZeus() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fling-q-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = FlingFileSink(stackID: UUID(), partialParent: dir, destination: dir.appendingPathComponent("Stack"))
        try sink.makeTemp()
        try sink.write(index: 0, data: Data("hello".utf8))
        _ = try sink.verify(index: 0)
        let url = try sink.commit(index: 0, name: "tool.command")
        let link = try sink.commitLink(name: "site", link: "https://example.com")
        for item in [url, link] {
            let values = try item.resourceValues(forKeys: [.quarantinePropertiesKey])
            let props = try #require(values.quarantineProperties)
            #expect(props[kLSQuarantineAgentNameKey as String] as? String == "Zeus", "\(item.lastPathComponent)")
            #expect(props[kLSQuarantineTypeKey as String] != nil)
        }
    }

    /// REG-735: a name that differs only in case lands beside the existing file, never over it.
    @Test func aCaseOnlyClashGetsANumberInTheStackFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fling-c-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = FlingFileSink(stackID: UUID(), partialParent: dir, destination: dir.appendingPathComponent("Stack"))
        try sink.makeTemp()
        for (i, text) in ["one", "two"].enumerated() { try sink.write(index: i, data: Data(text.utf8)); _ = try sink.verify(index: i) }
        let first = try sink.commit(index: 0, name: "Report.PDF")
        let second = try sink.commit(index: 1, name: "report.pdf")
        #expect(first.lastPathComponent == "Report.PDF" && second.lastPathComponent == "report 2.pdf")
        #expect(try String(contentsOf: first) == "one" && (try String(contentsOf: second)) == "two")
    }
}
