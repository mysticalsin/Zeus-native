import Foundation

/// A screen rectangle in points, origin at the bottom left, y up. Same axes as `NSScreen`.
public struct DockClearanceRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Bands a desktop card stays out of. The inputs are the screen frame and the visible frame.
/// A showing Dock already sits outside the visible frame, so no second band is added there.
/// When the Dock is hidden, those frames do not name its edge. The same 96 point band is then
/// reserved on the bottom, the left, and the right.
public enum DockClearance {
    public static let menuBarHeight = 40.0
    public static let hiddenDockBand = 96.0

    public static func reserved(frame: DockClearanceRect, visible: DockClearanceRect) -> [DockClearanceRect] {
        var reserved = [
            DockClearanceRect(x: frame.x, y: frame.y + frame.height - menuBarHeight, width: frame.width, height: menuBarHeight),
        ]
        let dockShowing = visible.x > frame.x + 1
            || visible.y > frame.y + 1
            || visible.x + visible.width < frame.x + frame.width - 1
        if !dockShowing {
            reserved.append(DockClearanceRect(x: frame.x, y: frame.y, width: hiddenDockBand, height: frame.height))
            reserved.append(DockClearanceRect(x: frame.x + frame.width - hiddenDockBand, y: frame.y, width: hiddenDockBand, height: frame.height))
            reserved.append(DockClearanceRect(x: frame.x, y: frame.y, width: frame.width, height: hiddenDockBand))
        }
        return reserved
    }
}
