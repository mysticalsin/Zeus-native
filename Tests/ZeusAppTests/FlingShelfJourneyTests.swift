import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import ZeusCore
import ZeusFling
@testable import Zeus

/// The Shelf as a person meets it: the real page and the real prompt card in an owned window, layout-resolved
/// events, and a recording stand-in for Fling. No network, no pairing, no file leaves this Mac.
/// Hosted: see qa/closed-loop/native_app_host.py.
@MainActor
@Suite("Fling Shelf journey", .inNativeHost, .serialized)
struct FlingShelfJourneyTests {
    /// Records every call the Shelf makes, in order.
    @MainActor
    final class RecordingFling: FlingSending {
        struct Send { var urls: [URL]; var target: FlingTarget; var gesture: FlingGesture }
        var isEnabled = true
        var localNetworkDenied = false
        var nearby: [FlingNearbyPeer] = []
        var pairingPrompt: FlingPairingPrompt?
        var pendingOffer: FlingOfferPrompt?
        var activity: [FlingActivity] = []
        var lastProblem: String?
        var justSent: Set<String> = []
        private(set) var sends: [Send] = []
        private(set) var turnOns = 0
        private(set) var pairs: [String] = []
        private(set) var cancels = 0
        func turnOn() { turnOns += 1; isEnabled = true }
        func send(_ items: [TopBarModel.ShelfItem], to target: FlingTarget, gesture: FlingGesture) {
            sends.append(Send(urls: items.map(\.url), target: target, gesture: gesture))
        }
        func pair(with peerID: String) { pairs.append(peerID) }
        func answerPairing(accept: Bool) {}
        func answerOffer(accept: Bool) {}
        func cancelAll() { cancels += 1 }
    }

    private let peerA = FlingNearbyPeer(id: "idA", name: "Alpha Mac", model: "Mac15,3", paired: true)
    private let peerB = FlingNearbyPeer(id: "idB", name: "Beta Mac", model: "Mac14,2", paired: true)
    private let stranger = FlingNearbyPeer(id: "idC", name: "Gamma Mac", model: "Mac13,1", paired: false)

