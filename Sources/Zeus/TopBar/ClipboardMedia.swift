import AppKit
import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ZeusCore

/// Images and files on the Clipboard page: what is read off the pasteboard, the saved picture cache, thumbnails,
/// copying an item back, and the drag-out provider.
@MainActor
enum ClipboardMedia {
    /// ~/Library/Caches/Zeus/clipboard: the pictures behind image items. Pruned to what the history still holds.
    static var directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Zeus/clipboard", isDirectory: true)

    private static let thumbnails = NSCache<NSString, NSImage>()
    /// Pictures larger than this are not kept (a copied 8K screenshot is not worth a gigabyte of history).
    static let maxBytes = 25_000_000

    static func url(for file: String) -> URL { directory.appendingPathComponent(file) }

    /// What a pasteboard holds that the Text path does not cover. Files win over a picture, a picture over text
    /// only when there is no text (Finder puts both a name and an icon on the board).
    enum Read {
        case files([URL])
        case image(file: String, width: Int, height: Int)
        case none
    }

    static func read(_ board: NSPasteboard) -> Read {
        let urls = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty { return .files(urls) }
        guard board.string(forType: .string) == nil,
              board.canReadObject(forClasses: [NSImage.self], options: nil),
              let image = (board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
              let saved = save(image) else { return .none }
        return .image(file: saved.file, width: saved.width, height: saved.height)
    }

    /// Saves a picture as PNG named by its content hash, so the same picture is one file.
    static func save(_ image: NSImage) -> (file: String, width: Int, height: Int)? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]), png.count <= maxBytes else { return nil }
        let hash = SHA256.hash(data: png).prefix(10).map { String(format: "%02x", $0) }.joined()
        let name = hash + ".png"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = url(for: name)
        if !FileManager.default.fileExists(atPath: target.path) { try? png.write(to: target, options: .atomic) }
        return (name, rep.pixelsWide, rep.pixelsHigh)
    }

    /// Drops pictures the history no longer holds.
    static func prune(keeping: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where !keeping.contains(name) { try? FileManager.default.removeItem(at: url(for: name)) }
    }

    /// A small picture for a row: the saved image, an image file's contents, or a file's Finder icon.
    static func thumbnail(for entry: ClipboardEntry, side: CGFloat = 44) -> NSImage? {
        let source: URL?
        switch entry.kind {
        case .image: source = entry.imageFile.map(url(for:))
        case .file: source = entry.filePaths.first.map { URL(fileURLWithPath: $0) }
        default: source = nil
        }
        guard let source else { return nil }
        let key = "\(source.path)@\(Int(side))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let image: NSImage?
        if UTType(filenameExtension: source.pathExtension)?.conforms(to: .image) == true,
           let src = CGImageSourceCreateWithURL(source as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                  kCGImageSourceCreateThumbnailWithTransform: true,
                                                                  kCGImageSourceThumbnailMaxPixelSize: side * 2] as CFDictionary) {
            image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        } else if entry.kind == .file {
            image = NSWorkspace.shared.icon(forFile: source.path)
        } else {
            image = nil
        }
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    /// Puts an item back on the pasteboard in its own type.
    static func copyBack(_ entry: ClipboardEntry) {
        let board = NSPasteboard.general
        board.clearContents()
        switch entry.kind {
        case .image:
            if let file = entry.imageFile, let image = NSImage(contentsOf: url(for: file)) { board.writeObjects([image]) }
        case .file:
            board.writeObjects(entry.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
        default:
            board.setString(entry.text, forType: .string)
        }
    }

    /// What a drag out of the row carries: the saved PNG, the file, or the text.
    static func dragProvider(for entry: ClipboardEntry) -> NSItemProvider {
        switch entry.kind {
        case .image:
            if let file = entry.imageFile, let provider = NSItemProvider(contentsOf: url(for: file)) { return provider }
        case .file:
            if let path = entry.filePaths.first, let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) { return provider }
        default: break
        }
        return NSItemProvider(object: entry.text as NSString)
    }

    /// A made-up picture for snapshots.
    static func sampleImage(seed: Int) -> NSImage {
        let size = NSSize(width: 160, height: 100)
        return NSImage(size: size, flipped: false) { rect in
            let colors: [[NSColor]] = [[.systemPurple, .systemPink], [.systemTeal, .systemBlue], [.systemOrange, .systemYellow]]
            NSGradient(colors: colors[seed % colors.count])?.draw(in: rect, angle: 35)
            NSColor.white.withAlphaComponent(0.7).setFill()
            NSBezierPath(ovalIn: NSRect(x: 100, y: 55, width: 34, height: 34)).fill()
            return true
        }
    }
}
