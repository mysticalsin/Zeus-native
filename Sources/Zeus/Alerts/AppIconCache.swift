import AppKit
import SwiftUI
import ZeusCore

/// App icons for alerts, rasterised once per bundle id.
///
/// `NSWorkspace.icon(forFile:)` returns a lazily drawn image. In a headless, sandboxed or off-screen pass
/// IconServices draws it as fully transparent pixels, so a non-nil image is not proof of an icon (this is why
/// the Alerts page showed an empty slot). Each icon is drawn into a bitmap once, checked for visible pixels,
/// and its dominant colour is taken from the same pixels. A blank result stays nil and the views draw a glyph.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    struct Entry {
        /// A bitmap-backed icon, or nil when the real icon could not be drawn.
        let image: NSImage?
        /// The icon's dominant colour, or the Zeus accent.
        let accent: Color
    }

    static let pixels = 64
    private var entries: [String: Entry] = [:]

    func entry(for bundleID: String) -> Entry {
        let key = bundleID.lowercased()
        if let cached = entries[key] { return cached }
        let entry = Self.build(bundleID)
        entries[key] = entry
        return entry
    }

    /// Tests and snapshots can pre-fill an entry.
    func seed(_ entry: Entry, for bundleID: String) { entries[bundleID.lowercased()] = entry }

    private static func build(_ bundleID: String) -> Entry {
        let fallback = Entry(image: nil, accent: Theme.accent)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return fallback }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        let side = pixels
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return fallback }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return fallback }
        let rgba = Array(UnsafeBufferPointer(start: data, count: side * side * 4))
        guard !AlertIconPixels.isBlank(rgba: rgba) else { return fallback }
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(rep)
        let accent = AlertAccent.dominantHex(rgba: rgba).map { Color(hex: $0) } ?? Theme.accent
        return Entry(image: image, accent: accent)
    }
}

/// The app's icon at `size`, or a glyph tile when the icon cannot be drawn.
struct AlertAppIcon: View {
    let bundleID: String
    var size: CGFloat = 22
    /// Agent engines (Claude, Codex, ...) use their brand logo instead of an app icon.
    var agentLabel: String?

    var body: some View {
        if let agentLabel {
            EngineBrandLogo(agentLabel: agentLabel, size: size * 0.8)
                .frame(width: size, height: size)
        } else {
            let entry = AppIconCache.shared.entry(for: bundleID)
            if let image = entry.image {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
            } else {
                Image(systemName: AlertAppGlyph.symbol(for: bundleID))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(entry.accent)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(entry.accent.opacity(0.2)))
            }
        }
    }
}
