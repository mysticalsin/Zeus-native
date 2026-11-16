import Foundation
import Testing
import ZeusCore
import ZeusFling
@testable import Zeus

@Suite("Fling save modes, asking and links", .serialized, .timeLimit(.minutes(2)))
struct FlingModesTests {
    private func parent() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fling-modes-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// REG-697: Ask each time prompts even for a paired Mac, and the answer picks where the files land.
    @Test func askEachTimePromptsEvenForAPairedMacAndTheAnswerPicksTheFolder() async throws {
        let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = Node("Alpha", parent: dir), b = Node("Beta", parent: dir)
        defer { a.endpoint.stop(); b.endpoint.stop() }
        var settings = FlingEndpointSettings(); settings.saveMode = .ask; settings.autoAcceptPaired = true
        b.endpoint.updateSettings(settings)
        let port = try #require(await pair(a, b))
        let file = dir.appendingPathComponent("note.txt"); try Data("hello".utf8).write(to: file)
        a.endpoint.send([.file(file)], to: .direct(id: b.id, port: port, pairPort: nil))
        let stack = try #require(await b.wait("an offer") { if case .offer(let s, _, _, _, _) = $0 { return s } else { return nil } })
        #expect(listing(b.root).filter { $0.hasSuffix("note.txt") }.isEmpty, "nothing is written before the answer")
        b.endpoint.answerOffer(stack, accept: true, saveMode: .clipboard)
        _ = try #require(await b.wait("the file") { if case .itemArrived(_, _, let name, let url, _, _, _) = $0, name == "note.txt" { return url } else { return nil } })
        #expect(listing(b.root).contains { $0.hasPrefix("/Inbox/Alpha ") && $0.hasSuffix("/note.txt") })
        #expect(!listing(b.root).contains { $0.hasPrefix("/Fling/") && $0.hasSuffix("note.txt") })
    }

    /// REG-697: Clipboard mode, and Downloads without access, land in the private inbox, never in Downloads/Fling.
    @Test func clipboardModeAndNoDownloadsAccessLandInTheInbox() async throws {
        for mode in ["clipboard", "noAccess"] {
            let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
            let a = Node("Alpha", parent: dir), b = Node("Beta", parent: dir)
            defer { a.endpoint.stop(); b.endpoint.stop() }
            var settings = FlingEndpointSettings()
            if mode == "clipboard" { settings.saveMode = .clipboard } else { settings.downloadsGranted = false }
            b.endpoint.updateSettings(settings)
            let port = try #require(await pair(a, b))
            let file = dir.appendingPathComponent("pic.png"); try Data("png".utf8).write(to: file)
            a.endpoint.send([.file(file)], to: .direct(id: b.id, port: port, pairPort: nil))
            _ = try #require(await b.wait("the file (\(mode))") { if case .itemArrived(_, _, let name, let url, _, _, _) = $0, name == "pic.png" { return url } else { return nil } })
            #expect(listing(b.root).contains { $0.hasPrefix("/Inbox/") && $0.hasSuffix("/pic.png") }, "\(mode)")
            #expect(!listing(b.root).contains { $0.hasPrefix("/Fling/") && $0.hasSuffix("pic.png") }, "\(mode)")
        }
    }

