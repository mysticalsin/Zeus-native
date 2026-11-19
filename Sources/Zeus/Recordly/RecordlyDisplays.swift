import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import ZeusCore

/// Lists the connected displays. Injectable so the page can be rendered and tested with fake displays.
protocol RecordlyDisplayListing {
    @MainActor func displays() -> [RecordlySourceSelection.CatalogSnapshot.Display]
}

/// The real displays. Needs no Screen Recording permission: it reads AppKit and CoreGraphics display state only.
struct RecordlySystemDisplays: RecordlyDisplayListing {
    @MainActor func displays() -> [RecordlySourceSelection.CatalogSnapshot.Display] { RecordlyDisplays.current() }
}

enum RecordlyDisplays {
    /// Main display first (the one with the menu bar), then left to right.
    @MainActor static func current() -> [RecordlySourceSelection.CatalogSnapshot.Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let main = CGMainDisplayID()
        var names: [UInt32: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        let listed = ids.prefix(Int(count)).filter { $0 != 0 }.map { id in
            RecordlySourceSelection.CatalogSnapshot.Display(
                id: id, frame: CGDisplayBounds(id), stableID: stableID(id), name: names[id], isMain: id == main
            )
        }
        return listed.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            return a.frame.minX < b.frame.minX
        }
    }

    /// CGDisplayCreateUUIDFromDisplayID as text: the same display keeps it across unplug and replug.
    static func stableID(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) else { return nil }
        return text as String
    }

    /// One still of a display for the preview stage. Returns nil without touching ScreenCaptureKit unless Screen
    /// Recording is already granted (a preflight check, never a prompt). Never streams.
    static func thumbnail(displayID: UInt32) async -> CGImage? {
        guard RecordlyPermissionGate.screenRecordingReady() else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }),
                  display.width > 0, display.height > 0 else { return nil }
            let configuration = SCStreamConfiguration()
            configuration.width = 640
            configuration.height = max(1, 640 * display.height / display.width)
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            return nil
        }
    }
}
