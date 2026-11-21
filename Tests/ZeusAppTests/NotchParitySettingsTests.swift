import Foundation
import Testing
@testable import ZeusCore

@Suite struct NotchParitySettingsTests {
    @Test func settingsRowsAreReachableAndHeldRowsSayNotAvailableYet() {
        let rows = NotchParitySettings.rows
        let expected = (1...25).map { String(format: "R-%03d", $0) }
        #expect(rows.map(\.id) == expected)
        #expect(Set(rows.map(\.id)).count == 25)
        #expect(rows.allSatisfy(\.isReachable))
        let held = rows.filter(\.isHeld)
        #expect(held.map(\.id) == ["R-014", "R-024", "R-025"])
        for row in held {
            #expect(row.status == "not available yet")
            #expect(row.control == .unavailable)
            #expect(row.canTurnOn == false)
            #expect(NotchParitySettings.turnOn(row.id) == false)
        }
        let wave2 = ["R-015", "R-016", "R-017", "R-018", "R-019", "R-020", "R-022", "R-023"]
        for id in wave2 {
            let row = rows.first { $0.id == id }
            #expect(row?.status == "Off")
            #expect(row?.canTurnOn == false)
            #expect(NotchParitySettings.turnOn(id) == false)
        }
        #expect(rows.allSatisfy { !$0.title.isEmpty })
    }
}
