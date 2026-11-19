import Foundation

/// The result of asking for a window to join a tree.
public enum TileInsertResult: Equatable, Sendable {
    case inserted(TileTree)
    /// No slot can take the window within the depth and minimum size limits. The caller leaves it floating.
    case refused
}

/// A reconciled tree and the windows that did not fit.
public struct TileReconcileResult: Equatable, Sendable {
    public var tree: TileTree
    public var refused: [TileWindowID]

    public init(tree: TileTree, refused: [TileWindowID]) {
        self.tree = tree
        self.refused = refused
    }
}

/// Edits to a split tree. Each one returns a new tree; an edit that has nothing to do (an unknown window, an
/// empty tree, a lone window) returns the tree it was given.
public enum TileOps {
    // MARK: Insert

    /// Adds `window` by splitting one slot of `tree` on `display`.
    ///
    /// It tries the focused slot first (when it is in the tree), then the others from the newest to the
    /// oldest, so with nothing focused the newest slot splits. A slot splits along its longer side (columns
    /// when the sides are equal), the existing window first and the new one second, at `config.defaultRatio`.
    /// A slot is used only when the new depth stays within `config.maxDepth` and both halves are at least
    /// `config.minTileSize` wide and tall. If no slot qualifies the result is `.refused`. An empty tree takes
    /// the window as its root without any check, and a window already in the tree changes nothing.
    public static func insert(_ window: TileWindowID, into tree: TileTree, focused: TileWindowID?,
                              display: TileRect, config: TileConfig) -> TileInsertResult {
        guard let root = tree.root else {
            return .inserted(TileTree(displayID: tree.displayID, root: .leaf(window: window), order: [window]))
        }
        if tree.contains(window) { return .inserted(tree) }

        var candidates: [TileWindowID] = []
        if let focused, tree.contains(focused) { candidates.append(focused) }
        for leaf in tree.order.reversed() where !candidates.contains(leaf) { candidates.append(leaf) }

        let usable = TileFrames.usableRect(display: display, outerGap: config.outerGap)
        let slots = TileFrames.frames(root, in: usable, innerGap: config.innerGap)
        func fits(_ rect: TileRect?) -> Bool {
            guard let rect else { return false }
            return rect.width >= config.minTileSize && rect.height >= config.minTileSize
        }
        for leaf in candidates {
            guard let slot = slots[leaf], let depth = root.depth(of: leaf), depth + 1 <= config.maxDepth else { continue }
            let axis: TileAxis = slot.width >= slot.height ? .horizontal : .vertical
            let split = TileNode.split(axis: axis, ratio: config.defaultRatio, pinned: false,
                                       first: .leaf(window: leaf), second: .leaf(window: window))
            let grown = root.replacingLeaf(leaf, with: split)
            let frames = TileFrames.frames(grown, in: usable, innerGap: config.innerGap)
            guard fits(frames[leaf]), fits(frames[window]) else { continue }
            return .inserted(TileTree(displayID: tree.displayID, root: grown, order: tree.order + [window]))
        }
        return .refused
    }

    // MARK: Remove, swap, flip

    /// Takes `window` out. Its sibling subtree takes the parent's whole slot and the tree collapses one level.
    /// No ratio changes, so windows outside that subtree keep their frames.
    public static func remove(_ window: TileWindowID, from tree: TileTree) -> TileTree {
        guard let root = tree.root, tree.contains(window) else { return tree }
        return TileTree(displayID: tree.displayID, root: root.removing(window), order: tree.order)
    }

    /// Exchanges the two windows' slots. Shape, ratios and pins stay as they were. The order is exchanged too,
    /// because it records slots: the newest slot stays the newest after a swap, so the next window still
    /// splits toward the right and bottom.
    public static func swap(_ a: TileWindowID, _ b: TileWindowID, in tree: TileTree) -> TileTree {
        guard let root = tree.root, a != b, tree.contains(a), tree.contains(b) else { return tree }
        let order = tree.order.map { $0 == a ? b : ($0 == b ? a : $0) }
        return TileTree(displayID: tree.displayID, root: root.swapping(a, b), order: order)
    }

    /// Turns the split that directly holds `window` from columns to rows or back, and pins it: a pinned axis is
    /// one the owner chose, and no insert changes an existing split's axis. A lone or unknown window changes
    /// nothing.
    public static func flip(at window: TileWindowID, in tree: TileTree) -> TileTree {
        guard let root = tree.root, let flipped = root.flippingParent(of: window) else { return tree }
        return TileTree(displayID: tree.displayID, root: flipped, order: tree.order)
    }

