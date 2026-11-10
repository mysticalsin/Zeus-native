import CoreGraphics
import Foundation

/// Spaces a present coordinate can live in.
///
/// Overlay points are the canvas space: origin at the top-left of one display,
/// y down, in points. That is what the companion and the ink already draw.
/// Every other space converts through AppKit global points (`screen`).
public enum CoordinateSpace: String, Codable, Sendable, Equatable, CaseIterable {
    /// AppKit global points. Origin is the bottom-left of the main display. Y increases upward.
    /// A display to the left or below the main display has a negative origin.
    case screen
    /// Quartz global points. Origin is the top-left of the main display. Y increases downward.
    /// Accessibility element frames use this space.
    case ax
    /// Points local to one display. Origin is that display's bottom-left. Y increases upward.
    case display
    /// Points local to one window. Origin is the window's bottom-left. Y increases upward.
    case window
    /// Pixels of one display, origin at its top-left, y down.
    /// With no capture, this is the backing store: `points * scale` (1x or 2x).
    /// With a capture, this is that image's pixel grid (for example a shot scaled to 1280 on the long side).
    case pixel
    /// Points the overlay draws. Origin is the top-left of one display. Y increases downward.
    case overlay
}

/// How close a ring or trail must land, in physical pixels.
/// 24 px at 1080p (scale 1). 48 px at 4K: scale 2, or a panel at least 3840 px wide.
public enum PresentTolerance {
    public static let ringPixels1080p: Double = 24
    public static let ringPixels4K: Double = 48

    public static func ringPixels(scale: Double, pixelWidth: Int) -> Double {
        if scale >= 2 || pixelWidth >= 3840 { return ringPixels4K }
        return ringPixels1080p
    }

    /// The same budget in points. 24 pt on 1080p and on 2x Retina. 48 pt on a 4K panel at scale 1.
    public static func ringPoints(scale: Double, pixelWidth: Int) -> Double {
        let safe = scale > 0 ? scale : 1
        return ringPixels(scale: safe, pixelWidth: pixelWidth) / safe
    }
}

/// One display the mapper can convert against. Frames are AppKit global points.
public struct DisplayMap: Equatable, Sendable {
    public var id: Int
    public var frame: CGRect
    /// Backing pixels per point. 1 for 1080p, 2 for Retina.
    public var scale: Double

    public init(id: Int, frame: CGRect, scale: Double) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }

    public var pixelWidth: Int {
        let safe = scale > 0 ? scale : 1
        return Int((frame.width * safe).rounded())
    }

    public var pixelHeight: Int {
        let safe = scale > 0 ? scale : 1
        return Int((frame.height * safe).rounded())
    }
}

/// A window frame in AppKit global points.
public struct WindowMap: Equatable, Sendable {
    public var frame: CGRect
    public var displayID: Int

    public init(frame: CGRect, displayID: Int) {
        self.frame = frame
        self.displayID = displayID
    }
}

