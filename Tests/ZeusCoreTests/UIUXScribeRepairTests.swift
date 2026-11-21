import Foundation
import Testing

/// Scribe surfaces from the UI/UX catalog. These assertions fail until the sites are repaired.
@Suite("UI UX scribe repairs")
struct UIUXScribeRepairTests {
    /// ZB-UIUX-A11Y-037 to ZB-UIUX-A11Y-093, ZB-UIUX-TYPE-003, ZB-UIUX-MOTION-004 to ZB-UIUX-MOTION-010, and ZB-UIUX-GLASS-002.
    /// Speaker editors stay deferred.
    private static let owned = [
        "Sources/Zeus/Scribe/ScribeEndWindow.swift",
        "Sources/Zeus/Scribe/ScribeIdleView.swift",
        "Sources/Zeus/Scribe/ScribeMeetingCardView.swift",
        "Sources/Zeus/Scribe/ScribeMemoryWindow.swift",
        "Sources/Zeus/Scribe/ScribePage.swift",
        "Sources/Zeus/Scribe",
        "Sources/Zeus/Scribe/ScribeLiveParts.swift",
        "Sources/Zeus/Scribe/ScribeOpenAnimation.swift",
        "Sources/Zeus/Scribe/ScribeDynamicType.swift",
        "Sources/Zeus/Scribe/ScribeMotionTokens.swift",
    ]

    @Test func scribeContractSitesStayClosed() throws {
        let root = try #require(UIUXRepo.root())
        let actual = UIUXAudit.scan(root: root)
        let open = actual.filter { Self.owned.contains($0.file) }
        #expect(open.isEmpty)
        #expect(!actual.contains { $0.kind == "dynamic-type" && $0.surface == "Scribe" })
    }
}
