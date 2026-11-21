import Foundation
import Testing
@testable import ZeusCore

@Suite("Gesture event clock")
struct EventClockTests {
    @Test func aLateQueueKeepsTheEventDelta() {
        let origin = Date(timeIntervalSince1970: 10_000)
        let clock = EventClock(originStamp: 50, originDate: origin)
        let down = clock.date(stamp: 50)
        let up = clock.date(stamp: 50.1)
        #expect(down == origin)
        #expect(up.timeIntervalSince(down) == 0.1)
    }

    @Test func theHoldBoundaryUsesTheStampNotTheDequeueGap() {
        let origin = Date(timeIntervalSince1970: 10_000)
        let clock = EventClock(originStamp: 1, originDate: origin)
        let began = clock.date(stamp: 1)
        let up = clock.date(stamp: 1 + NotchGestureAdapter<NotchPointerSample>.holdAfter - 0.01)
        #expect(up.timeIntervalSince(began) < NotchGestureAdapter<NotchPointerSample>.holdAfter)
    }
}