    // MARK: Ratio

    /// Moves a split edge by `step` (a share of the split, such as 0.05) so `window` grows toward `direction`.
    ///
    /// The nearest ancestor split is used whose axis matches the direction (left and right for columns, up and
    /// down for rows) and in which the window lies on the side whose outer edge that is: the first side for
    /// right and down, the second side for left and up. Right and down add the step to the ratio; left and
    /// up subtract it. The result is clamped. If the nearest match is already at its limit it stays there and
    /// no farther split moves. With no match, or a step that is not a number, nothing changes.
    public static func nudgeRatio(at window: TileWindowID, direction: TileDirection, step: Double,
                                  in tree: TileTree) -> TileTree {
        guard let root = tree.root, step.isFinite, step != 0 else { return tree }
        let result = nudged(root, window: window, direction: direction, delta: abs(step))
        guard result.handled else { return tree }
        return TileTree(displayID: tree.displayID, root: result.node, order: tree.order)
    }

    private static func nudged(_ node: TileNode, window: TileWindowID, direction: TileDirection,
                               delta: Double) -> (node: TileNode, handled: Bool) {
        guard case .split(let axis, let ratio, let pinned, let first, let second) = node else { return (node, false) }
        let inFirst = first.contains(window)
        guard inFirst || second.contains(window) else { return (node, false) }

        // The nearest split is the deepest one, so look below first.
        let inner = nudged(inFirst ? first : second, window: window, direction: direction, delta: delta)
        if inner.handled {
            let rebuilt = inFirst
                ? TileNode.split(axis: axis, ratio: ratio, pinned: pinned, first: inner.node, second: second)
                : TileNode.split(axis: axis, ratio: ratio, pinned: pinned, first: first, second: inner.node)
            return (rebuilt, true)
        }

        let growsLater = direction == .right || direction == .down
        let axisMatches = (axis == .horizontal) == (direction == .left || direction == .right)
        guard axisMatches, inFirst == growsLater else { return (node, false) }
        let moved = TileRatio.clamp(ratio + (growsLater ? delta : -delta))
        return (.split(axis: axis, ratio: moved, pinned: pinned, first: first, second: second), true)
    }

    // MARK: Focus

    /// The window to focus when moving from `window` toward `direction`, chosen from computed frames (so it
    /// works over the union of several displays), not from tree order.
    ///
    /// Candidates are windows whose frame lies entirely beyond the focused frame's edge that way (touching
    /// counts). The best has the longest overlap on the other axis, then the shortest distance across the
    /// gap, then the earliest place in `recency` (most recent first; windows not listed come after), then the
    /// lowest id, so the answer never depends on dictionary order. Nil when nothing is that way, the window has
    /// no frame, or its frame is empty. Windows with empty frames are never chosen. There is no wrap.
    public static func neighbour(of window: TileWindowID, direction: TileDirection,
                                 frames: [TileWindowID: TileRect], recency: [TileWindowID] = []) -> TileWindowID? {
        guard let from = frames[window], !from.isEmpty else { return nil }
        var rank: [TileWindowID: Int] = [:]
        for (index, id) in recency.enumerated() where rank[id] == nil { rank[id] = index }

        var best: Candidate?
        for (id, frame) in frames where id != window && !frame.isEmpty {
            let distance: Double
            let overlap: Double
            switch direction {
            case .right:
                guard frame.minX >= from.maxX else { continue }
                distance = frame.minX - from.maxX
                overlap = overlapLength(from.minY, from.maxY, frame.minY, frame.maxY)
            case .left:
                guard frame.maxX <= from.minX else { continue }
                distance = from.minX - frame.maxX
                overlap = overlapLength(from.minY, from.maxY, frame.minY, frame.maxY)
            case .down:
                guard frame.minY >= from.maxY else { continue }
                distance = frame.minY - from.maxY
                overlap = overlapLength(from.minX, from.maxX, frame.minX, frame.maxX)
            case .up:
                guard frame.maxY <= from.minY else { continue }
                distance = from.minY - frame.maxY
                overlap = overlapLength(from.minX, from.maxX, frame.minX, frame.maxX)
            }
            let candidate = Candidate(id: id, overlap: overlap, distance: distance, rank: rank[id] ?? Int.max)
            if best == nil || candidate.beats(best!) { best = candidate }
        }
        return best?.id
    }

