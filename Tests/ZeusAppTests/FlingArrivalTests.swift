import Foundation
import Testing
import ZeusCore
import ZeusFling
@testable import Zeus

@MainActor
@Suite("Fling arrivals and the Shelf", .serialized)
struct FlingArrivalTests {
    private func model() -> TopBarModel { TopBarModel(defaults: UserDefaults(suiteName: "zeus.fling-arrival.\(UUID().uuidString)")!) }
    private func temp() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fling-arrival-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func file(_ name: String, in dir: URL) -> URL {
        let url = dir.appendingPathComponent(name)
        try? Data(name.utf8).write(to: url)
        return url
    }
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }
    private func withSettings(_ values: [String: String], _ body: () async -> Void) async {
        let store = SettingsStore.shared
        let saved = values.keys.map { ($0, store.string($0)) }
        defer { for (id, value) in saved { store.set(id, value) } }
        for (id, value) in values { store.set(id, value) }
        await body()
    }

    /// REG-680: items from Fling carry their origin, their stack and the verified mark; the old calls keep their old meaning.
    @Test func arrivalsGetTheFlingOriginAStackAndTheVerifiedMark() {
        let m = model(); let stack = UUID()
        m.addToShelf([URL(fileURLWithPath: "/tmp/a.png")], origin: .fling(peer: "Mac B"), stack: stack)
        #expect(m.shelf.first?.origin == .fling(peer: "Mac B"))
        #expect(m.shelf.first?.stackID == stack && m.shelf.first?.verified == true)
        m.addToShelf([URL(fileURLWithPath: "/tmp/b.png")], isAirDrop: true)
        #expect(m.shelf.first?.origin == .airDrop && m.shelf.first?.verified == false && m.shelf.first?.stackID == nil)
        m.addToShelf([URL(fileURLWithPath: "/tmp/c.png")])
        #expect(m.shelf.first?.origin == .local)
    }

    /// REG-680: Fling items persist across a relaunch, files that are gone are dropped, and removing an item forgets it.
    @Test func flingItemsSurviveARelaunchButLocalOnesDoNot() {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = FlingShelfPersistence(url: dir.appendingPathComponent("Shelf/shelf.json"))
        let kept = file("kept.png", in: dir), gone = file("gone.png", in: dir), local = file("local.png", in: dir)
        let first = model(); first.shelfPersistence = persistence
        let stack = UUID()
        first.addToShelf([kept, gone], origin: .fling(peer: "Mac B"), stack: stack)
        first.addToShelf([local])
        try? FileManager.default.removeItem(at: gone)

        let second = model(); second.shelfPersistence = persistence
        second.loadPersistedShelf()
        #expect(second.shelf.map(\.url) == [kept])
        #expect(second.shelf.first?.origin == .fling(peer: "Mac B") && second.shelf.first?.stackID == stack && second.shelf.first?.verified == true)

        let id = second.shelf[0].id
        second.removeFromShelf(id)
        let third = model(); third.shelfPersistence = persistence
        third.loadPersistedShelf()
        #expect(third.shelf.isEmpty)
    }

    /// REG-681: the Fling glow and cue show only with Settings > Everyday lights > Fling on, and never use the AirDrop colours.
    @Test func theFlingLightShowsOnlyWithItsSwitchOn() async {
        await withSettings(["lights.fling": "true"]) {
            let m = model()
            m.addToShelf([URL(fileURLWithPath: "/tmp/a.png")], origin: .fling(peer: "Mac B"), stack: UUID())
            #expect(m.lights.contains { $0.kind == .flingLanded })
            #expect(!m.lights.contains { $0.kind == .landed(airDrop: true) || $0.kind == .landed(airDrop: false) })
            #expect(m.cue == .flingArrived(count: 1, from: "Mac B"))
        }
        await withSettings(["lights.fling": "false"]) {
            let m = model()
            m.addToShelf([URL(fileURLWithPath: "/tmp/a.png")], origin: .fling(peer: "Mac B"), stack: UUID())
            #expect(m.lights.isEmpty && m.cue == nil)
            #expect(m.shelf.count == 1)
        }
        #expect(TopBarModel.lightOption(for: .flingLanded) == "lights.fling")
        #expect(TopBarModel.lightOption(for: NotchCue.flingArrived(count: 2, from: "x")) == "lights.fling")
    }

    @Test func theOldShelfCallsLightAsBefore() async {
        await withSettings(["lights.shelf": "true", "lights.airDrop": "true"]) {
            let m = model()
            m.addToShelf([URL(fileURLWithPath: "/tmp/a.png")], isAirDrop: true)
            #expect(m.lights.contains { $0.kind == .landed(airDrop: true) } && m.cue == .shelfAdded(1))
            let n = model()
            n.addToShelf([URL(fileURLWithPath: "/tmp/b.png")])
            #expect(n.lights.contains { $0.kind == .landed(airDrop: false) } && n.cue == .shelfAdded(1))
        }
    }

    /// REG-682: the screenshot and AirDrop watcher skips the Fling folder, dot files and Fling's partial folders.
    @Test func theIntakeWatcherIgnoresTheFlingFolder() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let inbox = FlingService.supportDirectory.appendingPathComponent("Fling/Inbox")
        #expect(AirDropScreenshotWatcher.isIgnored(downloads.appendingPathComponent("Fling/Stack/a.png")))
        #expect(AirDropScreenshotWatcher.isIgnored(downloads.appendingPathComponent("Fling/.fling-partial-X/0")))
        #expect(AirDropScreenshotWatcher.isIgnored(inbox.appendingPathComponent("Stack/a.png")))
        #expect(AirDropScreenshotWatcher.isIgnored(downloads.appendingPathComponent(".hidden")))
        #expect(!AirDropScreenshotWatcher.isIgnored(downloads.appendingPathComponent("photo.png")))
        #expect(!AirDropScreenshotWatcher.isIgnored(downloads.appendingPathComponent("Other/Fling/a.png")), "REG-776: only Zeus's own folders")
    }

    /// REG-683: the service type the app browses for is the one the plist declares.
    @Test func theServiceTypeMatchesThePlist() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")), format: nil) as? [String: Any])
        #expect((plist["NSBonjourServices"] as? [String])?.contains(FlingEndpoint.serviceType) == true)
    }

    /// REG-692: sending happens only through `send(_:to:gesture:)`. Failures, arrivals, offers and peers never send.
    @Test func sendingNeedsAGestureAndNothingResendsOnItsOwn() async {
        let transport = FakeTransport()
        let m = model()
        let service = FlingService(model: m, transport: transport, setting: { id in id == "fling.enabled" ? "true" : (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
        service.reconfigure()
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let item = TopBarModel.ShelfItem(url: file("a.png", in: dir))
        await settle { service.eventsAreFlowing }

        service.send([item], to: .peer(id: "idB"), gesture: .drop)
        #expect(transport.sends.count == 1 && transport.sends[0].to == "idB")

        let stack = UUID()
        transport.emit(.peersChanged([]))
        transport.emit(.failed(stackID: stack, direction: .send, reason: "peerLost"))
        transport.emit(.declined(stackID: stack, direction: .send, reason: .diskFull))
        transport.emit(.offer(stackID: UUID(), peerID: "idC", peerName: "Mac C", itemCount: 1, totalBytes: 5))
        transport.emit(.itemArrived(stackID: stack, index: 0, name: "a.png", url: item.url, sha256: "x", peerName: "Mac B", link: nil))
        transport.emit(.stackFinished(stackID: stack, direction: .receive))
        await settle { service.lastProblem != nil && !m.shelf.isEmpty }
        #expect(service.lastProblem != nil)
        #expect(transport.sends.count == 1, "nothing but the gesture may send")
        #expect(service.pendingOffer?.peerName == "Mac C")

        service.send([item], to: .peer(id: "idB"), gesture: .button)
        #expect(transport.sends.count == 2)
    }

    @Test func aStackReachesTheShelfWhenItFinishesAndAVerifiedFileSurvivesAFailure() async {
        let transport = FakeTransport()
        let m = model()
        let service = FlingService(model: m, transport: transport, setting: { id in id == "fling.enabled" ? "true" : (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
        service.reconfigure()
        await settle { service.eventsAreFlowing }
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = file("a.png", in: dir), b = file("b.png", in: dir)
        let s1 = UUID()
        transport.emit(.itemArrived(stackID: s1, index: 0, name: "a.png", url: a, sha256: "x", peerName: "Mac B", link: nil))
        transport.emit(.itemArrived(stackID: s1, index: 1, name: "b.png", url: b, sha256: "y", peerName: "Mac B", link: nil))
        transport.emit(.stackFinished(stackID: s1, direction: .receive))
        await settle { m.shelf.count == 2 }
        #expect(m.shelf.count == 2 && Set(m.shelf.compactMap(\.stackID)) == [s1] && m.shelf.allSatisfy { $0.verified })

        let c = file("c.png", in: dir)
        let s2 = UUID()
        transport.emit(.itemArrived(stackID: s2, index: 0, name: "c.png", url: c, sha256: "z", peerName: "Mac B", link: nil))
        transport.emit(.failed(stackID: s2, direction: .receive, reason: "hashMismatch"))
        await settle { m.shelf.count == 3 }
        #expect(m.shelf.first?.url == c)
    }

    /// REG-681: Fling is off until the person turns it on, and turning it off stops it.
    @Test func flingStaysOffUntilTheSwitchIsOn() {
        let transport = FakeTransport()
        var enabled = "false"
        let service = FlingService(model: model(), transport: transport, setting: { id in id == "fling.enabled" ? enabled : (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
        service.reconfigure()
        #expect(transport.starts == 0 && !service.isEnabled)
        enabled = "true"; service.reconfigure()
        #expect(transport.starts == 1 && service.isEnabled)
        service.reconfigure()
        #expect(transport.starts == 1, "an unchanged setting must not restart it")
        enabled = "false"; service.reconfigure()
        #expect(transport.stops == 1 && !service.isEnabled)
    }

    @Test func pairingAndOffersGoThroughTheServiceAndClearWhenDone() async {
        let transport = FakeTransport()
        let service = FlingService(model: model(), transport: transport, setting: { id in id == "fling.enabled" ? "true" : (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
        service.reconfigure()
        await settle { service.eventsAreFlowing }
        transport.emit(.pairCode(code: "123456", role: .responder, peerID: "idB", peerName: "Mac B"))
        await settle { service.pairingPrompt != nil }
        #expect(service.pairingPrompt?.code == "123456" && service.pairingPrompt?.peerName == "Mac B")
        service.answerPairing(accept: true)
        #expect(transport.pairingAnswers == [true])
        transport.emit(.paired(peerID: "idB", name: "Mac B"))
        await settle { service.pairingPrompt == nil }
        #expect(service.pairingPrompt == nil)

        let stack = UUID()
        transport.emit(.offer(stackID: stack, peerID: "idB", peerName: "Mac B", itemCount: 2, totalBytes: 10))
        await settle { service.pendingOffer != nil }
        service.answerOffer(accept: false)
        #expect(transport.offerAnswers.count == 1 && transport.offerAnswers[0].0 == stack && transport.offerAnswers[0].1 == false)
        #expect(service.pendingOffer == nil)
    }

    /// REG-699: a send over 2 GB says so before it goes; a small one says nothing; the gesture still sends.
    @Test func aSendOverTwoGigabytesWarnsAndStillGoesWithItsGesture() throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let big = dir.appendingPathComponent("big.mov")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: 2_100_000_000)
        try handle.close()
        let small = file("small.txt", in: dir)

        let transport = FakeTransport()
        let m = model()
        let service = FlingService(model: m, transport: transport, setting: { id in id == "fling.enabled" ? "true" : (SettingsCatalog.option(id)?.defaultValue ?? "") }, downloadsGranted: { true })
        service.reconfigure()
        service.send([TopBarModel.ShelfItem(url: small)], to: .peer(id: "idB"), gesture: .button)
        #expect(m.cue == nil && transport.sends.count == 1)
        service.send([TopBarModel.ShelfItem(url: big)], to: .peer(id: "idB"), gesture: .drop)
        guard case .flingProblem(let text)? = m.cue else { Issue.record("no warning: \(String(describing: m.cue))"); return }
        #expect(text.contains("GB"), "\(text)")
        #expect(transport.sends.count == 2, "the warning does not stop a send the person asked for")
    }
}
