import Testing
@testable import ZeusCore

@Suite("Event tap timeout")
struct EventTapWatchTests {
    @Test func aTimeoutAndAUserDisableTurnTheTapBackOn() {
        #expect(EventTapWatch.step(.timeout) == .reenable)
        #expect(EventTapWatch.step(.userDisabled) == .reenable)
    }

    @Test func anOrdinaryEventIsDelivered() {
        #expect(EventTapWatch.step(.event) == .deliver)
    }

    @Test func everyTimeoutIsReenabled() {
        var steps: [EventTapWatch.Step] = []
        for _ in 0..<5 {
            steps.append(EventTapWatch.step(.timeout))
        }
        #expect(steps == Array(repeating: .reenable, count: 5))
    }
}
