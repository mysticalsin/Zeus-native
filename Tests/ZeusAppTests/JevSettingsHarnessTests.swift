import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Jev settings isolated app profile")
struct JevSettingsHarnessTests {
    @MainActor
    @Test func syntheticCenterNeverReadsOrWritesUserPreferencesOrProviders() async {
        let standard = UserDefaults.standard
        let ledgerBefore = standard.data(forKey: JevBudgetStore.key)
        let engineBefore = standard.object(forKey: IntelligenceEngine.settingsKey)

        let center = IntelligenceCenter.isolatedSettingsTestCenter()
        await center.refreshBudget()
        #expect(!center.hasJevKey)
        #expect(center.jevReservationStatus == .reconciliationRequired)

        #expect(standard.object(forKey: IntelligenceEngine.settingsKey) as? String == engineBefore as? String)

        let ordinary = await center.decide("synthetic UI safety check")
        #expect(ordinary.decision == nil)
        let forced = await center.decide("synthetic UI safety check", forceJev: true)
        #expect(forced.decision == nil)
        #expect(center.jevReservationStatus == .reconciliationRequired)

        await center.reconcileJevPending(.billed(inputTokens: 250))
        #expect(center.jevReservationStatus == .clear)
        #expect(center.jevBudget.inputTokens == 250)
        #expect(standard.data(forKey: JevBudgetStore.key) == ledgerBefore)
        #expect(standard.object(forKey: IntelligenceEngine.settingsKey) as? String == engineBefore as? String)
    }
}
