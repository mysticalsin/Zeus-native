import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Stickies")
struct StickiesTests {
    @Test func titles() {
        #expect(StickyNote(text: "\n\n# **Groceries** list\n- milk").title == "Groceries list")
        #expect(StickyNote(text: "   ").title == "Empty note")
        #expect(StickyNote(text: String(repeating: "a", count: 60)).title.count == 40)
        #expect(StickyNote(placement: .edge(.right, top: 10)).isOnEdge)
        #expect(!StickyNote().isOnEdge)
    }

    @Test func storeRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-stickies-\(UUID().uuidString)/stickies.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = StickyStore(url: url)
        #expect(store.load().isEmpty)
        let notes = [
            StickyNote(text: "one", tint: .sky, placement: .floating(CGRect(x: 10, y: 20, width: 260, height: 200)), created: Date(timeIntervalSince1970: 100)),
            StickyNote(text: "two", tint: .leaf, placement: .edge(.left, top: 80), created: Date(timeIntervalSince1970: 200)),
        ]
        try store.save(notes)
        #expect(store.load() == notes)
    }

    @Test func edgeTabAndSlideOut() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let tucked = EdgeShelf.frame(edge: .right, top: 100, expanded: false, visible: visible)
        #expect(Double(tucked.minX) == 1440 - EdgeShelf.tabWidth)
        #expect(Double(tucked.maxY) == 775)
        let open = EdgeShelf.frame(edge: .right, top: 100, expanded: true, visible: visible)
        #expect(open.maxX == 1440)
        let left = EdgeShelf.frame(edge: .left, top: 0, expanded: false, visible: visible)
        #expect(Double(left.maxX) == EdgeShelf.tabWidth)
        #expect(EdgeShelf.frame(edge: .left, top: 0, expanded: true, visible: visible).minX == 0)
        // Never off the bottom of the screen.
        #expect(EdgeShelf.frame(edge: .left, top: 5000, expanded: true, visible: visible).minY == 0)
    }

    @Test func snapping() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        #expect(EdgeShelf.snapEdge(for: CGRect(x: 10, y: 100, width: 260, height: 220), visible: visible) == .left)
        #expect(EdgeShelf.snapEdge(for: CGRect(x: 1170, y: 100, width: 260, height: 220), visible: visible) == .right)
        #expect(EdgeShelf.snapEdge(for: CGRect(x: 600, y: 100, width: 260, height: 220), visible: visible) == nil)
        #expect(EdgeShelf.top(for: CGRect(x: 0, y: 455, width: 260, height: 220), visible: visible) == 200)
    }
}
