import Foundation

public enum TileDirection: String, Codable, Sendable, CaseIterable {
    case left, right, up, down
}

/// What a bound key asks for. Pure data: the engine resolves it against a tree and the app applies the result.
public enum TileAction: Hashable, Sendable {
    /// Move focus to the nearest tiled window that way.
    case focus(TileDirection)
    /// Exchange the focused window with the neighbour that way; focus stays on the moved window.
    case swap(TileDirection)
    /// Turn the focused window's split from columns to rows, or back, and pin it.
    case flipSplit
    /// Take the focused window out of the layout, or put it back.
    case toggleFloat
    /// Stop or resume arranging windows.
    case togglePause
    /// Lay every window out again from the current tree.
    case retile
    /// Move the nearest matching split edge: see `TileOps.nudgeRatio`.
    case nudge(TileDirection)
    /// Show the list of keys.
    case showKeys
    /// Declared for the Spaces slice. Nothing resolves it yet, and no default key is bound to it.
    case maximizeToggle

    /// Every action, in a fixed order.
    public static let all: [TileAction] =
        TileDirection.allCases.map { TileAction.focus($0) }
        + TileDirection.allCases.map { TileAction.swap($0) }
        + [.flipSplit, .toggleFloat, .togglePause, .retile]
        + TileDirection.allCases.map { TileAction.nudge($0) }
        + [.showKeys, .maximizeToggle]

    /// The stable name used in stored keymaps. Never rename one.
    public var id: String {
        switch self {
        case .focus(let direction): "focus.\(direction.rawValue)"
        case .swap(let direction): "swap.\(direction.rawValue)"
        case .flipSplit: "flipSplit"
        case .toggleFloat: "toggleFloat"
        case .togglePause: "togglePause"
        case .retile: "retile"
        case .nudge(let direction): "nudge.\(direction.rawValue)"
        case .showKeys: "showKeys"
        case .maximizeToggle: "maximizeToggle"
        }
    }

    /// The action stored under `id`, or nil for a name this build does not know.
    public init?(id: String) {
        guard let match = Self.all.first(where: { $0.id == id }) else { return nil }
        self = match
    }
}
