import Foundation

/// The 3, 2, 1 that runs between pressing Record and the capture starting. Pure: the controller owns one value,
/// performs the returned effects (one one-shot timer per step, then the real start), and tags every timer with the
/// token it was given so a tick from a cancelled countdown does nothing.
public struct RecordlyCountdown: Equatable, Sendable {
    public typealias State = RecordlyCountdownBox.State
    public typealias Event = RecordlyCountdownBox.Event
    public typealias Effect = RecordlyCountdownBox.Effect

    public static let seconds = RecordlyCountdownBox.seconds
    public static let noSourceNotice = RecordlyCountdownBox.noSourceNotice
    public static let sourceLostNotice = RecordlyCountdownBox.sourceLostNotice

    private var machine = RecordlyCountdownBox.Machine()

    public private(set) var state: State {
        get { machine.state }
        set { machine.state = newValue }
    }

    public init() {}

    public var isCounting: Bool { machine.isCounting }

    public var remaining: Int? { machine.remaining }

    public mutating func send(_ event: Event) -> [Effect] {
        RecordlyCountdownBox.send(&machine, event)
    }
}
