import Foundation

/// The sprite poses the Memory mascot uses. Raw values are the names of the bundled mascot poses and clips.
public enum ScribeMascotPose: String, Equatable, Sendable {
    case walking
    case curious
    case idle
    case welcome
    case searching
}

/// Where Zeus is and what he is doing in the Memory window's bottom lane. Pure: it holds no clock, every
/// event carries the time, so each transition is a plain function the tests can step through.
///
/// Modes and what moves between them:
///
///     sitting  --goTo(x)--------------> walking   (a different place to stand)
///     sitting  --hover(x)-------------> looking   (turns toward the item under the pointer)
///     walking  --hover(x)-------------> looking   (stops where he is)
///     walking  --arrived (tick)-------> sitting
///     looking  --hoverEnded-----------> walking if a walk is waiting, else sitting
///     any      --searchStarted--------> reading   (stands still while a search is typed)
///     reading  --searchEnded----------> resumes: looking, walking or sitting
///     sitting, looking, walking --emptyShown--> waving (the "No meetings yet" state)
///     waving   --emptyHidden or after wavingSeconds (tick)--> resumes
///
/// Reading wins over waving, waving over looking, looking over walking. `goTo` while reading, waving or looking is
/// remembered and walked once nothing holds him. Only walking, looking, waving and reading animate; sitting is a
/// still frame, so a quiet window runs no clock at all.
public struct ScribeMascot: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case walking, looking, sitting, waving, reading
    }

    public enum Event: Equatable, Sendable {
        /// Stand somewhere else: a fraction of the lane, 0 (left edge) to 1 (right edge).
        case goTo(Double)
        /// The pointer is over an item at that lane position.
        case hover(Double)
        case hoverEnded
        case searchStarted
        case searchEnded
        case emptyShown
        case emptyHidden
        /// Time passed: finishes a walk that has arrived and a wave that has gone on long enough.
        case tick
    }

    /// Lane widths per second.
    public static let walkSpeed = 0.3
    public static let wavingSeconds: TimeInterval = 3.2

    public private(set) var mode: Mode = .sitting
    /// Where he stands when not walking. A fraction of the lane.
    public private(set) var restX: Double
    /// 1 faces right, -1 faces left.
    public private(set) var facing: Double = 1
    /// When the current mode began, for the sprite clip.
    public private(set) var modeStart: TimeInterval = 0

    private var walkFrom: Double
    private var walkTo: Double
    private var walkStart: TimeInterval = 0
    private var destination: Double
    private var lookX: Double?
    private var searching = false
    private var emptyState = false

    public init(startX: Double = 0.15) {
        let x = Self.clamp(startX)
        restX = x
        walkFrom = x
        walkTo = x
        destination = x
    }

    public var isAnimating: Bool { mode != .sitting }

    /// Where he is at `now`: halfway along the walk while walking, else where he stands.
    public func x(at now: TimeInterval) -> Double {
        guard mode == .walking else { return restX }
        let distance = abs(walkTo - walkFrom)
        guard distance > 0 else { return walkTo }
        let travelled = max(0, now - walkStart) * Self.walkSpeed
        return walkFrom + (walkTo - walkFrom) * min(1, travelled / distance)
    }

    /// True while a `tick` would change something (a walk arrived, a wave ran long enough).
    public func needsTick(at now: TimeInterval) -> Bool {
        switch mode {
        case .walking: return now >= walkStart + walkDuration
        case .waving: return now - modeStart >= Self.wavingSeconds
        case .looking, .sitting, .reading: return false
        }
    }

    public var pose: ScribeMascotPose {
        switch mode {
        case .walking: return .walking
        case .looking: return .curious
        case .sitting: return .idle
        case .waving: return .welcome
        case .reading: return .searching
        }
    }

    /// What Reduce Motion shows: no walking, the pose of the mode he is heading for, at the place he is heading for.
    public var stillFrame: (x: Double, pose: ScribeMascotPose) {
        if mode == .walking { return (x: walkTo, pose: ScribeMascotPose.idle) }
        return (x: restX, pose: pose)
    }

    public mutating func send(_ event: Event, at now: TimeInterval) {
        settle(at: now)
        switch event {
        case .goTo(let target):
            destination = Self.clamp(target)
            if mode == .sitting || mode == .walking { beginWalkIfNeeded(at: now) }
        case .hover(let x):
            lookX = Self.clamp(x)
            switch mode {
            case .sitting, .walking: stand(at: now); enter(.looking, at: now)
            case .looking: break
            case .waving, .reading: break
            }
            if mode == .looking { faceLook() }
        case .hoverEnded:
            lookX = nil
            if mode == .looking { resume(at: now) }
        case .searchStarted:
            searching = true
            if mode != .reading { stand(at: now); enter(.reading, at: now) }
        case .searchEnded:
            searching = false
            if mode == .reading { resume(at: now) }
        case .emptyShown:
            emptyState = true
            if mode == .sitting || mode == .walking || mode == .looking {
                stand(at: now)
                enter(.waving, at: now)
            }
        case .emptyHidden:
            emptyState = false
            if mode == .waving { resume(at: now) }
        case .tick:
            if mode == .waving, now - modeStart >= Self.wavingSeconds { resume(at: now) }
        }
    }

    // MARK: Transitions

    private var walkDuration: TimeInterval { abs(walkTo - walkFrom) / Self.walkSpeed }

    /// A finished walk ends where it was going, whatever event arrives first.
    private mutating func settle(at now: TimeInterval) {
        guard mode == .walking, now >= walkStart + walkDuration else { return }
        restX = walkTo
        resume(at: walkStart + walkDuration)
    }

    private mutating func stand(at now: TimeInterval) {
        if mode == .walking { restX = x(at: now) }
    }

    private mutating func enter(_ next: Mode, at now: TimeInterval) {
        mode = next
        modeStart = now
    }

    private mutating func faceLook() {
        guard let lookX, lookX != restX else { return }
        facing = lookX > restX ? 1 : -1
    }

    /// Nothing holds him any more: the strongest thing still wanted decides.
    private mutating func resume(at now: TimeInterval) {
        if searching {
            enter(.reading, at: now)
        } else if lookX != nil {
            enter(.looking, at: now)
            faceLook()
        } else if abs(destination - restX) > 0.001 {
            beginWalkIfNeeded(at: now)
        } else {
            enter(.sitting, at: now)
        }
    }

    private mutating func beginWalkIfNeeded(at now: TimeInterval) {
        let from = x(at: now)
        guard abs(destination - from) > 0.001 else {
            restX = from
            if mode != .sitting { enter(.sitting, at: now) }
            return
        }
        restX = from
        walkFrom = from
        walkTo = destination
        walkStart = now
        facing = destination > from ? 1 : -1
        enter(.walking, at: now)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(1, max(0, value))
    }
}