    private func temp() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fling-journey-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func file(_ name: String, in dir: URL) -> URL {
        let url = dir.appendingPathComponent(name)
        try? Data(name.utf8).write(to: url)
        return url
    }
    private func model(_ fling: RecordingFling, items: [URL] = []) -> TopBarModel {
        let m = TopBarModel(defaults: UserDefaults(suiteName: "zeus.fling-journey.\(UUID().uuidString)")!)
        m.shelf = items.map { TopBarModel.ShelfItem(url: $0) }
        m.fling = fling
        return m
    }
    private func host(_ root: some View, registry: OwnedWindowControlRegistry) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 40, y: 100, width: 760, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root.frame(width: 760, height: 200).environment(\.ownedWindowControlRegistry, registry))
        window.makeKeyAndOrderFront(nil)
        return window
    }
    private func waitFor(_ what: String, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("timed out waiting for \(what)")
    }
    private func frame(_ id: String, _ registry: OwnedWindowControlRegistry, _ window: NSWindow) async throws -> CGRect? {
        var found: CGRect?
        try await waitFor("layout of \(id)") {
            window.contentView?.layoutSubtreeIfNeeded()
            let probes = registry.probes(for: id, in: window)
            if probes.count == 1, let probe = probes.first { found = probe.convert(probe.bounds, to: nil); return !(found?.isEmpty ?? true) }
            return false
        }
        return found
    }

    /// REG-689: with Fling off the Shelf offers one button, and pressing it turns Fling on; nothing else on the strip.
    @Test func theShelfOffersTurnOnAndThatClickTurnsFlingOn() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let fling = RecordingFling(); fling.isEnabled = false
            let registry = OwnedWindowControlRegistry()
            let window = host(ShelfPage(topBar: model(fling)), registry: registry)
            defer { OwnedWindowFixtureApplication.close(window) }
            let driver = OwnedWindowEventDriver(registry: registry); driver.register(window)
            #expect(registry.probes(for: "fling.avatar.idA", in: window).isEmpty)
            try await driver.click("fling.turnOn", in: window)
            #expect(fling.turnOns == 1)
        }
    }

    /// REG-689: refused Local Network access shows a help row with a button, not Nearby, and nothing crashes.
    @Test func aRefusedLocalNetworkShowsHelpInsteadOfNearby() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let fling = RecordingFling(); fling.localNetworkDenied = true; fling.nearby = [peerA]
            let registry = OwnedWindowControlRegistry()
            let window = host(ShelfPage(topBar: model(fling)), registry: registry)
            defer { OwnedWindowFixtureApplication.close(window) }
            #expect(try await frame("fling.openLocalNetwork", registry, window) != nil)
            #expect(registry.probes(for: "fling.avatar.idA", in: window).isEmpty)
        }
    }

    /// REG-690: the strip lists paired Macs first, then others by name, each as a control; an unpaired Mac pairs on click.
    @Test func theStripListsPairedMacsFirstAndAnUnpairedOneStartsPairingOnClick() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let fling = RecordingFling(); fling.nearby = [peerA, peerB, stranger]
            let registry = OwnedWindowControlRegistry()
            let window = host(ShelfPage(topBar: model(fling)), registry: registry)
            defer { OwnedWindowFixtureApplication.close(window) }
            let driver = OwnedWindowEventDriver(registry: registry); driver.register(window)
            let a = try #require(try await frame("fling.avatar.idA", registry, window))
            let b = try #require(try await frame("fling.avatar.idB", registry, window))
            let c = try #require(try await frame("fling.avatar.idC", registry, window))
            #expect(a.minX < b.minX && b.minX < c.minX, "paired first, in order")
            try await driver.click("fling.avatar.idC", in: window)
            #expect(fling.pairs == ["idC"])
            try await driver.click("fling.avatar.idA", in: window)
            #expect(fling.pairs == ["idC"], "a paired Mac is not paired again")
            #expect(fling.sends.isEmpty, "clicking never sends")
        }
    }

    /// REG-689: dragging a cell onto the second avatar sends that item to that Mac with the drop gesture.
    @Test func droppingACellOnAnAvatarSendsThatItemThereWithTheDropGesture() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
            let one = file("one.png", in: dir), two = file("two.png", in: dir)
            let fling = RecordingFling(); fling.nearby = [peerA, peerB]
            let topBar = model(fling, items: [one, two])
            let registry = OwnedWindowControlRegistry()
            let window = host(ShelfPage(topBar: topBar), registry: registry)
            defer { OwnedWindowFixtureApplication.close(window) }
            // A synthetic drag session cannot be started in an owned window, so the drop lands through the same
            // handler the avatar's drop target calls, from the avatar's laid-out place, with a real item provider.
            let target = try #require(try await frame("fling.avatar.idB", registry, window))
            #expect(window.contentView?.bounds.contains(CGPoint(x: target.midX, y: target.midY)) == true)
            let provider = try #require(NSItemProvider(contentsOf: one))
            FlingDropHandler.perform(providers: [provider], to: .peer(id: "idB"), fling: fling, topBar: topBar)
            try await waitFor("the send") { !fling.sends.isEmpty }
            #expect(fling.sends.count == 1)
            #expect(fling.sends[0].urls == [one] && fling.sends[0].target == .peer(id: "idB") && fling.sends[0].gesture == .drop)
        }
    }

    /// REG-677: the real tracker turns synthetic samples into sends, a picker, or a plain drop.
    @Test func flicksSendPickOrDropByTheirSpeedDirectionAndPeers() {
        func samples(dx: CGFloat, dy: CGFloat, speed: CGFloat) -> [(CGPoint, TimeInterval)] {
            let length = hypot(dx, dy)
            return stride(from: 0, through: 120, by: 10).map { ms in
                let t = TimeInterval(ms) / 1000
                return (CGPoint(x: 200 + dx / length * speed * CGFloat(t), y: 100 + dy / length * speed * CGFloat(t)), t)
            }
        }
        func run(_ s: [(CGPoint, TimeInterval)], peers: [FlingNearbyPeer]) -> (sent: [RecordingFling.Send], picker: Int) {
            let fling = RecordingFling()
            let tracker = FlingFlickTracker(sensitivity: .normal)
            for (point, time) in s { tracker.add(point, at: time) }
            var pickers = 0
            let item = TopBarModel.ShelfItem(url: URL(fileURLWithPath: "/tmp/x.png"))
            FlingFlickAction.perform(tracker.finish(peerCount: peers.count), items: [item], peers: peers, fling: fling, openPicker: { pickers += 1 })
            return (fling.sends, pickers)
        }
        let slow = run(samples(dx: -1, dy: 0, speed: 300), peers: [peerA])
        #expect(slow.sent.isEmpty && slow.picker == 0)
        let one = run(samples(dx: 1, dy: 0, speed: 2500), peers: [peerA])
        #expect(one.sent.count == 1 && one.sent[0].target == .peer(id: "idA") && one.sent[0].gesture == .flick)
        let left = run(samples(dx: -1, dy: 0, speed: 2500), peers: [peerA, peerB])
        #expect(left.sent.count == 1 && left.sent[0].target == .peer(id: "idA"))
        let right = run(samples(dx: 1, dy: 0, speed: 2500), peers: [peerA, peerB])
        #expect(right.sent.count == 1 && right.sent[0].target == .peer(id: "idB"))
        let up = run(samples(dx: 0, dy: -1, speed: 2500), peers: [peerA, peerB])
        #expect(up.sent.isEmpty && up.picker == 1)
    }

    /// REG-690: Accept answers yes, Decline answers no, and sixty seconds without an answer counts as no; only the first answer counts.
    @Test func theAcceptCardAnswersTheReceiveMachineAndTheTimeoutDeclines() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            let stack = UUID()
            let offer = FlingOffer(stackID: stack, items: [FlingOfferItem(index: 0, name: "a.png", size: 3, kind: .file, uti: nil, sha256: String(repeating: "0", count: 64), url: nil)])
            @MainActor func machine() -> FlingReceiveMachine {
                var m = FlingReceiveMachine(context: FlingReceiveContext(peerID: "idA", peerName: "Alpha Mac", paired: true, autoAccept: false, freeBytes: 100 << 30, isReplay: false))
                _ = m.handle(.received(.offer(offer), now: Date(timeIntervalSince1970: 0)))
                return m
            }
            final class Box { var machine: FlingReceiveMachine; init(_ m: FlingReceiveMachine) { machine = m } }
            final class Box2 { var seconds = 0.0 }
            @MainActor func cardModel(_ box: Box, now: Box2) -> FlingPromptModel {
                FlingPromptModel(kind: .offer(peerName: "Alpha Mac", itemCount: 1, totalBytes: 3), deadline: Date(timeIntervalSince1970: 60),
                                 clock: { Date(timeIntervalSince1970: now.seconds) },
                                 onAnswer: { accept in _ = box.machine.handle(accept ? .userAccept : .userDecline) }, inputDelay: 0)
            }

            // Accept.
            let yes = Box(machine()); let clock1 = Box2()
            let registry = OwnedWindowControlRegistry()
            let window = host(FlingPromptCard(model: cardModel(yes, now: clock1)), registry: registry)
            let driver = OwnedWindowEventDriver(registry: registry); driver.register(window)
            try await driver.click("fling.prompt.accept", in: window)
            #expect(yes.machine.state == .receiving(index: 0, got: 0))
            OwnedWindowFixtureApplication.close(window)

            // Decline.
            let no = Box(machine()); let clock2 = Box2()
            let registry2 = OwnedWindowControlRegistry()
            let window2 = host(FlingPromptCard(model: cardModel(no, now: clock2)), registry: registry2)
            let driver2 = OwnedWindowEventDriver(registry: registry2); driver2.register(window2)
            try await driver2.click("fling.prompt.decline", in: window2)
            #expect(no.machine.state == .declined(.declined))
            OwnedWindowFixtureApplication.close(window2)

            // Timeout on an injected clock: nothing at 59 s, a decline at 60 s, and a late click changes nothing.
            let late = Box(machine()); let clock3 = Box2()
            let model3 = cardModel(late, now: clock3)
            clock3.seconds = 59; model3.tick()
            if case .prompting = late.machine.state {} else { Issue.record("a decline came before sixty seconds: \(late.machine.state)") }
            clock3.seconds = 60; model3.tick()
            #expect(late.machine.state == .declined(.declined))
            model3.answer(true)
            #expect(late.machine.state == .declined(.declined), "the first answer is the only one")
        }
    }

    /// REG-730: the starting Mac's card also needs its person: "Codes match" or Cancel, and both answer.
    @Test func thePairingCardOnTheStartingMacAsksForCodesMatchOrCancel() async throws {
        try await OwnedWindowJourneyLease.perform {
            let original = try OwnedWindowFixtureApplication.prepare()
            defer { OwnedWindowFixtureApplication.restore(original) }
            for press in ["fling.prompt.accept", "fling.prompt.decline"] {
                var answers: [Bool] = []
                let model = FlingPromptModel(kind: .pairing(code: "042917", peerName: "Beta Mac", canAccept: true, starter: true), deadline: Date().addingTimeInterval(60),
                                             clock: Date.init, onAnswer: { answers.append($0) }, inputDelay: 0)
                let registry = OwnedWindowControlRegistry()
                let window = host(FlingPromptCard(model: model), registry: registry)
                defer { OwnedWindowFixtureApplication.close(window) }
                let driver = OwnedWindowEventDriver(registry: registry); driver.register(window)
                try await driver.click(press, in: window)
                #expect(answers == [press == "fling.prompt.accept"])
                #expect(model.codeText == "042 917")
            }
        }
    }
}
