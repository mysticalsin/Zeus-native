import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZeusCore

/// What the Shelf draws for its items: a file, or a stack of files that arrived together.
enum ShelfCellModel: Equatable, Identifiable {
    case item(TopBarModel.ShelfItem)
    case stack(id: UUID, items: [TopBarModel.ShelfItem])

    var id: UUID {
        switch self {
        case .item(let item): item.id
        case .stack(let id, _): id
        }
    }
}

enum ShelfStacks {
    /// Items that share a stack id (two or more) become one stack cell at the place of the first of them; everything
    /// else stays a file. A stack with one file left is just a file.
    static func cells(_ items: [TopBarModel.ShelfItem]) -> [ShelfCellModel] {
        var counts: [UUID: Int] = [:]
        for item in items { if let id = item.stackID { counts[id, default: 0] += 1 } }
        var placed: Set<UUID> = []
        var cells: [ShelfCellModel] = []
        for item in items {
            if let id = item.stackID, counts[id, default: 0] > 1 {
                guard placed.insert(id).inserted else { continue }
                cells.append(.stack(id: id, items: items.filter { $0.stackID == id }))
            } else {
                cells.append(.item(item))
            }
        }
        return cells
    }
}

enum ShelfStackError: Error, Equatable { case notAFolder, missingFile(String), moveFailed(String), noSuchStack }

extension TopBarModel {
    /// Puts items into one new stack. One item is not a stack.
    @discardableResult
    func groupShelfItems(_ ids: [UUID]) -> UUID? {
        let chosen = shelf.indices.filter { ids.contains(shelf[$0].id) }
        guard chosen.count > 1 else { return nil }
        let stack = UUID()
        for index in chosen { shelf[index].stackID = stack }
        persistShelf()
        return stack
    }

    func ungroupStack(_ stack: UUID) {
        for index in shelf.indices where shelf[index].stackID == stack { shelf[index].stackID = nil }
        persistShelf()
    }

    /// Moves every file of a stack into `folder` (a taken name gets a number), then points the Shelf at the new
    /// places. If any file cannot move, the ones that did are put back and the Shelf is left as it was.
    func saveStack(_ stack: UUID, to folder: URL) -> Result<Int, ShelfStackError> {
        let indices = shelf.indices.filter { shelf[$0].stackID == stack }
        guard !indices.isEmpty else { return .failure(.noSuchStack) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return .failure(.notAFolder) }
        let fm = FileManager.default
        var taken = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        var moved: [(from: URL, to: URL, index: Int)] = []
        for index in indices {
            let source = shelf[index].url
            guard fm.fileExists(atPath: source.path) else { rollback(moved); return .failure(.missingFile(source.lastPathComponent)) }
            let name = FlingNames.freeName(source.lastPathComponent, taken: taken)
            let target = folder.appendingPathComponent(name)
            do { try fm.moveItem(at: source, to: target) } catch { rollback(moved); return .failure(.moveFailed(source.lastPathComponent)) }
            taken.insert(name)
            moved.append((source, target, index))
        }
        for entry in moved { shelf[entry.index].url = entry.to }
        persistShelf()
        return .success(moved.count)
    }

    private func rollback(_ moved: [(from: URL, to: URL, index: Int)]) {
        for entry in moved.reversed() { try? FileManager.default.moveItem(at: entry.to, to: entry.from) }
    }
}

enum FlingStackDrag {
    /// A drag out of Zeus into Finder or another app copies; it never moves what is on the Shelf.
    static let operationMask: NSDragOperation = .copy

    static func writers(for urls: [URL]) -> [NSPasteboardWriting] { urls.map { $0 as NSURL } }
}

/// Starts a multi-file drag from a stack cell and reports a plain click, which opens the stack.
struct FlingStackDragSource: NSViewRepresentable {
    let urls: [URL]
    let onClick: () -> Void

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.urls = urls
        view.onClick = onClick
    }

    final class DragView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var onClick: () -> Void = {}
        private var dragged = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { FlingStackDrag.operationMask }
        override func mouseDown(with event: NSEvent) { dragged = false }
        override func mouseDragged(with event: NSEvent) {
            guard !dragged, !urls.isEmpty else { return }
            dragged = true
            let items = FlingStackDrag.writers(for: urls).map { writer -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: writer)
                if let url = (writer as? NSURL) as URL? {
                    item.setDraggingFrame(NSRect(x: 0, y: 0, width: 40, height: 40), contents: NSWorkspace.shared.icon(forFile: url.path))
                }
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }
        override func mouseUp(with event: NSEvent) { if !dragged { onClick() } }
    }
}

/// A stack as one cell: three fanned thumbnails and a count.
struct FlingStackCell: View {
    let stack: UUID
    let items: [TopBarModel.ShelfItem]
    let topBar: TopBarModel
    let open: () -> Void

    private var from: String {
        if case .fling(let peer) = items.first?.origin { return peer }
        return "Shelf"
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 44, height: 44)
                        .rotationEffect(.degrees(Double(index - 1) * 7))
                        .offset(x: CGFloat(index - 1) * 5, y: CGFloat(index) * -2)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                Text("\(items.count)").font(TopBarStyle.label(10, .bold)).foregroundStyle(Color.black)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Theme.bolt))
                    .offset(x: 24, y: 22)
            }
            .frame(width: 60, height: 52)
            Text("\(items.count) files").font(TopBarStyle.label(10)).foregroundStyle(Theme.cloudPrimary).lineLimit(1).frame(width: 84)
            Text(from).font(TopBarStyle.label(9)).foregroundStyle(Theme.cloudQuiet).lineLimit(1).frame(width: 84)
        }
        .padding(6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { FlingStackDragSource(urls: items.map(\.url), onClick: open) }
        .contextMenu {
            Button("Open stack") { open() }
            if let fling = topBar.fling, fling.isEnabled {
                Menu("Fling to") {
                    ForEach(fling.nearby.filter(\.paired)) { peer in
                        Button(peer.name) { fling.send(items, to: .peer(id: peer.id), gesture: .menu) }
                    }
                    Button("AirDrop") { fling.send(items, to: .airDrop, gesture: .menu) }
                }
            }
            Button("Save stack to folder…") { FlingStackFolderPicker.choose { folder in _ = topBar.saveStack(stack, to: folder) } }
            Button("Ungroup") { topBar.ungroupStack(stack) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stack of \(items.count) files from \(from)")
        .accessibilityAddTraits(.isButton)
    }
}

enum FlingStackFolderPicker {
    @MainActor
    static func choose(_ done: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { done(url) }
        }
    }
}

/// The open stack: a back chevron and its files in a row. Escape also goes back.
struct FlingStackRibbon: View {
    let items: [TopBarModel.ShelfItem]
    let topBar: TopBarModel
    let back: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.cloudPrimary)
                    .frame(width: 28, height: 52).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .ownedJourneyControl("fling.stack.back")
            .accessibilityLabel("Back to the Shelf")
            ForEach(items) { item in ShelfCell(item: item, topBar: topBar) }
        }
    }
}
