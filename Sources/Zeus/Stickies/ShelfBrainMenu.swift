import Foundation
import SwiftUI
import ZeusCore

/// Shelf item menu: save a text file's contents (or a link to any other file) to the brain,
/// or turn a short text file into a sticky.
struct ShelfBrainMenu: View {
    let url: URL
    /// The Shelf item and Fling, when Fling is on: adds a "Fling to" submenu with the nearby Macs and AirDrop.
    var item: TopBarModel.ShelfItem?
    var fling: (any FlingSending)?

    var body: some View {
        if let item, let fling, fling.isEnabled {
            Menu("Fling to") {
                ForEach(fling.nearby.filter(\.paired)) { peer in
                    Button(peer.name) { fling.send([item], to: .peer(id: peer.id), gesture: .menu) }
                }
                Button("AirDrop") { fling.send([item], to: .airDrop, gesture: .menu) }
            }
            Divider()
        }
        Button("Save to Brain…") {
            BrainCaptureWindow.shared.show(title: url.deletingPathExtension().lastPathComponent, body: Self.body(for: url), source: "shelf")
        }
        if let text = Self.text(of: url) {
            Button("Make Sticky") { StickiesController.shared.new(text: text) }
        }
    }

    /// Text and Markdown files up to 200 KB are read; anything else becomes a link to the file.
    static func text(of url: URL) -> String? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        guard ["txt", "md", "markdown", "text"].contains(url.pathExtension.lowercased()), size <= 200_000 else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func body(for url: URL) -> String {
        text(of: url) ?? "From the Zeus shelf: [\(url.lastPathComponent)](\(url.absoluteString))"
    }
}
