import Foundation
import Testing
@testable import ZeusCore

@Suite("Jev default monthly limit")
struct JevDefaultCapTests {
    private func freshSuite() -> String { "zeus.test.jevdefaultcap.\(UUID().uuidString)" }

    @Test func defaultIsTenDollars() {
        #expect(JevBudgetStore.defaultCap == 10)
    }

    @Test func freshStoreUsesTheDefault() {
        let suite = freshSuite()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(JevBudgetStore(suite: suite).load().monthlyCap == 10)
    }

    @Test func oldPayloadWithNoCapGetsTheDefault() throws {
        let suite = freshSuite()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let legacy = JevBudget(monthlyCap: nil)
        let data = try JSONEncoder().encode(legacy)
        UserDefaults(suiteName: suite)?.set(data, forKey: JevBudgetStore.key)
        #expect(JevBudgetStore(suite: suite).load().monthlyCap == 10)
    }

    @Test func aCapTheOwnerSavedIsKept() {
        let suite = freshSuite()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = JevBudgetStore(suite: suite)
        store.save(JevBudget(monthlyCap: 4))
        #expect(store.load().monthlyCap == 4)
        #expect(JevBudgetStore(suite: suite).load().monthlyCap == 4)
    }

    @Test func removingTheCapStaysOff() {
        let suite = freshSuite()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = JevBudgetStore(suite: suite)
        let updated = store.updateCap(nil)
        #expect(updated?.monthlyCap == nil)
        #expect(store.load().monthlyCap == nil)
    }

    @Test func usageIsKeptWhenTheDefaultApplies() throws {
        let suite = freshSuite()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        var legacy = JevBudget(monthlyCap: nil)
        legacy.record(inputTokens: 1_000)
        UserDefaults(suiteName: suite)?.set(try JSONEncoder().encode(legacy), forKey: JevBudgetStore.key)
        let loaded = JevBudgetStore(suite: suite).load()
        #expect(loaded.monthlyCap == 10)
        #expect(loaded.inputTokens == 1_000)
    }
}
