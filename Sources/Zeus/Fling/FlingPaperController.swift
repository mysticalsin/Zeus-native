import AppKit
import SwiftUI
import ZeusCore

/// How a paper sits on screen: above other apps, on every Space and over full-screen apps, never the key window.
enum FlingPaperFlags {
    static let level: NSWindow.Level = .floating
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
}

private final class FlingPaperPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FlingPaperHostingView<Content: View>: NSHostingView<Content> {
    var onPinch: (() -> Void)?
    private var pinched: CGFloat = 0
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func magnify(with event: NSEvent) {
        pinched += event.magnification
        if event.phase == .ended || event.phase == .cancelled {
            if pinched < -0.15 { onPinch?() }
            pinched = 0
        }
    }
}

struct FlingPaperView: View {
    let url: URL
    let peer: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 48, height: 48)
            Text(url.lastPathComponent).font(TopBarStyle.label(10.5, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
            Text("from \(peer)").font(TopBarStyle.label(9.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
        }
        .padding(10)
        .frame(width: FlingPaperController.paperSize.width, height: FlingPaperController.paperSize.height)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.storm.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .overlay { FlingStackDragSource(urls: [url], onClick: { NSWorkspace.shared.open(url) }) }
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.cloudSecondary)
                    .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain).padding(6)
            .accessibilityLabel("Close \(url.lastPathComponent)")
        }
        .accessibilityElement(children: .contain)
    }
}

/// Floating papers for arrivals, off by default. A paper is a window and nothing more: closing it never touches the
/// Shelf or the file.
@MainActor
final class FlingPaperController {
    static let paperSize = CGSize(width: 180, height: 120)

    struct Paper {
        let id: UUID
        let url: URL
        let peer: String
        let panel: NSPanel
    }

    private(set) var papers: [Paper] = []
    private let area: () -> CGRect
    private let present: Bool
    private var placed = 0

    init(area: @escaping () -> CGRect = {
            (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
         },
         present: Bool = true) {
        self.area = area
        self.present = present
    }

    func show(urls: [URL], from peer: String) {
        for url in urls {
            let id = UUID()
            let panel = FlingPaperPanel(contentRect: CGRect(origin: .zero, size: Self.paperSize), styleMask: FlingPaperFlags.styleMask, backing: .buffered, defer: false)
            panel.level = FlingPaperFlags.level
            panel.collectionBehavior = FlingPaperFlags.collectionBehavior
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true
            let host = FlingPaperHostingView(rootView: FlingPaperView(url: url, peer: peer, close: { [weak self] in self?.close(id) }))
            host.onPinch = { [weak self] in self?.group() }
            panel.contentView = host
            panel.setContentSize(Self.paperSize)
            panel.setFrameOrigin(FlingGeometry.paperOrigin(index: placed, paper: Self.paperSize, in: area()))
            placed += 1
            papers.append(Paper(id: id, url: url, peer: peer, panel: panel))
            if present { panel.orderFrontRegardless() }
        }
    }

    func close(_ id: UUID) {
        guard let index = papers.firstIndex(where: { $0.id == id }) else { return }
        papers[index].panel.orderOut(nil)
        papers.remove(at: index)
    }

    func closeAll() {
        for paper in papers { paper.panel.orderOut(nil) }
        papers.removeAll()
        placed = 0
    }

    /// Fans the open papers into one stack where the first one sits.
    func group() {
        guard let anchor = papers.first?.panel.frame.origin else { return }
        let fan = FlingGeometry.stackFan(count: papers.count)
        for (index, paper) in papers.enumerated() where !fan.isEmpty {
            let offset = fan[min(index, fan.count - 1)]
            paper.panel.setFrameOrigin(CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y))
        }
    }
}
