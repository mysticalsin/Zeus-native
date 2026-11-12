import AppKit

/// The Z-bolt logo (Design/zeus-icon.svg), with fallbacks so a bare `swift run` still shows something.
@MainActor
enum Brand {
    static let menuBarImage: NSImage? = {
        let image = Bundle.main.image(forResource: "MenuBarTemplate")
            ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Zeus")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "Zeus"
        return image
    }()

    static let logo: NSImage = {
        // QA7 round 10 ("opaque white square" on the onboarding brand mark and the drag-helper
        // icon, every round): `NSImage(contentsOf:)` on Logo.pdf rasterizes it onto an opaque
        // white backing regardless of the vector art's own transparency -- confirmed by drawing
        // it into an NSBitmapImageRep and reading a corner pixel (outside the rounded squircle):
        // r=1,g=1,b=1,a=1 from the PDF, vs r=0,g=0,b=0,a=0 from Logo.png at the same pixel. The
        // PNG is a real, already-shipped 128x128 raster of the same art with correct alpha, so it
        // leads here now; the PDF is kept only as a last-resort fallback if the PNG is ever
        // missing from the bundle (better a white-cornered icon than no icon at all).
        if let raster = Bundle.main.image(forResource: "Logo") {
            raster.size = NSSize(width: 22, height: 22)
            return raster
        }
        if let url = Bundle.main.url(forResource: "Logo", withExtension: "pdf"),
           let pdf = NSImage(contentsOf: url) {
            pdf.size = NSSize(width: 22, height: 22)
            return pdf
        }
        return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Zeus") ?? NSImage()
    }()
}
