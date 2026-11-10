import Foundation
import Testing
@testable import ZeusCore

/// The Jev re-run and key-field fixes live in the app target, which this test target cannot import;
/// these pin the one ZeusCore rule they rely on (the local cap never exceeds US$10).
@Suite struct W6IntegBTests {
    @Test func jevCapIsNeverAboveTen() {
        #expect(JevBudgetStore.maxCap <= 10)
        #expect(min(25, JevBudgetStore.maxCap) == JevBudgetStore.maxCap)
    }
}
