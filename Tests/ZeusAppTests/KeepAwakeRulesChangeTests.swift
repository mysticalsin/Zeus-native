import Foundation
import Testing
@testable import Zeus

/// The music hold reads the session's battery floor and heat setting. It hears about a change through
/// `onRulesChange`, even when no session is running.
@Suite @MainActor struct KeepAwakeRulesChangeTests {
    @Test func changingTheBatteryFloorOrTheHeatSettingTellsTheListener() {
        let session = KeepAwakeSession()
        let floor = session.batteryFloor
        let hot = session.endWhenHot
        defer {
            session.onRulesChange = {}
            session.batteryFloor = floor
            session.endWhenHot = hot
        }
        var calls = 0
        session.onRulesChange = { calls += 1 }
        #expect(!session.isActive, "no session is running")
        session.batteryFloor = floor == 0 ? 5 : 0
        #expect(calls == 1)
        session.endWhenHot = !hot
        #expect(calls == 2)
    }
}
