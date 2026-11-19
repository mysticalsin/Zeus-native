import Foundation

// When the meeting-start detector runs. It is on only when a meeting is near: otherwise it waits for the
// microphone listeners and for one wake-up two minutes before the next calendar meeting. Pure; the app applies
// the plan and gathers the facts.

public enum ScribeDetectorPlan: Equatable, Sendable {
    /// Nothing runs: no timer, no microphone listeners, no calendar reads.
    case stopped
    /// Nothing is near. The microphone listeners wait, and the app wakes at `wakeAt`; nil sets no wake.
    case listening(wakeAt: Date?)
    /// A meeting is near: read the signals every few seconds as the backup to the listeners.
    case polling

    /// How far ahead the calendar is read, and so the longest the detector sleeps without reading it again.
    public static let lookAhead: TimeInterval = 24 * 3_600

    /// Off with the machine idle is `stopped`: the choice is followed at once, but a start or a recording the
    /// machine still owns keeps the detector reading until the machine is idle. Near means a calendar meeting
    /// inside its window, a call app holding the microphone, or a machine that is not idle. Anything else
    /// listens, waking at the earlier of the next meeting's heads-up and the end of the look-ahead.
    public static func plan(mode: ScribeAutoStartMode, machineIdle: Bool, micActive: Bool,
                            slots: [ScribeCalendarSlot], now: Date) -> ScribeDetectorPlan {
        if mode == .off && machineIdle { return .stopped }
        if !machineIdle || micActive || slots.contains(where: { isNear($0, at: now) }) { return .polling }
        let ahead = now.addingTimeInterval(lookAhead)
        let headsUps = slots.compactMap { slot -> Date? in
            let wake = slot.start.addingTimeInterval(-ScribeMeetingStartPolicy.leadWindow)
            return wake > now ? wake : nil
        }
        return .listening(wakeAt: min(headsUps.min() ?? ahead, ahead))
    }

    /// A meeting counts from `leadWindow` before its start until `lateWindow` after it, and never past its end.
    static func isNear(_ slot: ScribeCalendarSlot, at date: Date) -> Bool {
        if let end = slot.end, date >= end { return false }
        let until = slot.start.timeIntervalSince(date)
        return until <= ScribeMeetingStartPolicy.leadWindow && -until <= ScribeMeetingStartPolicy.lateWindow
    }
}

/// One scan at a time. A wake that arrives while a scan runs is not lost and not doubled: the scan runs once
/// more when the first ends.
public struct ScribeScanGate: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case scanning
        /// A wake arrived during the scan.
        case scanningDirty
    }

    public enum Event: Equatable, Sendable {
        case wake
        case finished
    }

    public enum Effect: Equatable, Sendable {
        case scan
    }

    public private(set) var state: State = .idle

    public init() {}

    @discardableResult
    public mutating func handle(_ event: Event) -> Effect? {
        switch (state, event) {
        case (.idle, .wake):
            state = .scanning
            return .scan
        case (.scanning, .wake), (.scanningDirty, .wake):
            state = .scanningDirty
            return nil
        case (.scanning, .finished):
            state = .idle
            return nil
        case (.scanningDirty, .finished):
            state = .scanning
            return .scan
        case (.idle, .finished):
            return nil
        }
    }
}
