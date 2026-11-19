import Foundation

/// One tile of the layout picture, in a 0 to 1 square over its display. It names a window by id only: no title
/// and no app, so the picture can be drawn and logged without revealing what is open.
public struct TilingPictureTile: Equatable, Sendable {
    public var window: TileWindowID
    public var rect: TileRect
    public var isFocused: Bool

    public init(window: TileWindowID, rect: TileRect, isFocused: Bool) {
        self.window = window
        self.rect = rect
        self.isFocused = isFocused
    }
}

/// One display in the layout picture.
public struct TilingPictureDisplay: Equatable, Sendable {
    public var displayID: UInt32
    /// Width over height.
    public var aspect: Double
    public var tiles: [TilingPictureTile]

    public init(displayID: UInt32, aspect: Double, tiles: [TilingPictureTile]) {
        self.displayID = displayID
        self.aspect = aspect
        self.tiles = tiles
    }
}

/// The current layout as a picture the section draws. Pure.
public enum TilingPicture {
    /// One entry per display, left to right (then top to bottom). A tile is the window's engine frame as a
    /// share of its whole display, so the menu bar, the outer gap and the inner gap all show. A tree for a
    /// display that is gone is not drawn, and a display with no size is left out.
    public static func make(displays: [TileDisplay], trees: [UInt32: TileTree], config: TileConfig,
                            focused: TileWindowID?) -> [TilingPictureDisplay] {
        let sorted = displays.sorted { ($0.frame.x, $0.frame.y, $0.id) < ($1.frame.x, $1.frame.y, $1.id) }
        return sorted.compactMap { display in
            let whole = display.frame
            guard whole.width > 0, whole.height > 0, whole.width.isFinite, whole.height.isFinite else { return nil }
            var tiles: [TilingPictureTile] = []
            if let tree = trees[display.id] {
                let frames = TileFrames.frames(of: tree, display: display.visibleFrame, config: config)
                for window in tree.windows {
                    guard let frame = frames[window], !frame.isEmpty else { continue }
                    let share = TileRect(x: (frame.x - whole.x) / whole.width, y: (frame.y - whole.y) / whole.height,
                                         width: frame.width / whole.width, height: frame.height / whole.height)
                    tiles.append(TilingPictureTile(window: window, rect: share, isFocused: window == focused))
                }
            }
            return TilingPictureDisplay(displayID: display.id, aspect: whole.width / whole.height, tiles: tiles)
        }
    }
}
