import Foundation

/// Which way a split lays out its two children.
public enum TileAxis: String, Codable, Sendable, CaseIterable {
    /// The children sit side by side: columns.
    case horizontal
    /// The children are stacked: rows.
    case vertical

    public var flipped: TileAxis { self == .horizontal ? .vertical : .horizontal }
}

/// One window, as the engine sees it: the owning process and an index the app assigns per app by element
/// identity. ZeusCore treats it as an opaque, ordered value.
public struct TileWindowID: Hashable, Comparable, Codable, Sendable {
    public var pid: Int32
    public var index: Int

    public init(pid: Int32, index: Int) {
        self.pid = pid
        self.index = index
    }

    public static func < (lhs: TileWindowID, rhs: TileWindowID) -> Bool {
        (lhs.pid, lhs.index) < (rhs.pid, rhs.index)
    }
}

/// The share of a split that goes to its first child. Kept away from the ends so no tile shrinks to a sliver.
public enum TileRatio {
    public static let minimum = 0.15
    public static let maximum = 0.85
    public static let standard = 0.5

    /// `value` limited to `minimum ... maximum`. Not a number gives the standard ratio.
    public static func clamp(_ value: Double) -> Double {
        if value.isNaN { return standard }
        return min(max(value, minimum), maximum)
    }
}

/// A slot in the split tree: one window, or a split of two slots.
public indirect enum TileNode: Equatable, Sendable {
    case leaf(window: TileWindowID)
    case split(axis: TileAxis, ratio: Double, pinned: Bool, first: TileNode, second: TileNode)

    /// Every window, first child before second, so left to right and top to bottom.
    public var windows: [TileWindowID] {
        var out: [TileWindowID] = []
        collect(into: &out)
        return out
    }

    /// Splits between the root and the deepest window. A lone window has depth 0.
    public var depth: Int {
        switch self {
        case .leaf: 0
        case .split(_, _, _, let first, let second): 1 + max(first.depth, second.depth)
        }
    }

    public func contains(_ window: TileWindowID) -> Bool {
        switch self {
        case .leaf(let id): id == window
        case .split(_, _, _, let first, let second): first.contains(window) || second.contains(window)
        }
    }

    /// Splits above `window`, or nil when it is not in this tree.
    public func depth(of window: TileWindowID) -> Int? {
        switch self {
        case .leaf(let id):
            return id == window ? 0 : nil
        case .split(_, _, _, let first, let second):
            if let depth = first.depth(of: window) ?? second.depth(of: window) { return depth + 1 }
            return nil
        }
    }

    func isLeaf(_ window: TileWindowID) -> Bool {
        if case .leaf(let id) = self { return id == window }
        return false
    }

    private func collect(into out: inout [TileWindowID]) {
        switch self {
        case .leaf(let id): out.append(id)
        case .split(_, _, _, let first, let second):
            first.collect(into: &out)
            second.collect(into: &out)
        }
    }
}

/// The split tree of one display, and the order its windows were added in.
///
/// `order` always holds exactly the windows in `root`, oldest slot first. It is what "the last added slot"
/// means. It tracks slots, not windows: a swap trades the two ids in it, so the newest slot stays the newest,
/// and a removal only drops one id.
public struct TileTree: Equatable, Sendable {
    public let displayID: UInt32
    public let root: TileNode?
    public let order: [TileWindowID]

    /// A tree over `root`. `order` is repaired to match it: unknown and repeated ids are dropped, and a window
    /// missing from `order` is appended in tree order.
    public init(displayID: UInt32 = 0, root: TileNode? = nil, order: [TileWindowID] = []) {
        self.displayID = displayID
        self.root = root
        let leaves = root?.windows ?? []
        let present = Set(leaves)
        var seen = Set<TileWindowID>()
        var repaired: [TileWindowID] = []
        for id in order where present.contains(id) && seen.insert(id).inserted { repaired.append(id) }
        for id in leaves where seen.insert(id).inserted { repaired.append(id) }
        self.order = repaired
    }

    public var isEmpty: Bool { root == nil }
    public var windows: [TileWindowID] { root?.windows ?? [] }
    public var count: Int { windows.count }
    public var depth: Int { root?.depth ?? 0 }

    public func contains(_ window: TileWindowID) -> Bool { root?.contains(window) ?? false }
}
