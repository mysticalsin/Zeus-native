import Foundation

/// Maps an event's own timestamp onto a `Date` the gesture machine can subtract.
///
/// The first stamp anchors the clock. Later stamps keep their delta, so a tap that is
/// handled late is still as long as the events say, not as long as the queue delay.
public struct EventClock: Equatable, Sendable {
    public var originStamp: TimeInterval
    public var originDate: Date

    public init(originStamp: TimeInterval, originDate: Date) {
        self.originStamp = originStamp
        self.originDate = originDate
    }

    public func date(stamp: TimeInterval) -> Date {
        originDate.addingTimeInterval(stamp - originStamp)
    }
}
