import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor
@Suite("Fling stacks on the Shelf")
struct FlingStackTests {
    private func model() -> TopBarModel { TopBarModel(defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "zeus.fling-stacks.\(UUID().uuidString)")!) }
    private func temp() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fling-stacks-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func file(_ name: String, in dir: URL, text: String? = nil) -> URL {
        let url = dir.appendingPathComponent(name)
        try? Data((text ?? name).utf8).write(to: url)
        return url
    }

    /// REG-696: files that arrived together collapse into one stack cell, in the order they first appear; single files stay alone.
    @Test func filesFromOneStackCollapseIntoOneCellAndSingleFilesStayAlone() {
        let stack = UUID(), other = UUID()
        func item(_ n: String, _ s: UUID?) -> TopBarModel.ShelfItem { TopBarModel.ShelfItem(url: URL(fileURLWithPath: "/tmp/\(n)"), origin: .fling(peer: "Mac B"), stackID: s, verified: true) }
        let a = item("a", stack), b = item("b", nil), c = item("c", stack), d = item("d", other), e = item("e", stack)
        let cells = ShelfStacks.cells([a, b, c, d, e])
        #expect(cells == [.stack(id: stack, items: [a, c, e]), .item(b), .item(d)])
        #expect(ShelfStacks.cells([]).isEmpty)
        #expect(ShelfStacks.cells([item("only", UUID())]).count == 1)
        if case .item = ShelfStacks.cells([item("only", UUID())])[0] {} else { Issue.record("one file in a stack is just a file") }
    }

    @Test func groupingJoinsItemsAndUngroupingFreesThem() {
        let m = model()
        m.addToShelf([URL(fileURLWithPath: "/tmp/g1"), URL(fileURLWithPath: "/tmp/g2"), URL(fileURLWithPath: "/tmp/g3")])
        let ids = m.shelf.map(\.id)
        let stack = m.groupShelfItems(Array(ids.prefix(2)))
        #expect(stack != nil)
        #expect(m.shelf.filter { $0.stackID == stack }.count == 2)
        #expect(m.shelf.first { $0.id == ids[2] }?.stackID == nil)
        #expect(m.groupShelfItems([ids[2]]) == nil, "one item is not a stack")
        m.ungroupStack(try! #require(stack))
        #expect(m.shelf.allSatisfy { $0.stackID == nil })
    }

    /// REG-696: Save stack to folder moves every file, points the Shelf at the new places and remembers them.
    @Test func savingAStackMovesItsFilesAndUpdatesTheShelf() throws {
        let src = temp(), dest = temp(), shelfDir = temp()
        defer { for d in [src, dest, shelfDir] { try? FileManager.default.removeItem(at: d) } }
        let persistence = FlingShelfPersistence(url: shelfDir.appendingPathComponent("shelf.json"))
        let m = model(); m.shelfPersistence = persistence
        let stack = UUID()
        let a = file("a.txt", in: src), b = file("b.txt", in: src)
        _ = file("a.txt", in: dest, text: "already here")
        m.addToShelf([a, b], origin: .fling(peer: "Mac B"), stack: stack)
        let result = m.saveStack(stack, to: dest)
        #expect(result == .success(2))
        #expect(!FileManager.default.fileExists(atPath: a.path) && !FileManager.default.fileExists(atPath: b.path))
        let urls = Set(m.shelf.map(\.url.lastPathComponent))
        #expect(urls == ["a 2.txt", "b.txt"], "a name that is taken gets a number: \(urls)")
        #expect(m.shelf.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) && $0.url.deletingLastPathComponent().path == dest.path })
        #expect(try String(contentsOf: dest.appendingPathComponent("a.txt")) == "already here")
        #expect(Set(persistence.load().records.map { URL(fileURLWithPath: $0.path).lastPathComponent }) == urls)
    }

    @Test func aFailedSaveLeavesTheFilesAndTheShelfAlone() throws {
        let src = temp(); defer { try? FileManager.default.removeItem(at: src) }
        let notAFolder = file("plain.txt", in: src)
        let m = model(); let stack = UUID()
        let a = file("a.txt", in: src), b = file("b.txt", in: src)
        m.addToShelf([a, b], origin: .fling(peer: "Mac B"), stack: stack)
        let result = m.saveStack(stack, to: notAFolder)
        if case .success = result { Issue.record("saving into a plain file must fail") }
        #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
        #expect(Set(m.shelf.map(\.url)) == [a, b])
        // A missing file stops the move and puts back what already moved.
        let dest = temp(); defer { try? FileManager.default.removeItem(at: dest) }
        try FileManager.default.removeItem(at: b)
        let again = m.saveStack(stack, to: dest)
        if case .success = again { Issue.record("a missing file must fail") }
        #expect(FileManager.default.fileExists(atPath: a.path), "the file that moved first was put back")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dest.path))?.isEmpty == true)
    }

    /// REG-696: dragging a stack out offers copies of every file, never moves.
    @Test func draggingAStackOutOffersCopiesOfEveryFile() {
        let urls = (1...3).map { URL(fileURLWithPath: "/tmp/stack-\($0).png") }
        let writers = FlingStackDrag.writers(for: urls)
        #expect(writers.count == 3)
        #expect(writers.compactMap { $0 as? NSURL }.map { $0 as URL } == urls)
        #expect(FlingStackDrag.operationMask == .copy)
    }
}
