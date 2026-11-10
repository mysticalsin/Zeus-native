import AppKit
import ScreenCaptureKit
import ZeusCore

/// Captures every display (ZEUS's own windows excluded), longest side 1280 px, JPEG 0.8,
/// the cursor's screen first. Returns [] without Screen Recording permission.
@MainActor
enum ScreenCapture {
    static func captureAll() async -> [ScreenShot] {
        guard CGPreflightScreenCaptureAccess() else { return [] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownApps = content.applications.filter { $0.processID == ownPID }
            let mouse = NSEvent.mouseLocation

            var captured: [(shot: (Data, Int, Int, CGRect), hasCursor: Bool)] = []
            for display in content.displays {
                guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
                let frame = screen.frame
                let scale = 1280 / max(frame.width, frame.height)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(frame.width * scale)
                configuration.height = Int(frame.height * scale)
                configuration.showsCursor = false
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard let jpeg = NSBitmapImageRep(cgImage: image)
                    .representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { continue }
                captured.append(((jpeg, image.width, image.height, frame), frame.contains(mouse)))
            }

            let ordered = captured.filter(\.hasCursor) + captured.filter { !$0.hasCursor }
            return ordered.enumerated().map { index, item in
                let (jpeg, width, height, frame) = item.shot
                var label = "screen \(index + 1) of \(ordered.count)"
                if item.hasCursor { label += " — cursor is on this screen (primary focus)" }
                label += " (image dimensions: \(width)x\(height) pixels)"
                return ScreenShot(jpegData: jpeg, label: label, pixelWidth: width, pixelHeight: height, displayFrame: frame)
            }
        } catch {
            NSLog("[ZEUS] screen capture failed: %@", String(describing: error))
            return []
        }
    }

    /// Screenshot pixels (top-left origin) → global AppKit point (bottom-left origin).
    static func globalPoint(x: Int, y: Int, on shot: ScreenShot) -> CGPoint {
        if let mapped = PresentPointMapping.screenPoint(x: x, y: y, screen: 1, in: [shot]) { return mapped }
        let frame = shot.displayFrame
        let px = min(max(Double(x), 0), Double(shot.pixelWidth))
        let py = min(max(Double(y), 0), Double(shot.pixelHeight))
        return CGPoint(
            x: frame.minX + px * frame.width / Double(shot.pixelWidth),
            y: frame.maxY - py * frame.height / Double(shot.pixelHeight)
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
