import AppKit
import CoreGraphics
import Foundation
import ZeusCore

/// Fake displays and states for `Zeus --snapshots`, so visual QA sees the Record page without real monitors,
/// Screen Recording permission or a capture.
enum RecordlySnapshotFixtures {
    private struct FakeDisplays: RecordlyDisplayListing {
        let list: [RecordlySourceSelection.CatalogSnapshot.Display]
        @MainActor func displays() -> [RecordlySourceSelection.CatalogSnapshot.Display] { list }
    }

    static let builtIn = RecordlySourceSelection.CatalogSnapshot.Display(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), stableID: "SNAPSHOT-BUILTIN",
        name: "Built-in Retina Display", isMain: true
    )
    static let external = RecordlySourceSelection.CatalogSnapshot.Display(
        id: 2, frame: CGRect(x: 1512, y: -458, width: 2560, height: 1440), stableID: "SNAPSHOT-LG",
        name: "LG UltraFine", isMain: false
    )

    static let pageStates: [(String, [RecordlySourceSelection.CatalogSnapshot.Display], Bool, RecordlyController.SnapshotState)] = [
        ("idle-one-display", [builtIn], true, .idle),
        ("idle-two-displays", [builtIn, external], true, .idle),
        ("permission-missing", [builtIn, external], false, .idle),
        ("countdown", [builtIn, external], true, .countdown(2)),
        ("recording", [builtIn, external], true, .recording(elapsed: 74)),
        ("saved", [builtIn], true, .saved),
    ]

    @MainActor
    static func controller(
        displays: [RecordlySourceSelection.CatalogSnapshot.Display],
        granted: Bool,
        state: RecordlyController.SnapshotState
    ) -> RecordlyController {
        let suite = "zeus.snapshot.recordly"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let controller = RecordlyController(displayLister: FakeDisplays(list: displays), defaults: defaults)
        controller.seedForSnapshot(granted: granted, thumbnail: granted ? sampleThumbnail() : nil, state: state)
        return controller
    }

    /// A made-up desktop still: a blue to violet sky with a window shape.
    private static func sampleThumbnail() -> CGImage? {
        let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.10, green: 0.16, blue: 0.38, alpha: 1), NSColor(red: 0.45, green: 0.25, blue: 0.65, alpha: 1)])?
                .draw(in: rect, angle: 60)
            NSColor(white: 1, alpha: 0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 300, height: 200), xRadius: 12, yRadius: 12).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
