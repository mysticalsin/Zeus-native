import Foundation

/// The life of the tiling key tap, as a pure state machine. The tap runs on its own thread with its own run loop, so
/// its creation, its removal and the system's complaints arrive from different threads; one value under one lock
/// decides what each of them may do. The owner turns every returned effect into the matching system call.
///
/// - `off`: no tap, no thread.
/// - `starting`: the tap exists and its thread is installing it.
/// - `live`: the thread has installed the tap and is servicing it.
/// - `stopping`: a stop was asked for and the thread has not ended yet. Nothing starts and nothing is re-enabled.
/// - `failed`: the system kept turning the tap off. It stays off, with its thread, until a stop removes it.
public struct TileTapLife: Equatable, Sendable {
    public enum State: Equatable, Sendable { case off, starting, live, stopping, failed }

    public enum Event: Equatable, Sendable {
        /// The owner wants the tap running.
        case startRequested
        /// The system would not create the tap.
        case createFailed
        /// The tap thread added the tap to its run loop and turned it on.
        case installed
        /// The system turned the tap off; the health rule has judged how often.
        case systemDisabled(TileTapHealth.Verdict)
        /// The owner wants the tap gone.
        case stopRequested
        /// The tap thread has ended (the port is invalidated and the source removed before it does).
        case threadEnded
    }

    public enum Effect: Equatable, Sendable {
        case none
        /// Create the tap and start its thread.
        case createTap
        /// Turn the tap on.
        case enableTap
        /// Turn the tap off and leave it off.
        case disableTap
        /// Ask the tap thread to remove the source, invalidate the port and end.
        case tearDown
    }

    public private(set) var state: State = .off

    public init() {}

    /// A tap that exists and is wanted: it is being installed or it is live.
    public var isRunning: Bool { state == .starting || state == .live }

    public mutating func handle(_ event: Event) -> Effect {
        switch (state, event) {
        case (.off, .startRequested):
            state = .starting
            return .createTap
        case (.starting, .createFailed):
            state = .off
            return .none
        case (.starting, .installed):
            state = .live
            return .none
        case (.live, .startRequested):
            return .enableTap
        case (.starting, .systemDisabled(let verdict)), (.live, .systemDisabled(let verdict)):
            switch verdict {
            case .reenable:
                return .enableTap
            case .giveUp:
                state = .failed
                return .disableTap
            }
        case (.failed, .systemDisabled):
            return .disableTap
        case (.starting, .stopRequested), (.live, .stopRequested), (.failed, .stopRequested):
            state = .stopping
            return .tearDown
        case (_, .threadEnded):
            state = .off
            return .none
        default:
            // Off ignores everything that needs a tap. Stopping ignores everything but the end of its thread. A failed
            // tap ignores a start, and a started or live one ignores a repeated start or install.
            return .none
        }
    }
}

/// Actions the key tap hands to the main actor. The tap thread pushes; the main actor pops one entry per drain.
/// A held focus key repeats faster than a window scan runs, so a run of focus requests collapses to the newest one:
/// at most one scan waits behind a running one. A held nudge key repeats too, but each repeat moves the split a step
/// that must not be lost, so a run of equal nudges collapses to one entry with a step count: the owner applies all the
/// steps and lays the windows out once. Every other action is kept, in order. Pure: the caller keeps it under its own
/// lock.
public struct TileActionMailbox: Sendable {
    /// The most steps one nudge entry carries: enough to cross the whole ratio range, so nothing a held key could still
    /// move is lost, and a long wait on a busy main actor cannot grow the count without limit.
    public static let maxNudgeSteps = 16

    private struct Entry: Sendable {
        var action: TileAction
        var count = 1
    }

    private var entries: [Entry] = []
    /// A drain has been asked for and has not popped yet.
    private var scheduled = false

    public init() {}

    /// The waiting actions, in the order they will run.
    public var pending: [TileAction] { entries.map(\.action) }

    /// Adds `action`. Returns true when the caller must schedule one drain, false when one is already scheduled.
    public mutating func push(_ action: TileAction) -> Bool {
        if case .focus = action, case .focus? = entries.last?.action {
            entries[entries.count - 1] = Entry(action: action)
        } else if case .nudge = action, entries.last?.action == action {
            entries[entries.count - 1].count = min(entries[entries.count - 1].count + 1, Self.maxNudgeSteps)
        } else {
            entries.append(Entry(action: action))
        }
        defer { scheduled = true }
        return !scheduled
    }

    /// The next action, how many steps it stands for (more than one only for nudges), and whether another drain is
    /// needed for the ones behind it. Nil when nothing waits, which also makes the mailbox idle, so the next push asks
    /// for a drain. The main actor runs the action after this returns: a push that arrives meanwhile schedules a drain
    /// of its own and merges with the others behind it.
    public mutating func pop() -> (action: TileAction, count: Int, more: Bool)? {
        guard !entries.isEmpty else {
            scheduled = false
            return nil
        }
        let entry = entries.removeFirst()
        scheduled = !entries.isEmpty
        return (entry.action, entry.count, scheduled)
    }

    /// Forgets every waiting action and is idle again. For a tap that stopped or restarted.
    public mutating func reset() {
        entries.removeAll()
        scheduled = false
    }
}
