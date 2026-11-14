import Foundation

/// What the layout knows between key presses: one tree per display, the windows the owner released, the window
/// the keys act on, and the order windows were last focused in (most recent first). A value, so a key press
/// builds the next state without touching the last.
public struct TileLayoutState: Equatable, Sendable {
    public var trees: [UInt32: TileTree]
    /// Windows left out of the layout for this session: released by the owner, or that would not move.
    public var floating: Set<TileWindowID>
    /// The window the keys act on, tiled or not.
    public var focused: TileWindowID?
    public var recency: [TileWindowID]

    public init(trees: [UInt32: TileTree] = [:], floating: Set<TileWindowID> = [], focused: TileWindowID? = nil,
                recency: [TileWindowID] = []) {
        self.trees = trees
        self.floating = floating
        self.focused = focused
        self.recency = recency
    }

    /// The display and tree that hold `window`, lowest display id first so the answer never depends on
    /// dictionary order.
    public func location(of window: TileWindowID) -> (displayID: UInt32, tree: TileTree)? {
        for key in trees.keys.sorted() {
            if let tree = trees[key], tree.contains(window) { return (key, tree) }
        }
        return nil
    }

    /// Every tiled window, lowest display id first, each tree in tree order.
    public var tiledWindows: [TileWindowID] {
        trees.keys.sorted().flatMap { trees[$0]?.windows ?? [] }
    }

    /// Puts `window` first in the focus history.
    public mutating func noteFocus(_ window: TileWindowID) {
        recency.removeAll { $0 == window }
        recency.insert(window, at: 0)
    }
}

/// What the app must do after a key action has been resolved against the layout.
public enum TileEffect: Equatable, Sendable {
    case none
    /// Give this window keyboard focus.
    case focus(TileWindowID)
    /// The tree or the released set changed: read the windows again and lay them out.
    case relayout
    case togglePause
    case showKeys
}

/// Turns a `TileAction` into the next layout state and one thing for the app to do. Pure: no window, no clock,
/// no system call. An action that has nothing to do changes nothing and answers `.none`.
public enum TileResolver {
    /// The share of a split one nudge moves.
    public static let nudgeStep = 0.05

    public static func resolve(_ action: TileAction, in state: TileLayoutState, displays: [TileDisplay],
                               config: TileConfig) -> (state: TileLayoutState, effect: TileEffect) {
        switch action {
        case .focus(let direction): return focus(direction, state, displays, config)
        case .swap(let direction): return swap(direction, state, displays, config)
        case .flipSplit: return flip(state)
        case .toggleFloat: return toggleFloat(state)
        case .nudge(let direction): return nudge(direction, state)
        case .retile: return (state, .relayout)
        case .togglePause: return (state, .togglePause)
        case .showKeys: return (state, .showKeys)
        case .maximizeToggle: return (state, .none)
        }
    }

    // MARK: Frames

    /// The frames of every tree, on every display, in one map: focus moves across displays.
    private static func allFrames(_ state: TileLayoutState, _ displays: [TileDisplay], _ config: TileConfig) -> [TileWindowID: TileRect] {
        var out: [TileWindowID: TileRect] = [:]
        for display in displays {
            guard let tree = state.trees[display.id] else { continue }
            out.merge(TileFrames.frames(of: tree, display: display.visibleFrame, config: config)) { first, _ in first }
        }
        return out
    }

    // MARK: Actions

    private static func focus(_ direction: TileDirection, _ state: TileLayoutState, _ displays: [TileDisplay],
                              _ config: TileConfig) -> (state: TileLayoutState, effect: TileEffect) {
        var next = state
        let target: TileWindowID?
        if let from = state.focused, state.location(of: from) != nil {
            target = TileOps.neighbour(of: from, direction: direction, frames: allFrames(state, displays, config),
                                       recency: state.recency)
        } else {
            // From a window that is not tiled, a focus key goes back to the last tiled window.
            let tiled = Set(state.tiledWindows)
            target = state.recency.first { tiled.contains($0) } ?? state.tiledWindows.first
        }
        guard let target else { return (state, .none) }
        next.focused = target
        next.noteFocus(target)
        return (next, .focus(target))
    }

    private static func swap(_ direction: TileDirection, _ state: TileLayoutState, _ displays: [TileDisplay],
                             _ config: TileConfig) -> (state: TileLayoutState, effect: TileEffect) {
        // A swap stays on one display: sending a window to another display is a later slice.
        guard let from = state.focused, let place = state.location(of: from),
              let display = displays.first(where: { $0.id == place.displayID }) else { return (state, .none) }
        let frames = TileFrames.frames(of: place.tree, display: display.visibleFrame, config: config)
        guard let other = TileOps.neighbour(of: from, direction: direction, frames: frames, recency: state.recency) else {
            return (state, .none)
        }
        var next = state
        next.trees[place.displayID] = TileOps.swap(from, other, in: place.tree)
        return (next, .relayout)
    }

    private static func flip(_ state: TileLayoutState) -> (state: TileLayoutState, effect: TileEffect) {
        guard let from = state.focused, let place = state.location(of: from) else { return (state, .none) }
        let flipped = TileOps.flip(at: from, in: place.tree)
        guard flipped != place.tree else { return (state, .none) }
        var next = state
        next.trees[place.displayID] = flipped
        return (next, .relayout)
    }

    private static func nudge(_ direction: TileDirection, _ state: TileLayoutState) -> (state: TileLayoutState, effect: TileEffect) {
        guard let from = state.focused, let place = state.location(of: from) else { return (state, .none) }
        let nudged = TileOps.nudgeRatio(at: from, direction: direction, step: nudgeStep, in: place.tree)
        guard nudged != place.tree else { return (state, .none) }
        var next = state
        next.trees[place.displayID] = nudged
        return (next, .relayout)
    }

    private static func toggleFloat(_ state: TileLayoutState) -> (state: TileLayoutState, effect: TileEffect) {
        guard let from = state.focused else { return (state, .none) }
        var next = state
        if state.floating.contains(from) {
            // Back in: the next layout pass inserts it.
            next.floating.remove(from)
            return (next, .relayout)
        }
        guard let place = state.location(of: from) else { return (state, .none) }
        next.floating.insert(from)
        next.trees[place.displayID] = TileOps.remove(from, from: place.tree)
        return (next, .relayout)
    }
}
