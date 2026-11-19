import AppKit
import SwiftUI

/// Renders a SwiftUI view offscreen the way the snapshot renderer does and answers questions about its pixels,
/// so a test can tell text that is drawn but invisible (dark on dark) from text a person can read.
@MainActor
struct RenderedPixelProbe {
    let width: Int, height: Int
    private let bytes: [UInt8]

    init?<Content: View>(_ view: Content, width: CGFloat? = nil) {
        let renderer = ImageRenderer(content: view.frame(width: width).fixedSize(horizontal: width != nil, vertical: true))
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        self.width = image.width
        self.height = image.height
        self.bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    /// Relative luminance 0...1 of the pixel at x, y (y counted from the top).
    func luminance(_ x: Int, _ y: Int) -> Double {
        let i = (y * width + x) * 4
        func lin(_ v: UInt8) -> Double { let c = Double(v) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(bytes[i]) + 0.7152 * lin(bytes[i + 1]) + 0.0722 * lin(bytes[i + 2])
    }

    /// How many pixels in the rows `rows` (from the top) and inside `inset` of the sides are at least `minimum` bright.
    func brightPixels(rows: Range<Int>, inset: Int = 12, minimum: Double = 0.3) -> Int {
        var count = 0
        for y in max(0, rows.lowerBound)..<min(height, rows.upperBound) {
            for x in inset..<max(inset, width - inset) where luminance(x, y) >= minimum { count += 1 }
        }
        return count
    }
}
