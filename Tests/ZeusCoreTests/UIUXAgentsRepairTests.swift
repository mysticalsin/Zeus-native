import Foundation
import Testing

/// Agent surfaces from the UI/UX catalog. These assertions fail until the sites are repaired.
@Suite("UI UX agents repairs")
struct UIUXAgentsRepairTests {
    /// ZB-UIUX-A11Y-001 to ZB-UIUX-A11Y-008, ZB-UIUX-TYPE-001, and ZB-UIUX-GLASS-001.
    private static let owned = [
        "Sources/Zeus/Agents/AgentCardsUI.swift",
        "Sources/Zeus/Agents/OtherAgents.swift",
        "Sources/Zeus/Agents/BackgroundAgentTracker.swift",
        "Sources/Zeus/Agents",
        "Sources/Zeus/Agents/AgentsDynamicType.swift",
    ]

    @Test func agentsContractSitesStayClosed() throws {
        let root = try #require(UIUXRepo.root())
        let actual = UIUXAudit.scan(root: root)
        let open = actual.filter { Self.owned.contains($0.file) }
        #expect(open.isEmpty)
        #expect(!actual.contains { $0.kind == "dynamic-type" && $0.surface == "Agents" })
    }
}
