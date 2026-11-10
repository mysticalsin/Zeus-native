import AppKit
import Testing
@testable import Zeus

@Suite struct BrandTests {
    @Test @MainActor func logoLoadsWithVectorSize() {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pdf = repoRoot.appendingPathComponent("Resources/Logo.pdf")
        #expect(FileManager.default.fileExists(atPath: pdf.path))
        guard let fileLogo = NSImage(contentsOf: pdf) else {
            Issue.record("Logo.pdf did not load")
            return
        }
        fileLogo.size = NSSize(width: 22, height: 22)
        #expect(fileLogo.size.width == 22)
        #expect(fileLogo.size.height == 22)
        #expect(!Brand.logo.size.width.isZero)
        #expect(!Brand.logo.size.height.isZero)
    }

    /// QA7 round 10: "opaque white square" behind the brand mark and the drag-helper icon, every
    /// round. `NSImage(contentsOf:)` on Logo.pdf rasterized the squircle's rounded-away corners as
    /// opaque white instead of transparent; `Brand.logo` now prefers Logo.png (confirmed correct
    /// alpha) for exactly this reason. Draws the real `Brand.logo` into an off-screen bitmap and
    /// reads a corner pixel -- outside the rounded art, where a passing icon must be transparent.
    @Test @MainActor func logoCornersAreTransparentNotAnOpaqueWhiteSquare() {
        let size = 64
        let image = Brand.logo
        image.size = NSSize(width: size, height: size)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            Issue.record("could not create a bitmap to draw into")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        guard let corner = rep.colorAt(x: 2, y: 2) else {
            Issue.record("no pixel read back at the corner")
            return
        }
        #expect(corner.alphaComponent < 0.1, "corner alpha was \(corner.alphaComponent), expected near-0 (transparent), not an opaque square")
    }
}
