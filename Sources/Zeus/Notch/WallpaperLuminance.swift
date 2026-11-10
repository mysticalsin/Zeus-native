import AppKit
import ImageIO
import ZeusCore

/// Reads how bright the desktop picture is under the notch, for "Match the halo colour to the wallpaper".
/// A small thumbnail of the wallpaper file is averaged over the strip along the top centre; the result is cached.
@MainActor
final class WallpaperLuminance {
    static let shared = WallpaperLuminance()
    private var cache: (url: URL, at: Date, value: Double?)?

    /// How far to blend the halo toward white right now (0 when the option is off or nothing can be read).
    func whiteAmount(enabled: Bool) -> Double {
        guard enabled, !TopBarStyle.isSnapshot, let value = luminance() else { return 0 }
        return WallpaperBlend.whiteAmount(luminance: value)
    }

    /// Called from the halo's drawing on every frame: answer from the cache first. Asking for the
    /// wallpaper URL is an XPC round trip to the wallpaper service, which cost ~15–45% CPU when it
    /// ran every frame (QA, sample). Re-read at most every 30 s.
    func luminance(now: Date = Date()) -> Double? {
        if let cache, now.timeIntervalSince(cache.at) < 30 { return cache.value }
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            cache = (URL(fileURLWithPath: "/"), now, nil)
            return nil
        }
        if let cache, cache.url == url {
            self.cache = (url, now, cache.value) // same picture: keep the value, restart the clock
            return cache.value
        }
        let value = Self.sample(url)
        cache = (url, now, value)
        return value
    }

    /// Average brightness of the top-centre strip of the picture (where the notch sits), 0...1.
    nonisolated static func sample(_ url: URL) -> Double? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 128,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let w = thumb.width, h = thumb.height
        let strip = CGRect(x: Double(w) * 0.3, y: 0, width: Double(w) * 0.4, height: max(2, Double(h) * 0.1))
        guard let crop = thumb.cropping(to: strip) else { return nil }
        let width = 16, height = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        var r = 0.0, g = 0.0, b = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) { r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]) }
        let n = Double(width * height) * 255
        return WallpaperBlend.luminance(red: r / n, green: g / n, blue: b / n)
    }
}
