import Foundation

/// One connected display, in both coordinate spaces the app touches.
///
/// The engine and Accessibility share one space: origin at the top left of the main display, y growing
/// downward. AppKit puts the origin at the bottom left of the main display with y growing upward. A display
/// converts between the two using its own edges, not the main display's height, so a display above or to the
/// left of the main one, with a negative origin, converts the same way as any other.
public struct TileDisplay: Equatable, Sendable {
    public let id: UInt32
    /// The whole display in AppKit coordinates.
    public let appKitFrame: TileRect
    /// The whole display in engine coordinates.
    public let frame: TileRect
    /// The area windows may use (the menu bar, Dock and notch are out) in engine coordinates.
    public let visibleFrame: TileRect

    /// A display from its AppKit frame, the AppKit visible frame, and where the same display sits in engine
    /// coordinates. `visibleFrame` is derived, so the two spaces cannot disagree.
    public init(id: UInt32, appKitFrame: TileRect, appKitVisibleFrame: TileRect, engineFrame: TileRect) {
        self.id = id
        self.appKitFrame = appKitFrame
        self.frame = engineFrame
        let probe = TileDisplay(id: id, appKitFrame: appKitFrame, frame: engineFrame, visibleFrame: engineFrame)
        self.visibleFrame = probe.toEngine(appKitVisibleFrame)
    }

    private init(id: UInt32, appKitFrame: TileRect, frame: TileRect, visibleFrame: TileRect) {
        self.id = id
        self.appKitFrame = appKitFrame
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    /// A rect on this display, from AppKit coordinates to engine coordinates.
    public func toEngine(_ rect: TileRect) -> TileRect {
        TileRect(x: frame.x + (rect.x - appKitFrame.x),
                 y: frame.y + (appKitFrame.maxY - rect.maxY),
                 width: rect.width, height: rect.height)
    }

    /// A rect on this display, from engine coordinates to AppKit coordinates. The inverse of `toEngine`.
    public func toAppKit(_ rect: TileRect) -> TileRect {
        TileRect(x: appKitFrame.x + (rect.x - frame.x),
                 y: appKitFrame.maxY - (rect.y - frame.y) - rect.height,
                 width: rect.width, height: rect.height)
    }

    /// Where a display with `appKitFrame` sits in engine coordinates when the only thing known is the height
    /// of the main display. Used when the system gives no engine frame for a display.
    public static func engineFrame(appKitFrame: TileRect, mainScreenHeight: Double) -> TileRect {
        TileRect(x: appKitFrame.x, y: mainScreenHeight - appKitFrame.maxY, width: appKitFrame.width, height: appKitFrame.height)
    }
}

public enum TileDisplays {
    /// The display that `frame` overlaps most, in engine coordinates. Equal overlaps go to the lowest id. Nil when
    /// the frame is empty, not a number, or overlaps no display.
    public static func display(for frame: TileRect, in displays: [TileDisplay]) -> TileDisplay? {
        guard frame.x.isFinite, frame.y.isFinite, frame.width.isFinite, frame.height.isFinite, !frame.isEmpty else { return nil }
        var best: (display: TileDisplay, area: Double)?
        for display in displays {
            let area = overlapArea(frame, display.frame)
            guard area > 0 else { continue }
            if let current = best, area < current.area || (area == current.area && display.id > current.display.id) { continue }
            best = (display, area)
        }
        return best?.display
    }

    private static func overlapArea(_ a: TileRect, _ b: TileRect) -> Double {
        let width = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let height = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return width > 0 && height > 0 ? width * height : 0
    }
}