/// A capture of one display. Pixel size can differ from the backing store.
public struct CaptureMap: Equatable, Sendable {
    public var displayID: Int
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(displayID: Int, pixelWidth: Int, pixelHeight: Int) {
        self.displayID = displayID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Which display, window, or capture a conversion uses.
/// One context names one display. To cross displays, convert to `screen` and then onward with a second context.
public struct MapContext: Equatable, Sendable {
    public var displayID: Int?
    public var window: WindowMap?
    public var capture: CaptureMap?

    public init(displayID: Int? = nil, window: WindowMap? = nil, capture: CaptureMap? = nil) {
        self.displayID = displayID
        self.window = window
        self.capture = capture
    }
}

/// The one coordinate mapper. Converts screen, display, window, AX, and pixels into overlay points.
public protocol CoordinateMapping: Sendable {
    var displays: [DisplayMap] { get }
    /// The display whose top-left is the Quartz origin. Its frame is AppKit `(0, 0, width, height)` on a real Mac.
    var mainDisplayID: Int { get }

    func convert(_ point: CGPoint, from source: CoordinateSpace, to destination: CoordinateSpace, context: MapContext) -> CGPoint?

    func convert(_ rect: CGRect, from source: CoordinateSpace, to destination: CoordinateSpace, context: MapContext) -> CGRect?

    /// The first display whose frame contains `screenPoint` (AppKit global). Nil when none do.
    func display(containing screenPoint: CGPoint) -> DisplayMap?

    func ringPixelTolerance(displayID: Int) -> Double?
    func ringPointTolerance(displayID: Int) -> Double?

    /// Both points are in the same point space (`screen` or `overlay`). Nil when the display is unknown.
    func withinRing(_ point: CGPoint, of target: CGPoint, displayID: Int) -> Bool?
}

extension CoordinateMapping {
    /// Overlay point for `point` on one display.
    public func overlayPoint(_ point: CGPoint, from source: CoordinateSpace, displayID: Int, context: MapContext = MapContext()) -> CGPoint? {
        var ctx = context
        ctx.displayID = displayID
        return convert(point, from: source, to: .overlay, context: ctx)
    }

    public func overlayRect(_ rect: CGRect, from source: CoordinateSpace, displayID: Int, context: MapContext = MapContext()) -> CGRect? {
        var ctx = context
        ctx.displayID = displayID
        return convert(rect, from: source, to: .overlay, context: ctx)
    }
}

/// Value-type mapper. Callers pass display frames in. It does not read `NSScreen` and it does not move the pointer.
public struct ScreenCoordinateMapper: CoordinateMapping {
    public let displays: [DisplayMap]
    public let mainDisplayID: Int

    public init(displays: [DisplayMap], mainDisplayID: Int? = nil) {
        self.displays = displays
        if let mainDisplayID {
            self.mainDisplayID = mainDisplayID
        } else if let primary = displays.first(where: { $0.frame.minX == 0 && $0.frame.minY == 0 }) {
            self.mainDisplayID = primary.id
        } else {
            self.mainDisplayID = displays.first?.id ?? 0
        }
    }

    public func display(containing screenPoint: CGPoint) -> DisplayMap? {
        guard screenPoint.x.isFinite, screenPoint.y.isFinite else { return nil }
        return displays.first { $0.frame.contains(screenPoint) }
    }

    public func ringPixelTolerance(displayID: Int) -> Double? {
        guard let display = display(id: displayID) else { return nil }
        return PresentTolerance.ringPixels(scale: display.scale, pixelWidth: display.pixelWidth)
    }

    public func ringPointTolerance(displayID: Int) -> Double? {
        guard let display = display(id: displayID) else { return nil }
        return PresentTolerance.ringPoints(scale: display.scale, pixelWidth: display.pixelWidth)
    }

    public func withinRing(_ point: CGPoint, of target: CGPoint, displayID: Int) -> Bool? {
        guard let budget = ringPointTolerance(displayID: displayID) else { return nil }
        guard point.x.isFinite, point.y.isFinite, target.x.isFinite, target.y.isFinite else { return nil }
        return hypot(point.x - target.x, point.y - target.y) <= budget
    }

    public func convert(_ point: CGPoint, from source: CoordinateSpace, to destination: CoordinateSpace, context: MapContext) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        guard let screen = toScreen(point, from: source, context: context) else { return nil }
        if destination == .screen { return screen }
        return fromScreen(screen, to: destination, context: context)
    }

    public func convert(_ rect: CGRect, from source: CoordinateSpace, to destination: CoordinateSpace, context: MapContext) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
        let origin = rect.origin
        let far = CGPoint(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height)
        guard let start = convert(origin, from: source, to: destination, context: context),
              let end = convert(far, from: source, to: destination, context: context) else { return nil }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    // MARK: - Axes

    private func toScreen(_ point: CGPoint, from source: CoordinateSpace, context: MapContext) -> CGPoint? {
        switch source {
        case .screen:
            return point
        case .ax:
            guard let main = mainDisplay else { return nil }
            return CGPoint(x: point.x + main.frame.minX, y: main.frame.maxY - point.y)
        case .display:
            guard let display = localDisplay(source, context: context, screen: nil) else { return nil }
            return CGPoint(x: display.frame.minX + point.x, y: display.frame.minY + point.y)
        case .overlay:
            guard let display = localDisplay(source, context: context, screen: nil) else { return nil }
            return CGPoint(x: display.frame.minX + point.x, y: display.frame.maxY - point.y)
        case .window:
            guard let window = context.window else { return nil }
            return CGPoint(x: window.frame.minX + point.x, y: window.frame.minY + point.y)
        case .pixel:
            guard let display = localDisplay(source, context: context, screen: nil) else { return nil }
            guard let size = pixelSize(of: display, context: context) else { return nil }
            let fromLeft = point.x * display.frame.width / size.width
            let fromTop = point.y * display.frame.height / size.height
            return CGPoint(x: display.frame.minX + fromLeft, y: display.frame.maxY - fromTop)
        }
    }

    private func fromScreen(_ point: CGPoint, to destination: CoordinateSpace, context: MapContext) -> CGPoint? {
        switch destination {
        case .screen:
            return point
        case .ax:
            guard let main = mainDisplay else { return nil }
            return CGPoint(x: point.x - main.frame.minX, y: main.frame.maxY - point.y)
        case .display:
            guard let display = localDisplay(destination, context: context, screen: point) else { return nil }
            return CGPoint(x: point.x - display.frame.minX, y: point.y - display.frame.minY)
        case .overlay:
            guard let display = localDisplay(destination, context: context, screen: point) else { return nil }
            return CGPoint(x: point.x - display.frame.minX, y: display.frame.maxY - point.y)
        case .window:
            guard let window = context.window else { return nil }
            return CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        case .pixel:
            guard let display = localDisplay(destination, context: context, screen: point) else { return nil }
            guard let size = pixelSize(of: display, context: context) else { return nil }
            guard display.frame.width > 0, display.frame.height > 0 else { return nil }
            let fromLeft = point.x - display.frame.minX
            let fromTop = display.frame.maxY - point.y
            return CGPoint(x: fromLeft * size.width / display.frame.width, y: fromTop * size.height / display.frame.height)
        }
    }

    private var mainDisplay: DisplayMap? {
        displays.first { $0.id == mainDisplayID }
    }

    private func display(id: Int) -> DisplayMap? {
        displays.first { $0.id == id }
    }

    /// Local spaces need a display. An explicit id wins. Otherwise a capture or a window can name it.
    /// `screen` is set only when converting from global points, so the display under that point can be inferred.
    private func localDisplay(_ space: CoordinateSpace, context: MapContext, screen: CGPoint?) -> DisplayMap? {
        if let id = context.displayID {
            return display(id: id)
        }
        switch space {
        case .pixel:
            if let id = context.capture?.displayID, let found = display(id: id) { return found }
        case .window:
            if let id = context.window?.displayID, let found = display(id: id) { return found }
        case .screen, .ax, .display, .overlay:
            break
        }
        if let screen { return display(containing: screen) }
        return nil
    }

    /// Backing pixels, unless a capture of this same display supplies its own grid.
    private func pixelSize(of display: DisplayMap, context: MapContext) -> CGSize? {
        if let capture = context.capture {
            guard capture.displayID == display.id, capture.pixelWidth > 0, capture.pixelHeight > 0 else { return nil }
            return CGSize(width: capture.pixelWidth, height: capture.pixelHeight)
        }
        let scale = display.scale > 0 ? display.scale : 1
        let width = display.frame.width * scale
        let height = display.frame.height * scale
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}