    /// REG-697: a link arrives as a .webloc file that holds exactly its address.
    @Test func aLinkArrivesAsAWeblocWithItsAddress() async throws {
        let dir = parent(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = Node("Alpha", parent: dir), b = Node("Beta", parent: dir)
        defer { a.endpoint.stop(); b.endpoint.stop() }
        let port = try #require(await pair(a, b))
        a.endpoint.send([.link("https://example.com/a?b=1")], to: .direct(id: b.id, port: port, pairPort: nil))
        let arrived = try #require(await b.wait("the link") { if case .itemArrived(_, _, _, let url, _, _, let link?) = $0 { return (url, link) } else { return nil } })
        #expect(arrived.1 == "https://example.com/a?b=1" && arrived.0.pathExtension == "webloc")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: arrived.0), format: nil) as? [String: String]
        #expect(plist?["URL"] == "https://example.com/a?b=1")
        // A non-web address never leaves the sender.
        a.endpoint.send([.link("file:///etc/passwd")], to: .direct(id: b.id, port: port, pairPort: nil))
        let failed = await a.wait("a refusal") { if case .failed(_, .send, let reason) = $0 { return reason } else { return nil } }
        #expect(failed == "badLink")
    }
}

@MainActor
@Suite("Fling service: links, clipboard and the Ask card")
struct FlingServiceModesTests {
    private func model() -> TopBarModel { TopBarModel(defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "zeus.fling-svc.\(UUID().uuidString)")!) }
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }
    private func service(_ transport: FakeTransport, _ values: [String: String]) -> FlingService {
        var all = values; all["fling.enabled"] = "true"
        return FlingService(model: model(), transport: transport, setting: { id in all[id] ?? (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
    }

    /// REG-697: a received link opens in the browser only when the switch is on, only for http and https, and only once the stack is verified.
    @Test func aReceivedLinkOpensOnlyWhenAllowedAndOnlyForWebAddresses() async {
        for (open, address, expected) in [("true", "https://example.com", 1), ("false", "https://example.com", 0), ("true", "javascript:alert(1)", 0), ("true", "file:///etc/passwd", 0)] {
            let transport = FakeTransport()
            let s = service(transport, ["fling.openLinks": open])
            var opened: [URL] = []
            s.openLink = { opened.append($0) }
            s.reconfigure()
            await settle { s.eventsAreFlowing }
            let stack = UUID()
            let link = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).webloc")
            transport.emit(.itemArrived(stackID: stack, index: 0, name: "x.webloc", url: link, sha256: "x", peerName: "Mac B", link: address))
            await settle { true }
            #expect(opened.isEmpty, "nothing opens before the stack is verified")
            transport.emit(.stackFinished(stackID: stack, direction: .receive))
            await settle { opened.count == expected }
            try? await Task.sleep(nanoseconds: 30_000_000)
            #expect(opened.count == expected, "\(address) with openLinks \(open)")
            if expected == 1 { #expect(opened[0].absoluteString == address) }
        }
    }

    /// REG-697: Clipboard mode puts the arrived files on the pasteboard once the stack is verified.
    @Test func clipboardModeCopiesTheArrivedFiles() async {
        let transport = FakeTransport()
        let s = service(transport, ["fling.saveMode": "Clipboard"])
        var copied: [[URL]] = []
        s.writeClipboard = { copied.append($0) }
        s.reconfigure()
        await settle { s.eventsAreFlowing }
        let stack = UUID()
        let a = URL(fileURLWithPath: "/tmp/a.png"), b = URL(fileURLWithPath: "/tmp/b.png")
        transport.emit(.itemArrived(stackID: stack, index: 0, name: "a.png", url: a, sha256: "x", peerName: "Mac B", link: nil))
        transport.emit(.itemArrived(stackID: stack, index: 1, name: "b.png", url: b, sha256: "y", peerName: "Mac B", link: nil))
        transport.emit(.stackFinished(stackID: stack, direction: .receive))
        await settle { !copied.isEmpty }
        #expect(copied == [[a, b]])

        let other = service(FakeTransport(), [:])
        var none: [[URL]] = []
        other.writeClipboard = { none.append($0) }
        other.handle(.itemArrived(stackID: stack, index: 0, name: "a.png", url: a, sha256: "x", peerName: "Mac B", link: nil))
        other.handle(.stackFinished(stackID: stack, direction: .receive))
        #expect(none.isEmpty, "Downloads mode never touches the pasteboard")
    }

    /// REG-697: in Ask mode the answer carries the chosen place to the transport, and a plain Accept carries none.
    @Test func theAskAnswerCarriesTheChosenPlace() async {
        let transport = FakeTransport()
        let s = service(transport, ["fling.saveMode": "Ask each time"])
        s.reconfigure()
        await settle { s.eventsAreFlowing }
        let stack = UUID()
        transport.emit(.offer(stackID: stack, peerID: "idB", peerName: "Mac B", itemCount: 1, totalBytes: 5))
        await settle { s.pendingOffer != nil }
        s.answerOffer(accept: true, saveMode: .clipboard)
        #expect(transport.modeAnswers.count == 1 && transport.modeAnswers[0].mode == .clipboard && transport.modeAnswers[0].accept)
        #expect(s.pendingOffer == nil)
    }

    @Test func theAskCardOffersBothPlacesAndOnlyTheFirstChoiceCounts() {
        var chosen: [FlingSaveMode] = []
        var answers: [Bool] = []
        let card = FlingPromptModel(kind: .offer(peerName: "Mac B", itemCount: 1, totalBytes: 5), deadline: Date().addingTimeInterval(60), clock: Date.init,
                                    onAnswer: { answers.append($0) }, askWhere: true, onChoose: { chosen.append($0) }, inputDelay: 0)
        card.choose(.clipboard)
        card.choose(.downloads)
        card.answer(false)
        #expect(chosen == [.clipboard] && answers.isEmpty)
        #expect(card.askWhere)
    }
}
