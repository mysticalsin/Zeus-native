import Foundation

/// One admitted window, as the driver reports it. The Accessibility element stays inside the app's driver:
/// the id's index is assigned by element identity, so the id is the element identity as far as ZeusCore goes.
public struct TileWindowRef: Equatable, Sendable {
    public var id: TileWindowID
    public var bundleID: String
    /// In engine coordinates: origin at the top left of the main display, y growing downward.
    public var frame: TileRect

    public init(id: TileWindowID, bundleID: String, frame: TileRect) {
        self.id = id
        self.bundleID = bundleID
        self.frame = frame
    }

    public var pid: Int32 { id.pid }
}

/// What the layout needs from the system to arrange windows. The Accessibility version is the only real one;
/// tests use a fake. Every frame crossing it is in engine coordinates.
@MainActor
public protocol TilingWindowDriver: AnyObject {
    /// Whether Accessibility is on. Without it every other call does nothing and reports nothing.
    var isTrusted: Bool { get }
    /// The connected displays with their visible areas.
    func displays() -> [TileDisplay]
    /// The windows on the current Space that pass admission under `config`, every one read fresh in this call.
    /// A window the call could not read in time is left out, never reported from an earlier call. Empty without
    /// Accessibility.
    func windows(config: TileConfig) -> [TileWindowRef]
    /// False when the last `windows(config:)` could not read every app. A window missing from an incomplete
    /// listing is unknown, not gone: the caller keeps its slot and does not write to it.
    var lastPassComplete: Bool { get }
    /// Moves and resizes `window`, then reads the frame back. True only when it landed within the tolerance.
    /// Only a window the last `windows(config:)` returned can be written; any other id is refused.
    func setFrame(_ frame: TileRect, for window: TileWindowID) -> Bool
    /// Brings `window` to the front and gives it keyboard focus. Does nothing for a window the last
    /// `windows(config:)` did not return.
    func focus(_ window: TileWindowID)
}

/// Gives each window of each app a number that is never used again in this session.
public struct TileIDAllocator: Sendable {
    private var last: [Int32: Int] = [:]

    public init() {}

    public mutating func next(pid: Int32) -> TileWindowID {
        let index = (last[pid] ?? 0) + 1
        last[pid] = index
        return TileWindowID(pid: pid, index: index)
    }
}

/// One window that must move.
public struct TileMove: Equatable, Sendable {
    public var id: TileWindowID
    public var target: TileRect
    public var current: TileRect

    public init(id: TileWindowID, target: TileRect, current: TileRect) {
        self.id = id
        self.target = target
        self.current = current
    }
}

/// What a layout pass has to do: the windows to move, the ones already in place, and tree slots with no window.
public struct TileMovePlan: Equatable, Sendable {
    public var moves: [TileMove]
    /// Windows already within the tolerance of their frame. They are not written, so nothing cascades.
    public var inPlace: [TileWindowID]
    /// Slots of the tree with no live window to move, or no usable frame to give.
    public var missing: [TileWindowID]

    public init(moves: [TileMove], inPlace: [TileWindowID], missing: [TileWindowID]) {
        self.moves = moves
        self.inPlace = inPlace
        self.missing = missing
    }
}

/// Matches the windows the driver found to the slots of a tree. Pure.
public enum TilePlanner {
    /// The windows the engine may arrange: admission's answer checked again against the config and the
    /// displays. Floating and excluded windows, windows below the minimum size, windows on no display and
    /// repeated ids are dropped. Discovery order is kept.
    public static func eligible(_ windows: [TileWindowRef], config: TileConfig, displays: [TileDisplay]) -> [TileWindowRef] {
        var seen = Set<TileWindowID>()
        var kept: [TileWindowRef] = []
        for window in windows {
            guard !config.floating.contains(window.id),
                  !config.excludedBundleIDs.contains(window.bundleID),
                  window.frame.width >= config.minTileSize, window.frame.height >= config.minTileSize,
                  TileDisplays.display(for: window.frame, in: displays) != nil,
                  seen.insert(window.id).inserted else { continue }
            kept.append(window)
        }
        return kept
    }

    /// The moves that put each window of `tree` into its engine frame on `display`, in tree order. A window not in
    /// the tree, and a floating one, is never touched.
    public static func plan(tree: TileTree, display: TileDisplay, config: TileConfig, windows: [TileWindowRef]) -> TileMovePlan {
        let frames = TileFrames.frames(of: tree, display: display.visibleFrame, config: config)
        var live: [TileWindowID: TileWindowRef] = [:]
        for window in windows where live[window.id] == nil { live[window.id] = window }

        var plan = TileMovePlan(moves: [], inPlace: [], missing: [])
        for leaf in tree.windows where !config.floating.contains(leaf) {
            guard let target = frames[leaf], !target.isEmpty, let window = live[leaf] else {
                plan.missing.append(leaf)
                continue
            }
            if TileReadBack.matches(window.frame, target) {
                plan.inPlace.append(leaf)
            } else {
                plan.moves.append(TileMove(id: leaf, target: target, current: window.frame))
            }
        }
        return plan
    }
}

public enum TileApplyState: Equatable, Sendable {
    case applied
    /// Accessibility is off: no frame was written.
    case accessibilityOff
}

/// What a pass did.
public struct TileApplyOutcome: Equatable, Sendable {
    public var state: TileApplyState
    /// Written and landed.
    public var moved: [TileWindowID] = []
    /// Already in place: not written.
    public var skipped: [TileWindowID] = []
    /// Written but did not land. The caller marks each one floating for the session and lays the rest out again.
    public var refused: [TileWindowID] = []
    /// Not started because the time budget ran out. Not floating: a later pass takes them.
    public var deferred: [TileWindowID] = []
    /// The frame asked for in every write, landed or not, for `TileSelfWrites`.
    public var intended: [TileWindowID: TileRect] = [:]

    public init(state: TileApplyState) { self.state = state }
}

/// Runs a plan through a driver: each move once, in order, with no retry.
@MainActor
public enum TileApplier {
    /// Seconds one pass may take before it stops starting new writes.
    public static let defaultBudget = 0.75

    public static func apply(_ plan: TileMovePlan, with driver: some TilingWindowDriver, budget: Double = TileApplier.defaultBudget,
                             clock: () -> Double = { ProcessInfo.processInfo.systemUptime }) -> TileApplyOutcome {
        guard driver.isTrusted else { return TileApplyOutcome(state: .accessibilityOff) }
        var outcome = TileApplyOutcome(state: .applied)
        outcome.skipped = plan.inPlace
        let start = clock()
        var outOfTime = false
        for move in plan.moves {
            if !outOfTime, clock() - start >= budget { outOfTime = true }
            if outOfTime {
                outcome.deferred.append(move.id)
                continue
            }
            outcome.intended[move.id] = move.target
            if driver.setFrame(move.target, for: move.id) {
                outcome.moved.append(move.id)
            } else {
                outcome.refused.append(move.id)
            }
        }
        return outcome
    }
}
