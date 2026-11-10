import AppKit
import ZeusCore

/// Captures Zeus's own windows for `zeus debug screenshot`, replacing the old
/// `CGWindowListCreateImage(.infinite, .optionOnScreenOnly, ...)` capture: that call needs Screen
/// Recording and returns a blank image when the screen is locked. Capturing only this app's own
/// windows (plus the notch panel) needs no extra permission and works while locked.
enum DebugScreenshot {
    /// Whether `name` is selected by `filter` ("settings", "onboarding", "notch", "all", or nil
    /// for everything). Pure, so the selection logic is unit tested without real windows.
    nonisolated static func matches(name: String, filter: String?) -> Bool {
        guard let filter, filter != "all" else { return true }
        return name.caseInsensitiveCompare(filter) == .orderedSame
    }

    /// Captures each window in `windows` that matches `filter`, writing `<base>-<name>.png`.
    /// Returns the paths actually written.
    @MainActor
    static func capture(windows: [(name: String, window: NSWindow)], base: String, filter: String?) -> [String] {
        let expanded = (base as NSString).expandingTildeInPath
        let baseURL = URL(fileURLWithPath: expanded)
        try? FileManager.default.createDirectory(at: baseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var paths: [String] = []
        for (name, window) in windows where matches(name: name, filter: filter) {
            guard let png = pngData(for: window) else { continue }
            let url = URL(fileURLWithPath: ScreenshotCapturePlan.outputPath(base: expanded, windowName: name, filter: filter))
            if (try? png.write(to: url)) != nil { paths.append(url.path) }
        }
        return paths
    }

    /// Own-window capture, with an own-rendering fallback for when Screen Recording isn't granted.
    @MainActor
    private static func pngData(for window: NSWindow) -> Data? {
        prepareWindow(window)
        guard let contentView = window.contentView, contentView.bounds.width > 0, contentView.bounds.height > 0 else { return nil }
        contentView.layoutSubtreeIfNeeded()
        // QA7 round 11 (report-11.md): `zeus debug screenshot` returned a path but every file it
        // wrote was solid white. Root cause: `NSView.cacheDisplay(in:to:)` asks the view to run its
        // own `draw(_:)` into a bitmap context -- that only produces real pixels for *drawing-based*
        // views. Every window this hook captures (Settings, onboarding, the notch panel) hosts
        // SwiftUI content via `NSHostingView`, which is layer-backed: its pixels live on `CALayer`s
        // Core Animation composites on screen, not in a `draw(_:)` override, so `cacheDisplay` had
        // nothing to call and produced a blank (white) bitmap every time, live window or not.
        // `CALayer.render(in:)` rasterizes the actual composited layer tree instead, which is the
        // right tool for a layer-backed hierarchy (same class of fix as this file's own "screen
        // capture needs CGWindowListCreateImage, but that needs Screen Recording" reasoning above:
        // use the API that matches what's actually being asked to render).
        guard let layer = contentView.layer else {
            // No layer (not layer-backed): a plain NSView's own drawing, which `cacheDisplay` is
            // the right tool for. Nothing in this app's real windows takes this path (every
            // hosted SwiftUI content view is layer-backed), but it keeps this working for any
            // plain-NSView window, now or in a test.
            guard let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return nil }
            contentView.cacheDisplay(in: contentView.bounds, to: rep)
            return rep.representation(using: .png, properties: [:])
        }
        let bounds = contentView.bounds
        let backing = Double(window.backingScaleFactor)
        let pixels = ScreenshotCapturePlan.pixelSize(pointWidth: bounds.width, pointHeight: bounds.height, backingScale: backing)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels.width, pixelsHigh: pixels.height,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        // `size` is the point size, so the context is already point space (1 unit = 1/backingScale pixel).
        // QA20: scaling by backingScale again wrote a 2160x1560 PNG of only the top-left of the 1080x780 window.
        rep.size = bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cgContext = context.cgContext
        let userScale = ScreenshotCapturePlan.contextScale(contextIsPointSpace: true, backingScale: backing)
        if userScale != 1 {
            cgContext.scaleBy(x: userScale, y: userScale)
        }
        cgContext.translateBy(x: 0, y: bounds.height)
        cgContext.scaleBy(x: 1, y: -1)
        layer.render(in: cgContext)
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor
    private static func prepareWindow(_ window: NSWindow) {
        window.layoutIfNeeded()
        guard let contentView = window.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        scrollToTop(contentView)
        contentView.layoutSubtreeIfNeeded()
    }

    private static func scrollToTop(_ view: NSView) {
        if let scroll = view as? NSScrollView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        for sub in view.subviews { scrollToTop(sub) }
    }

    /// Splits `zeus debug screenshot <path> [--window <name>]`'s text into the path and filter.
    nonisolated static func parseArgument(_ text: String?) -> (path: String?, filter: String?) {
        let parts = (text ?? "").split(separator: " ").map(String.init)
        var path: String?
        var filter: String?
        var i = 0
        while i < parts.count {
            if parts[i] == "--window", i + 1 < parts.count {
                filter = parts[i + 1]
                i += 2
            } else {
                if path == nil { path = parts[i] }
                i += 1
            }
        }
        return (path, filter)
    }
}
