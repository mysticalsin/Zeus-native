import Foundation
import Testing
@testable import ZeusCore

@Suite struct BuddyVisibilityTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func defaultIsOnlyWhenCalled() {
        #expect(BuddyShow.stored(nil) == .onCall)
        #expect(BuddyShow.stored("garbage") == .onCall)
        #expect(BuddyShow.stored("always") == .always)
        #expect(BuddyShow.onCall.title == "When I call him")
        #expect(BuddyVisibility().policy == .onCall)
    }

    @Test func hiddenUntilCalledThenFadesTwoSecondsAfterTheTurn() {
        var state = BuddyVisibility()
        #expect(!state.isVisible(at: t0))
        // The talk shortcut.
        state.begin(.call)
        #expect(state.isVisible(at: t0))
        // The turn takes over from the call.
        state.begin(.turn)
        state.end(.call, at: t0.addingTimeInterval(0.3))
        #expect(state.isVisible(at: t0.addingTimeInterval(30)))
        // The turn ends: still there for 2 seconds, then gone.
        let ended = t0.addingTimeInterval(31)
        state.end(.turn, at: ended)
        #expect(state.isVisible(at: ended.addingTimeInterval(1.9)))
        #expect(!state.isVisible(at: ended.addingTimeInterval(2.0)))
        #expect(state.nextChange(after: ended) == ended.addingTimeInterval(2))
        #expect(state.nextChange(after: ended.addingTimeInterval(3)) == nil)
    }

    @Test func overlappingReasonsKeepHimUntilTheLastEnds() {
        var state = BuddyVisibility()
        state.begin(.turn)
        state.begin(.pointing)
        state.end(.turn, at: t0)
        #expect(state.isVisible(at: t0.addingTimeInterval(10)))
        #expect(state.nextChange(after: t0) == nil)
        state.end(.pointing, at: t0.addingTimeInterval(10))
        #expect(state.isVisible(at: t0.addingTimeInterval(11.5)))
        #expect(!state.isVisible(at: t0.addingTimeInterval(12.5)))
    }

    @Test func beginningAgainCancelsTheFade() {
        var state = BuddyVisibility()
        state.begin(.turn)
        state.end(.turn, at: t0)
        state.begin(.caption)
        #expect(state.isVisible(at: t0.addingTimeInterval(5)))
        // Ending a reason that is not active does nothing.
        state.end(.pointing, at: t0.addingTimeInterval(5))
        #expect(state.isVisible(at: t0.addingTimeInterval(6)))
    }

    @Test func alwaysAndNever() {
        var always = BuddyVisibility(policy: .always)
        #expect(always.isVisible(at: t0))
        always.begin(.turn); always.end(.turn, at: t0)
        #expect(always.isVisible(at: t0.addingTimeInterval(60)))
        #expect(always.nextChange(after: t0) == nil)
        var never = BuddyVisibility(policy: .never)
        never.begin(.turn)
        #expect(!never.isVisible(at: t0))
        // Switching policy applies at once, keeping what is active.
        never.policy = .onCall
        #expect(never.isVisible(at: t0))
    }
}

@Suite struct HomeStripTests {
    private func strip(level: Int? = 80, charging: Bool = false, plugged: Bool = false, awake: Bool = false, ended: String? = nil) -> HomeStrip {
        HomeStrip.make(batteryLevel: level, charging: charging, pluggedIn: plugged, keepAwakeActive: awake, keepAwakeLabel: "24 min",
                       keepAwakeOpenEnded: false, keepAwakeEndedText: ended)
    }

    @Test func showsOnlyWhatMatters() {
        // On battery: shown. Plugged in and full: nothing.
        #expect(strip().chips == [.battery(level: 80, charging: false, low: false)])
        #expect(!strip(level: 100, plugged: true).isVisible)
        // Desktop Mac: no battery chip.
        #expect(!strip(level: nil).isVisible)
        // Charging shows its level.
        #expect(strip(level: 50, charging: true, plugged: true).chips == [.battery(level: 50, charging: true, low: false)])
    }

    @Test func lowBatteryAndKeepAwake() {
        #expect(strip(level: 12).chips == [.battery(level: 12, charging: false, low: true)])
        // Low but plugged in is not an alarm.
        #expect(strip(level: 12, charging: true, plugged: true).chips == [.battery(level: 12, charging: true, low: false)])
        let both = strip(level: 12, awake: true)
        #expect(both.chips == [.battery(level: 12, charging: false, low: true), .keepAwake(label: "24 min", openEnded: false)])
        #expect(strip(level: 100, plugged: true, awake: true).chips == [.keepAwake(label: "24 min", openEnded: false)])
        #expect(strip(level: 100, plugged: true, ended: "Ended: battery 9%").chips == [.keepAwakeEnded("Ended: battery 9%")])
    }

    @Test func takesRoomOnlyWhenShown() {
        #expect(strip(level: 100, plugged: true).extraHeight == 0)
        #expect(strip().extraHeight == HomeStrip.height + HomeStrip.gap)
    }
}
