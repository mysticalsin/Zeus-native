import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Fling floating papers")
struct FlingPaperTests {
    private let area = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private func urls(_ n: Int) -> [URL] { (1...n).map { URL(fileURLWithPath: "/tmp/paper-\($0).png") } }
    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    /// REG-698: a paper floats over other apps on every Space without taking the keyboard or a click's focus.
    @Test func papersFloatOnEverySpaceAndNeverTakeFocus() {
        _ = NSApplication.shared
        let controller = FlingPaperController(area: { area }, present: false)
        controller.show(urls: urls(3), from: "Mac B")
        #expect(controller.papers.count == 3)
        var origins = Set<String>()
        for paper in controller.papers {
            let panel = paper.panel
            #expect(panel.level == .floating)
            #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless))
            #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.collectionBehavior.contains(.fullScreenAuxiliary))
            #expect(!panel.canBecomeKey && !panel.canBecomeMain && !panel.hidesOnDeactivate && !panel.isReleasedWhenClosed)
            #expect(area.contains(panel.frame))
            origins.insert("\(panel.frame.origin)")
        }
        #expect(origins.count == 3, "papers cascade, they do not stack on one spot")
        controller.closeAll()
    }

    /// REG-698: closing a paper takes the paper away and nothing else.
    @Test func closingAPaperNeverTouchesTheShelfOrTheFiles() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fling-papers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.png"), b = dir.appendingPathComponent("b.png")
        try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)
        let topBar = TopBarModel(defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "zeus.fling-papers.\(UUID().uuidString)")!)
        topBar.addToShelf([a, b], origin: .fling(peer: "Mac B"), stack: UUID())
        let before = topBar.shelf
        let controller = FlingPaperController(area: { area }, present: false)
        controller.show(urls: [a, b], from: "Mac B")
        let first = try #require(controller.papers.first)
        controller.close(first.id)
        #expect(controller.papers.count == 1)
        #expect(topBar.shelf == before)
        #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
        controller.closeAll()
        #expect(controller.papers.isEmpty && topBar.shelf == before)
    }

    /// REG-698: a pinch brings the papers together into one fanned stack.
    @Test func aPinchGroupsThePapersIntoOneStack() {
        _ = NSApplication.shared
        let controller = FlingPaperController(area: { area }, present: false)
        controller.show(urls: urls(4), from: "Mac B")
        let spread = controller.papers.map(\.panel.frame.origin)
        controller.group()
        let grouped = controller.papers.map(\.panel.frame.origin)
        #expect(grouped.count == 4)
        let width = (grouped.map(\.x).max() ?? 0) - (grouped.map(\.x).min() ?? 0)
        let spreadWidth = (spread.map(\.x).max() ?? 0) - (spread.map(\.x).min() ?? 0)
        #expect(width < spreadWidth)
        #expect(width <= 5 * 6 + 0.001, "a fan of at most five steps")
        controller.closeAll()
    }

    /// REG-698: arrivals become papers only when the Settings switch is on.
    @Test func arrivalsBecomePapersOnlyWhenTheSwitchIsOn() async {
        for (setting, expected) in [("true", 1), ("false", 0)] {
            let transport = FakeTransport()
            let service = FlingService(model: TopBarModel(defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "zeus.fling-papers.\(UUID().uuidString)")!), transport: transport,
                                       setting: { id in id == "fling.enabled" ? "true" : (id == "fling.papers" ? setting : (SettingsCatalog.option(id)?.defaultValue ?? "")) },
                                       downloadsGranted: { true })
            var shown: [([URL], String)] = []
            service.presentPapers = { shown.append(($0, $1)) }
            service.reconfigure()
            await settle { service.eventsAreFlowing }
            let stack = UUID()
            let a = URL(fileURLWithPath: "/tmp/a.png")
            transport.emit(.itemArrived(stackID: stack, index: 0, name: "a.png", url: a, sha256: "x", peerName: "Mac B", link: nil))
            transport.emit(.stackFinished(stackID: stack, direction: .receive))
            await settle { service.eventsAreFlowing && (!shown.isEmpty || expected == 0) }
            try? await Task.sleep(nanoseconds: 40_000_000)
            #expect(shown.count == expected, "papers \(setting)")
            if expected == 1 { #expect(shown[0].0 == [a] && shown[0].1 == "Mac B") }
        }
    }
}