    private struct Candidate {
        var id: TileWindowID
        var overlap: Double
        var distance: Double
        var rank: Int

        func beats(_ other: Candidate) -> Bool {
            if overlap != other.overlap { return overlap > other.overlap }
            if distance != other.distance { return distance < other.distance }
            if rank != other.rank { return rank < other.rank }
            return id < other.id
        }
    }

    private static func overlapLength(_ aMin: Double, _ aMax: Double, _ bMin: Double, _ bMax: Double) -> Double {
        max(0, min(aMax, bMax) - max(aMin, bMin))
    }

    // MARK: Reconcile

    /// Brings `tree` in line with the windows that are eligible now. Ids no longer eligible are removed, new
    /// ones are inserted in `order` (discovery order; eligible ids missing from it come last, lowest first),
    /// and the rest stay where they are. Windows in `config.floating` are not tiled. Each new window splits the
    /// newest slot, as an insert with nothing focused does. Returns the tree and the new windows that did not
    /// fit, in the order they were tried.
    public static func reconcile(tree: TileTree, eligible: Set<TileWindowID>, order: [TileWindowID],
                                 display: TileRect, config: TileConfig) -> TileReconcileResult {
        let wanted = eligible.subtracting(config.floating)
        var current = tree
        for window in tree.windows where !wanted.contains(window) { current = remove(window, from: current) }

        var known = Set(current.windows)
        var queue: [TileWindowID] = []
        for window in order where wanted.contains(window) && known.insert(window).inserted { queue.append(window) }
        for window in wanted.sorted() where known.insert(window).inserted { queue.append(window) }

        var refused: [TileWindowID] = []
        for window in queue {
            switch insert(window, into: current, focused: nil, display: display, config: config) {
            case .inserted(let next): current = next
            case .refused: refused.append(window)
            }
        }
        return TileReconcileResult(tree: current, refused: refused)
    }
}

// MARK: Tree transforms

private extension TileNode {
    /// The tree with the leaf for `target` replaced by `replacement`.
    func replacingLeaf(_ target: TileWindowID, with replacement: TileNode) -> TileNode {
        switch self {
        case .leaf(let id):
            return id == target ? replacement : self
        case .split(let axis, let ratio, let pinned, let first, let second):
            return .split(axis: axis, ratio: ratio, pinned: pinned,
                          first: first.replacingLeaf(target, with: replacement),
                          second: second.replacingLeaf(target, with: replacement))
        }
    }

    /// The tree without `target`, or nil when that leaves nothing. The sibling replaces the parent split.
    func removing(_ target: TileWindowID) -> TileNode? {
        switch self {
        case .leaf(let id):
            return id == target ? nil : self
        case .split(let axis, let ratio, let pinned, let first, let second):
            switch (first.removing(target), second.removing(target)) {
            case (nil, nil): return nil
            case (nil, let rest?): return rest
            case (let rest?, nil): return rest
            case (let a?, let b?): return .split(axis: axis, ratio: ratio, pinned: pinned, first: a, second: b)
            }
        }
    }

    /// The tree with the windows `a` and `b` trading places.
    func swapping(_ a: TileWindowID, _ b: TileWindowID) -> TileNode {
        switch self {
        case .leaf(let id):
            return .leaf(window: id == a ? b : (id == b ? a : id))
        case .split(let axis, let ratio, let pinned, let first, let second):
            return .split(axis: axis, ratio: ratio, pinned: pinned,
                          first: first.swapping(a, b), second: second.swapping(a, b))
        }
    }

    /// The tree with the split that directly holds `target` turned over and pinned, or nil when there is none.
    func flippingParent(of target: TileWindowID) -> TileNode? {
        guard case .split(let axis, let ratio, let pinned, let first, let second) = self else { return nil }
        if first.isLeaf(target) || second.isLeaf(target) {
            return .split(axis: axis.flipped, ratio: ratio, pinned: true, first: first, second: second)
        }
        if let inner = first.flippingParent(of: target) {
            return .split(axis: axis, ratio: ratio, pinned: pinned, first: inner, second: second)
        }
        if let inner = second.flippingParent(of: target) {
            return .split(axis: axis, ratio: ratio, pinned: pinned, first: first, second: inner)
        }
        return nil
    }
}
