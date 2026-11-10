import Foundation
import Testing
@testable import ZeusCore

@Suite struct UserMemoryPersistenceDateTests {
    @Test func saveLoadPreservesCreatedDatesAndOrderAtISO8601Precision() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserMemoryPersistenceDateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = UserMemoryPersistence(url: directory.appendingPathComponent("memory.json"))
        let oldest = Date(timeIntervalSince1970: 1_700_000_000)
        let middle = Date(timeIntervalSince1970: 1_700_000_060)
        let newest = Date(timeIntervalSince1970: 1_700_000_120)
        let newestRuleID = UUID()
        let oldestRuleID = UUID()
        let newestFactID = UUID()
        let middleFactID = UUID()
        let store = UserMemoryStore(
            rules: [
                .init(id: newestRuleID, text: "newest rule", created: newest),
                .init(id: oldestRuleID, text: "oldest rule", created: oldest)
            ],
            facts: [
                .init(id: newestFactID, text: "newest fact", source: .you, created: newest),
                .init(id: middleFactID, text: "middle fact", source: .learned, created: middle)
            ]
        )

        try persistence.save(store)
        let loaded = persistence.load()

        #expect(loaded.rules.map(\.id) == [newestRuleID, oldestRuleID])
        #expect(loaded.rules.map(\.text) == ["newest rule", "oldest rule"])
        #expect(loaded.rules.map(\.created) == [newest, oldest])
        #expect(loaded.facts.map(\.id) == [newestFactID, middleFactID])
        #expect(loaded.facts.map(\.text) == ["newest fact", "middle fact"])
        #expect(loaded.facts.map(\.source) == [.you, .learned])
        #expect(loaded.facts.map(\.created) == [newest, middle])
        #expect(loaded.rules.map(\.created) == loaded.rules.map(\.created).sorted(by: >))
        #expect(loaded.facts.map(\.created) == loaded.facts.map(\.created).sorted(by: >))
    }
}
