import Foundation

/// A rectangle in the engine's one coordinate space: origin at the top left, y growing downward, the same as
/// Accessibility reports. The app converts from and to AppKit at its own edge.
public struct TileRect: Equatable, Hashable, Sendable {
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

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// No area, or a size that is not a positive number.
    public var isEmpty: Bool { !(width > 0 && height > 0) }

    /// The rect shrunk by `distance` on all four sides, never past its centre line, so it cannot invert.
    /// A negative or unreadable distance counts as none.
    public func inset(by distance: Double) -> TileRect {
        let rect = sanitized
        let d = distance.isFinite ? max(distance, 0) : 0
        let dx = min(d, rect.width / 2)
        let dy = min(d, rect.height / 2)
        return TileRect(x: rect.x + dx, y: rect.y + dy, width: rect.width - 2 * dx, height: rect.height - 2 * dy)
    }

    /// True when the two rects share area. Touching edges do not count, and an empty rect overlaps nothing.
    public func overlaps(_ other: TileRect) -> Bool {
        guard !isEmpty, !other.isEmpty else { return false }
        return minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }

    /// This rect, or an empty one at the origin when a part is not a number or the size is negative.
    var sanitized: TileRect {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite, width >= 0, height >= 0 else {
            return TileRect(x: 0, y: 0, width: 0, height: 0)
        }
        return self
    }
}

/// Turns a split tree into one frame per window. Pure and deterministic.
public enum TileFrames {
    /// The display rect shrunk by the outer gap on all four sides, never inverted.
    public static func usableRect(display: TileRect, outerGap: Double) -> TileRect {
        display.inset(by: outerGap)
    }

    /// The frames of `tree` on `display`, with the config's outer and inner gaps.
    public static func frames(of tree: TileTree, display: TileRect, config: TileConfig) -> [TileWindowID: TileRect] {
        guard let root = tree.root else { return [:] }
        return frames(root, in: usableRect(display: display, outerGap: config.outerGap), innerGap: config.innerGap)
    }

    /// The frames of `node` filling `rect`. A leaf takes the whole rect. A split removes the inner gap once
    /// along its axis, gives the first child that length times the ratio, and the second child the rest after
    /// the gap. Edges are rounded to whole points once, at the end, so shared edges stay exact: frames never
    /// overlap and no length drifts. Every window gets a frame; with no room they are all empty.
    public static func frames(_ node: TileNode, in rect: TileRect, innerGap: Double) -> [TileWindowID: TileRect] {
        let area = rect.sanitized
        var out: [TileWindowID: TileRect] = [:]
        if area.isEmpty {
            let origin = TileRect(x: roundHalfUp(area.x), y: roundHalfUp(area.y), width: 0, height: 0)
            for window in node.windows { out[window] = origin }
            return out
        }
        let gap = innerGap.isFinite ? max(innerGap, 0) : 0
        let box = Box(minX: area.minX, minY: area.minY, maxX: area.maxX, maxY: area.maxY)
        layout(node, in: box, gap: gap, into: &out)
        return out
    }

    // MARK: Layout

    /// Exact edges, rounded only when a leaf takes its frame.
    private struct Box {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        var frame: TileRect {
            let left = roundHalfUp(minX), right = roundHalfUp(maxX)
            let top = roundHalfUp(minY), bottom = roundHalfUp(maxY)
            return TileRect(x: left, y: top, width: right - left, height: bottom - top)
        }
    }

    private static func layout(_ node: TileNode, in box: Box, gap: Double, into out: inout [TileWindowID: TileRect]) {
        switch node {
        case .leaf(let window):
            out[window] = box.frame
        case .split(let axis, let ratio, _, let first, let second):
            let share = TileRatio.clamp(ratio)
            switch axis {
            case .horizontal:
                let length = box.maxX - box.minX
                let g = min(gap, length)
                let cut = min(box.minX + (length - g) * share, box.maxX)
                let next = min(cut + g, box.maxX)
                layout(first, in: Box(minX: box.minX, minY: box.minY, maxX: cut, maxY: box.maxY), gap: gap, into: &out)
                layout(second, in: Box(minX: next, minY: box.minY, maxX: box.maxX, maxY: box.maxY), gap: gap, into: &out)
            case .vertical:
                let length = box.maxY - box.minY
                let g = min(gap, length)
                let cut = min(box.minY + (length - g) * share, box.maxY)
                let next = min(cut + g, box.maxY)
                layout(first, in: Box(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: cut), gap: gap, into: &out)
                layout(second, in: Box(minX: box.minX, minY: next, maxX: box.maxX, maxY: box.maxY), gap: gap, into: &out)
            }
        }
    }

    /// Rounds halves up. Unlike the default rounding, moving a value by a whole number never changes how it
    /// rounds, so a layout keeps its sizes when a display sits at a negative origin.
    private static func roundHalfUp(_ value: Double) -> Double { (value + 0.5).rounded(.down) }
}
